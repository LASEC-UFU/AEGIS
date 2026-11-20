// Platform-independent Claude-backed supervisor for the AEGIS engine.
//
// Dart has no official Anthropic SDK, so the Messages API is called over raw
// HTTP (package:http). Every consultation produces an AgentDecision record
// with the observation sent, the structured reply, the action proposed, the
// latency, the token usage and an estimated cost. The model can (and is told
// to) answer "insufficient evidence" instead of acting.
//
// Safety: the model never touches engine internals. Its reply is constrained
// by a JSON schema (output_config.format), validated here against the action
// bounds and validated again by the C++ core (range, max step, cooldown,
// budget lock), which can reject it. At most one action is applied per
// consultation. The agent can be disabled at any time; an in-flight reply is
// then discarded and the run is unaffected.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

/// USD per million tokens (input, output, cache read). Source: Anthropic
/// model table as cached by the claude-api reference (2026-11-03). Cache
/// writes are estimated at 1.25 × input. Costs are therefore estimates.
const Map<String, List<double>> kClaudePricing = {
  'claude-opus-5-5': [4.0, 20.0, 0.20],
  'claude-sonnet-5-5': [2.0, 10.0, 0.10],
  'claude-haiku-5-5': [0.10, 0.50, 0.01],
  'claude-fable-5-2': [8.0, 40.0, 0.20],
  'claude-opus-4-8': [5.0, 25.0, 0.50],
};

/// Parameters the LLM may propose (subset of the core action schema).
const Map<String, List<double>> kLlmActionBounds = {
  // name: [min, max, maxStep]
  'mutationFactor': [0.05, 1.0, 0.3],
  'crossoverRate': [0.0, 1.0, 0.3],
  'migrationRate': [0.0, 0.5, 0.2],
  'migrationInterval': [5, 200, 50],
  'reinitializationRatio': [0.0, 0.5, 0.2],
  'structuralMutationRate': [0.0, 0.5, 0.2],
  'complexityPenalty': [0.0, 1.0, 0.1],
  'noInputPenalty': [0.0, 5.0, 1.0],
  'freeRunPenalty': [0.0, 5.0, 1.0],
  'freeRunHorizon': [10, 500, 200],
  'denominatorPenalty': [0.0, 2.0, 0.5],
  'stabilityPenalty': [0.0, 5.0, 1.0],
  'exponentPenalty': [0.0, 1.0, 0.2],
  'triggerRestart': [0.05, 0.5, 0.5],
};

const String kLlmSystemPrompt = '''
You supervise AEGIS, a multi-island Differential Evolution engine that identifies polynomial/rational NARX models of a dynamic system from data. A deterministic curriculum inside the engine already advances phases (0 structural exploration, 1 nonlinear expansion, 2 parsimony/validation, 3 local refinement) and anneals penalties; do not try to manage phases.

Every consultation you receive one observation (schema aegis.observation/1): champion metrics on training and validation (one-step RMSE/R2, horizon-limited and full validation free-run RMSE, input contribution, residual whiteness, stability), population health (success rate, unique structures, structure entropy, stagnation in generations, per-island statistics, mean JADE parameters), the current parameter values, the effective fitness weights, alerts, and your previous decisions with the engine's response (accepted/rejected and, when known, the observed outcome). Test-set data are never shown to you and must not be requested.

Decide whether ONE bounded parameter adjustment is likely to improve the identification (lower validation free-run error without loss of stability or parsimony). Typical patterns: long stagnation with very low success rate suggests larger mutation steps or more random immigrants; collapsed structural diversity suggests restarts or structural mutation; validation error well above training error suggests more parsimony; free-run error much larger than one-step error suggests a larger free-run penalty or horizon. A healthy, improving search needs no action.

Rules:
- Propose at most one action, only from the allowed parameters, within [min, max] and with |new - current| <= maxStep. Values outside are rejected by the engine.
- If the observation does not clearly support a change (for example the search is still improving, or signals conflict), return no action and set evidence_sufficient to false or explain that the search is healthy.
- Never repeat an action the engine just rejected; respect cooldowns.
- Keep diagnosis and rationale short and specific to the numbers observed.
''';

Map<String, dynamic> llmResponseSchema() => {
  'type': 'object',
  'additionalProperties': false,
  'required': ['assessment', 'diagnosis', 'evidence_sufficient', 'actions', 'rationale'],
  'properties': {
    'assessment': {
      'type': 'string',
      'enum': [
        'healthy', 'stagnation', 'diversity_collapse', 'premature_convergence',
        'overfitting', 'unstable_or_divergent', 'input_underuse', 'other',
      ],
    },
    'diagnosis': {'type': 'string'},
    'evidence_sufficient': {'type': 'boolean'},
    'actions': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['param', 'value', 'reason'],
        'properties': {
          'param': {'type': 'string', 'enum': kLlmActionBounds.keys.toList()},
          'value': {'type': 'number'},
          'reason': {'type': 'string'},
        },
      },
    },
    'rationale': {'type': 'string'},
  },
};

