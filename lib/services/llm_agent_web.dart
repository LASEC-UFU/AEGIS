// Web implementation of LlmAgent.
// Uses package:http (BrowserClient) for the Claude API call and reads the
// API key from localStorage so the user can persist it across sessions.
// The logic is identical to llm_agent_native.dart — only the key source differs.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;

import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

// ── localStorage helpers (defined in aegis_wasm_loader.js) ───────────────

@JS('aegisGetLocalStorage')
external JSString _jsGetLocalStorage(JSString key);

@JS('aegisSetLocalStorage')
external void _jsSetLocalStorage(JSString key, JSString value);

// ─────────────────────────────────────────────────────────────────────────

class LlmAgent implements OptimizationAgent {
  @override
  TuningSuggestion? onSuggestion;

  final String _apiKey;
  final http.Client _http = http.Client();

  int _lastCallGen = -999;
  static const int _cooldown = 50;
  bool _calling = false;

  static const String _model = 'claude-opus-4-8';

  static const String _systemPrompt =
      'You are the strategic layer supervising a Differential Evolution (DE) '
      'engine that identifies MISO rational NARX models. A deterministic '
      '"reflex" layer in the C++ core already runs every generation: it '
      'advances the AEGIS Curriculum phase, anneals the complexity penalty '
      '(gamma) and ramps the free-run penalty (theta) automatically. Your '
      'job is higher-level strategic correction — things the reflex layer '
      'cannot see, such as persistent diversity collapse, overfitting, or a '
      'phase stuck far longer than expected.\n\n'
      'Each turn you receive a JSON snapshot with:\n'
      '- generation, bestFitness, meanFitness, stdDevFitness\n'
      '- stagnationCounter: generations without improvement\n'
      '- phenotypicDiversity: population spread (0=converged, high=diverse)\n'
      '- successRate: fraction of trials that improved fitness (0–1)\n'
      '- phase (0-3) and phaseName: current AEGIS Curriculum phase '
      '(0=Structural Exploration, 1=Nonlinear Expansion, '
      '2=Parsimony & Validation, 3=Local Refinement), managed automatically '
      'by the reflex layer — you do not need to advance it yourself\n'
      '- bestModelComplexity: number of regressors in best model\n'
      '- bestModelRMSE / bestModelValidationRMSE: train and validation RMSE\n'
      '- bestModelR2: coefficient of determination (higher = better, max 1)\n'
      '- freeRunRmse: free-run (simulation) RMSE; a large gap vs '
      'bestModelRMSE means the model fits one-step-ahead but diverges in '
      'simulation (poor generalization)\n'
      '- inputContributionRatio: fraction of ERR explained by regressors '
      'that depend on an input (0=trivial/pure-autoregressive model, '
      '1=fully input-driven)\n'
      '- residualInputCorr: max correlation between residuals and inputs; '
      'high values in later phases suggest missing regressors\n'
      '- fitnessBreakdown: weighted contribution of each fitness term '
      '{rmse, bic_term, denom_term, complexity_term, exponent_term, '
      'stability_term, no_input_term, free_run_term} — use this to see '
      'which penalty currently dominates the composite fitness\n'
      '- islands[]: per-island muF, muCR, stagnation, successRate\n\n'
      'Tunable parameters and valid ranges:\n'
      '| Parameter            | Min | Max  |\n'
      '|----------------------|-----|------|\n'
      '| mutationFactor       | 0.0 | 2.0  |\n'
      '| crossoverRate        | 0.0 | 1.0  |\n'
      '| migrationRate        | 0.0 | 0.3  |\n'
      '| reinitializationRatio| 0.0 | 0.5  |\n'
      '| complexityPenalty    | 0.0 | 1.0  |\n'
      '| noInputPenalty       | 0.0 | 2.0  |\n'
      '| freeRunPenalty       | 0.0 | 2.0  |\n'
      '| freeRunHorizon       | 10  | 500  |\n'
      '| denominatorPenalty   | 0.0 | 1.0  |\n'
      '| stabilityPenalty     | 0.0 | 2.0  |\n'
      '| exponentPenalty      | 0.0 | 1.0  |\n'
      '| alpha                | 0.0 | 2.0  |\n\n'
      'Reply ONLY with one of:\n'
      '  {"proposed_changes":{"paramName":value},"reason":"brief explanation"}\n'
      'or the single word: null\n\n'
      'Heuristics:\n'
      '- Low diversity + high stagnation → increase mutationFactor or '
      'reinitializationRatio\n'
      '- bestModelValidationRMSE >> bestModelRMSE, or freeRunRmse much '
      'larger than bestModelRMSE → overfitting/divergent simulation → '
      'increase freeRunPenalty (theta) or denominatorPenalty/stabilityPenalty\n'
      '- residualInputCorr high during phase 2/3 with low input contribution '
      '→ increase noInputPenalty\n'
      '- successRate near 0 for many generations → increase mutationFactor '
      'or migrationRate\n'
      '- muCR near 1.0 with good diversity → decrease crossoverRate\n'
      '- Avoid overriding complexityPenalty/freeRunPenalty/noInputPenalty '
      'unless the engine is clearly stuck despite phase transitions — the '
      'reflex layer already manages these per phase\n'
      'Suggest at most ONE parameter. Reply null when the engine is healthy.';

