import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../agent/generation_snapshot.dart';

typedef TuningSuggestion = void Function(
    String param, double value, String reason);

/// LLM agent that calls the Claude API directly from Dart.
///
/// Receives [GenerationSnapshot] objects via [processSnapshot] (called from
/// the existing 200 ms polling loop in EngineNotifier) and periodically asks
/// Claude whether any DE parameter should be adjusted.
///
/// API key resolution order:
///   1. Constructor argument
///   2. ANTHROPIC_API_KEY environment variable
///   3. File `anthropic_api_key.txt` next to the executable
class LlmAgent {
  TuningSuggestion? onSuggestion;

  final String _apiKey;
  final http.Client _http = http.Client();

  int _lastCallGen = -999;
  static const int _cooldown = 50; // minimum generations between Claude calls
  bool _calling = false;

  static const String _model = 'claude-opus-4-7';

  static const String _systemPrompt =
      'You are an expert monitoring a Differential Evolution (DE) engine '
      'that identifies MISO rational NARX models.\n\n'
      'Each turn you receive a JSON snapshot with:\n'
      '- generation, bestFitness, meanFitness, stdDevFitness\n'
      '- stagnationCounter: generations without improvement\n'
      '- phenotypicDiversity: population spread (0=converged, high=diverse)\n'
      '- successRate: fraction of trials that improved fitness (0–1)\n'
      '- bestModelComplexity: number of regressors in best model\n'
      '- bestModelRMSE / bestModelValidationRMSE: train and validation RMSE\n'
      '- bestModelR2: coefficient of determination (higher = better, max 1)\n'
      '- islands[]: per-island muF, muCR, stagnation, successRate\n\n'
      'Tunable parameters and valid ranges:\n'
      '| Parameter         | Min | Max  |\n'
      '|-------------------|-----|------|\n'
      '| mutationFactor    | 0.0 | 2.0  |\n'
      '| crossoverRate     | 0.0 | 1.0  |\n'
      '| migrationRate     | 0.0 | 0.3  |\n'
      '| complexityPenalty | 0.0 | 10.0 |\n'
      '| maxRegressors     | 2   | 20   |\n\n'
      'Reply ONLY with one of:\n'
      '  {"proposed_changes":{"paramName":value},"reason":"brief explanation"}\n'
      'or the single word: null\n\n'
      'Heuristics:\n'
      '- Low diversity + high stagnation → increase mutationFactor\n'
      '- bestModelValidationRMSE >> bestModelRMSE → overfitting → increase complexityPenalty\n'
      '- Low R² and large RMSE → underfitting → decrease complexityPenalty\n'
      '- successRate near 0 for many generations → increase mutationFactor or migrationRate\n'
      '- muCR near 1.0 with good diversity → decrease crossoverRate\n'
      'Suggest at most ONE parameter. Reply null when the engine is healthy.';

  LlmAgent({String? apiKey})
      : _apiKey = apiKey ??
            Platform.environment['ANTHROPIC_API_KEY'] ??
            _readKeyFile();

  static String _readKeyFile() {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final f = File('$dir/anthropic_api_key.txt');
      if (f.existsSync()) return f.readAsStringSync().trim();
    } catch (_) {}
    return '';
  }

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Called every generation from EngineNotifier._onGeneration.
  void processSnapshot(GenerationSnapshot snap) {
    if (_calling) return;
    if (snap.generation - _lastCallGen < _cooldown) return;
    if (_apiKey.isEmpty) return;
    _callClaude(snap); // fire-and-forget; _calling flag prevents overlap
  }

  void dispose() => _http.close();

  Future<void> _callClaude(GenerationSnapshot snap) async {
    _calling = true;
    try {
      final suggestion = await _askClaude(snap);
      if (suggestion != null) {
        final param  = suggestion['param']  as String;
        final value  = (suggestion['value'] as num).toDouble();
        final reason = suggestion['reason'] as String? ?? '';
        _lastCallGen = snap.generation;
        onSuggestion?.call(param, value, reason);
        // ignore: avoid_print
        print('[LLM Agent] Gen ${snap.generation}: $param → $value ($reason)');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[LLM Agent] Error: $e');
    } finally {
      _calling = false;
    }
  }

  Future<Map<String, dynamic>?> _askClaude(GenerationSnapshot snap) async {
    final islandData = snap.islandSnapshots
        .map((s) => {
              'id':         s.islandId,
              'bestFitness':s.stats.bestFitness,
              'stagnation': s.stagnationCounter,
              'successRate':s.successRate,
              'muF':        s.muF,
              'muCR':       s.muCR,
            })
        .toList();

    final userContent = jsonEncode({
      'generation':              snap.generation,
      'bestFitness':             snap.bestFitness,
      'meanFitness':             snap.meanFitness,
      'stdDevFitness':           snap.stdDevFitness,
      'stagnationCounter':       snap.stagnationCounter,
      'phenotypicDiversity':     snap.phenotypicDiversity,
      'successRate':             snap.successRate,
      'bestModelComplexity':     snap.bestModelComplexity,
      'bestModelRMSE':           snap.bestModelRMSE,
      'bestModelValidationRMSE': snap.bestModelValidationRMSE,
      'bestModelR2':             snap.bestModelR2,
      'islands':                 islandData,
    });

    final response = await _http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key':         _apiKey,
        'anthropic-version': '2023-06-01',
        'content-type':      'application/json',
      },
      body: jsonEncode({
        'model':    _model,
        'max_tokens': 256,
        'system':   _systemPrompt,
        'messages': [
          {'role': 'user', 'content': userContent},
        ],
      }),
    );

    if (response.statusCode != 200) {
      // ignore: avoid_print
      print('[LLM Agent] API ${response.statusCode}: ${response.body}');
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (body['content'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join()
        .trim();

    if (text.isEmpty || text.toLowerCase() == 'null') return null;

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final changes = json['proposed_changes'] as Map<String, dynamic>?;
    if (changes == null || changes.isEmpty) return null;

    final param = changes.keys.first;
    return {
      'param':  param,
      'value':  changes[param],
      'reason': json['reason'] as String? ?? '',
    };
  }
}