class LlmAgentCore extends OptimizationAgent {
  final String Function() _apiKeyProvider;
  final http.Client _http;
  final String model;
  final String effort;
  final int consultEvery;
  final Duration timeout;
  final int maxCalls;
  final double maxCostUsd;
  final Map<String, String> extraHeaders;
  final bool serverSideFallback;

  int _lastCallGen = -1 << 30;
  bool _calling = false;
  bool _disposed = false;
  bool enabled = true;
  int calls = 0;
  double costUsd = 0;
  final List<Map<String, dynamic>> _memory = []; // previous decisions + engine responses
  Map<String, dynamic>? _lastProposal;

  LlmAgentCore({
    required String Function() apiKeyProvider,
    http.Client? client,
    this.model = 'claude-opus-5-5',
    this.effort = 'medium',
    this.consultEvery = 50,
    this.timeout = const Duration(seconds: 120),
    this.maxCalls = 200,
    this.maxCostUsd = 20.0,
    this.extraHeaders = const {},
    this.serverSideFallback = true,
  }) : _apiKeyProvider = apiKeyProvider,
       _http = client ?? http.Client();

  bool get hasApiKey => _apiKeyProvider().isNotEmpty;

  @override
  String get id => 'llm';

  @override
  String get name => 'Claude remoto ($model)';

  @override
  bool get available => hasApiKey;

  bool _due(GenerationSnapshot s) => s.generation - _lastCallGen >= consultEvery;

  @override
  void processSnapshot(GenerationSnapshot snapshot) {
    final snap = snapshot;
    if (_calling || !_due(snap)) return;
    unawaited(consult(snap)); // UI mode: never blocks the engine
  }

  @override
  Future<void> consult(GenerationSnapshot snapshot) async {
    final snap = snapshot;
    if (_calling || _disposed || !_due(snap)) return;
    _lastCallGen = snap.generation;
    final observation = snap.toObservation()..['previousDecisions'] = List.of(_memory);
    if (!enabled) return _skip(snap, 'agent disabled', observation);
    if (!hasApiKey) return _skip(snap, 'no API key configured', observation);
    if (calls >= maxCalls) return _skip(snap, 'call budget exhausted ($maxCalls)', observation);
    if (costUsd >= maxCostUsd) return _skip(snap, 'cost budget exhausted (\$$maxCostUsd)', observation);
    _calling = true;
    final sw = Stopwatch()..start();
    try {
      calls++;
      final body = {
        'model': model,
        'max_tokens': 16000,
        'system': kLlmSystemPrompt,
        'cache_control': {'type': 'ephemeral'},
        'output_config': {
          'effort': effort,
          'format': {'type': 'json_schema', 'schema': llmResponseSchema()},
        },
        if (serverSideFallback) 'fallbacks': 'default',
        'messages': [
          {
            'role': 'user',
            'content': jsonEncode({
              'observation': observation,
              'allowedActions': {
                for (final e in kLlmActionBounds.entries)
                  e.key: {'min': e.value[0], 'max': e.value[1], 'maxStep': e.value[2],
                          'current': snap.parameters[e.key]},
              },
            }),
          },
        ],
      };
      final response = await _http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': _apiKeyProvider(),
              'anthropic-version': '2026-10-21',
              'content-type': 'application/json',
              if (serverSideFallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
              ...extraHeaders,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      final latency = sw.elapsedMicroseconds / 1000.0;
      if (_disposed) return;
      if (response.statusCode != 200) {
        // Never echo request headers; the body of an error does not contain the key.
        return _error(snap, 'HTTP ${response.statusCode}: ${_truncate(response.body)}', observation, latency);
      }
      final j = jsonDecode(response.body) as Map<String, dynamic>;
      final usage = (j['usage'] as Map?)?.cast<String, dynamic>() ?? const {};
      final cost = _cost(j['model'] as String? ?? model, usage);
      costUsd += cost;
      final stop = j['stop_reason'] as String?;
      if (stop == 'refusal') {
        return _record(snap, 'refusal', 'model declined (${j['stop_details']})', observation,
            latency: latency, usage: usage, cost: cost);
      }
      if (stop == 'max_tokens') {
        return _error(snap, 'reply truncated (max_tokens)', observation, latency, usage: usage, cost: cost);
      }
      final text = ((j['content'] as List?) ?? const [])
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String)
          .join();
      final Map<String, dynamic> reply;
      try {
        reply = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return _error(snap, 'reply is not valid JSON', observation, latency, usage: usage, cost: cost);
      }
      _handleReply(snap, reply, observation, latency, usage, cost, j['model'] as String? ?? model);
    } on TimeoutException {
      _error(snap, 'timeout after ${timeout.inSeconds}s', observation, sw.elapsedMicroseconds / 1000.0);
    } catch (e) {
      _error(snap, 'request failed: ${e.runtimeType}', observation, sw.elapsedMicroseconds / 1000.0);
    } finally {
      _calling = false;
    }
  }