  LlmAgent({String? apiKey}) : _apiKey = apiKey ?? _readKeyFromStorage();

  static String _readKeyFromStorage() {
    try {
      return _jsGetLocalStorage('ANTHROPIC_API_KEY'.toJS).toDart;
    } catch (_) {
      return '';
    }
  }

  /// Persist the key so it survives page reloads.
  static void saveKeyToStorage(String key) {
    try {
      _jsSetLocalStorage('ANTHROPIC_API_KEY'.toJS, key.toJS);
    } catch (_) {}
  }

  bool get hasApiKey => _apiKey.isNotEmpty;

  @override
  String get name => 'Claude remoto';

  @override
  bool get available => hasApiKey;

  @override
  void processSnapshot(GenerationSnapshot snap) {
    if (_calling) return;
    if (snap.generation - _lastCallGen < _cooldown) return;
    if (_apiKey.isEmpty) return;
    _lastCallGen = snap.generation;
    _callClaude(snap);
  }

  @override
  void dispose() => _http.close();

  Future<void> _callClaude(GenerationSnapshot snap) async {
    _calling = true;
    try {
      final suggestion = await _askClaude(snap);
      if (suggestion != null) {
        final param = suggestion['param'] as String;
        final value = (suggestion['value'] as num).toDouble();
        final reason = suggestion['reason'] as String? ?? '';
        onSuggestion?.call(param, value, 'Agente remoto: $reason');
      }
    } catch (_) {
      // Network failures are silent — the engine keeps running
    } finally {
      _calling = false;
    }
  }

  Future<Map<String, dynamic>?> _askClaude(GenerationSnapshot snap) async {
    final islandData = snap.islandSnapshots
        .map(
          (s) => {
            'id': s.islandId,
            'bestFitness': s.stats.bestFitness,
            'stagnation': s.stagnationCounter,
            'successRate': s.successRate,
            'muF': s.muF,
            'muCR': s.muCR,
          },
        )
        .toList();

    final userContent = jsonEncode({
      'generation': snap.generation,
      'phase': snap.phase,
      'phaseName': snap.phaseName,
      'bestFitness': snap.bestFitness,
      'meanFitness': snap.meanFitness,
      'stdDevFitness': snap.stdDevFitness,
      'stagnationCounter': snap.stagnationCounter,
      'phenotypicDiversity': snap.phenotypicDiversity,
      'successRate': snap.successRate,
      'bestModelComplexity': snap.bestModelComplexity,
      'bestModelRMSE': snap.bestModelRMSE,
      'bestModelValidationRMSE': snap.bestModelValidationRMSE,
      'bestModelR2': snap.bestModelR2,
      'freeRunRmse': snap.freeRunRmse,
      'inputContributionRatio': snap.inputContributionRatio,
      'residualInputCorr': snap.residualInputCorr,
      'fitnessBreakdown': snap.fitnessBreakdown,
      'islands': islandData,
    });

    final response = await _http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': 256,
        'system': _systemPrompt,
        'messages': [
          {'role': 'user', 'content': userContent},
        ],
      }),
    );

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (body['content'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join()
        .trim();

    if (text.isEmpty || text.toLowerCase() == 'null') return null;

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final changes = parsed['proposed_changes'] as Map<String, dynamic>?;
    if (changes == null || changes.isEmpty) return null;

    final param = changes.keys.first;
    return {
      'param': param,
      'value': changes[param],
      'reason': parsed['reason'] as String? ?? '',
    };
  }
}