  void _handleReply(GenerationSnapshot snap, Map<String, dynamic> reply, Map<String, dynamic> obs,
      double latency, Map<String, dynamic> usage, double cost, String servedBy) {
    final diagnosis = {
      'assessment': reply['assessment'],
      'diagnosis': reply['diagnosis'],
      'evidenceSufficient': reply['evidence_sufficient'],
      'servedBy': servedBy,
    };
    final rationale = (reply['rationale'] as String?) ?? '';
    final raw = (reply['actions'] as List?) ?? const [];
    final evidence = reply['evidence_sufficient'] == true;
    if (raw.isEmpty || !evidence) {
      final status = evidence ? 'no_action' : 'insufficient_evidence';
      _remember(snap, status, null, rationale);
      return _record(snap, status, rationale, obs,
          diagnosis: diagnosis, latency: latency, usage: usage, cost: cost, model: servedBy);
    }
    final a = raw.first as Map<String, dynamic>;
    final param = a['param'] as String? ?? '';
    final value = (a['value'] as num?)?.toDouble() ?? double.nan;
    final bounds = kLlmActionBounds[param];
    final current = snap.parameters[param];
    String? invalid;
    if (bounds == null) {
      invalid = 'parameter not allowed';
    } else if (!value.isFinite || value < bounds[0] || value > bounds[1]) {
      invalid = 'value outside [${bounds[0]}, ${bounds[1]}]';
    } else if (param != 'triggerRestart' && current != null && (value - current).abs() > bounds[2] + 1e-12) {
      invalid = 'step larger than maxStep ${bounds[2]}';
    }
    if (raw.length > 1) diagnosis['ignoredExtraActions'] = raw.length - 1;
    if (invalid != null) {
      diagnosis['localRejection'] = invalid;
      _remember(snap, 'rejected_locally', {'param': param, 'value': value}, invalid);
      return _record(snap, 'rejected_locally', '$rationale [local validation: $invalid]', obs,
          actions: [ProposedAction(param, value, a['reason'] as String? ?? '')],
          diagnosis: diagnosis, latency: latency, usage: usage, cost: cost, model: servedBy);
    }
    final reason = 'Agente LLM ($servedBy): ${a['reason'] ?? ''}';
    _lastProposal = {'generation': snap.generation, 'param': param, 'value': value};
    _remember(snap, 'action', {'param': param, 'value': value, 'from': current}, rationale);
    _record(snap, 'action', rationale, obs,
        actions: [ProposedAction(param, value, reason)],
        diagnosis: diagnosis, latency: latency, usage: usage, cost: cost, model: servedBy);
    onSuggestion?.call(param, value, reason);
  }

  @override
  void onActionResult(Map<String, dynamic> result) {
    if (_memory.isEmpty || _lastProposal == null) return;
    _memory.last['engine'] = {
      'accepted': result['accepted'],
      'code': result['code'],
      if (result['message'] != null) 'message': result['message'],
    };
    _lastProposal = null;
  }

  void _remember(GenerationSnapshot s, String status, Map<String, dynamic>? action, String why) {
    _memory.add({
      'generation': s.generation,
      'status': status,
      'action': ?action,
      'validationRmse': s.bestModelValidationRMSE,
      'freeRunRmseValidationFull': s.freeRunRmseValidationFull,
      'rationale': _truncate(why, 200),
    });
    while (_memory.length > 6) {
      _memory.removeAt(0);
    }
  }

  double _cost(String m, Map<String, dynamic> u) {
    final p = kClaudePricing[m] ?? kClaudePricing[model];
    if (p == null) return 0;
    double n(String k) => (u[k] as num?)?.toDouble() ?? 0;
    return (n('input_tokens') * p[0] +
            n('output_tokens') * p[1] +
            n('cache_read_input_tokens') * p[2] +
            n('cache_creation_input_tokens') * p[0] * 1.25) /
        1e6;
  }

  void _skip(GenerationSnapshot s, String why, Map<String, dynamic> obs) =>
      _record(s, 'skipped', why, obs);

  void _error(GenerationSnapshot s, String why, Map<String, dynamic> obs, double latency,
      {Map<String, dynamic>? usage, double? cost}) =>
      _record(s, 'error', why, obs, latency: latency, usage: usage, cost: cost);

  void _record(GenerationSnapshot s, String status, String rationale, Map<String, dynamic> obs,
      {List<ProposedAction> actions = const [], Map<String, dynamic>? diagnosis, double? latency,
      Map<String, dynamic>? usage, double? cost, String? model}) {
    onDecision?.call(AgentDecision(
      agent: id,
      generation: s.generation,
      status: status,
      rationale: rationale,
      actions: actions,
      observation: obs,
      diagnosis: diagnosis,
      latencyMs: latency,
      usage: usage,
      costUsd: cost,
      model: model ?? this.model,
    ));
  }

  static String _truncate(String s, [int n = 300]) => s.length <= n ? s : '${s.substring(0, n)}…';

  @override
  void dispose() {
    _disposed = true;
    _http.close();
  }
}
