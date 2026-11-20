import '../agent/generation_snapshot.dart';

typedef TuningSuggestion =
    void Function(String parameter, double value, String reason);

/// Every consultation of an agent produces one decision record, including
/// "no action" and "insufficient evidence" outcomes (schema aegis.decision/1).
typedef DecisionListener = void Function(AgentDecision decision);

/// Agent modes selectable in the UI and in the experiment runner.
///  - off:    no supervision (identical runs for the same seed)
///  - local:  UCB1 bandit over heuristic candidates (LocalAdaptiveAgent)
///  - fuzzy:  interpretable Takagi–Sugeno rule base (FuzzyPolicyAgent)
///  - remote: Claude API (LlmAgent); requires an API key
enum AgentMode { off, local, fuzzy, remote }

/// One action proposed by an agent (validated again by the core).
class ProposedAction {
  final String param;
  final double value;
  final String reason;

  const ProposedAction(this.param, this.value, this.reason);

  Map<String, dynamic> toMap() => {'param': param, 'value': value, 'reason': reason};
}

/// Structured record of one agent consultation.
class AgentDecision {
  final String agent;
  final int generation;
  final DateTime time;

  /// action | no_action | insufficient_evidence | skipped | error | refusal
  final String status;
  final String rationale;
  final List<ProposedAction> actions;
  final Map<String, dynamic>? observation;
  final Map<String, dynamic>? diagnosis;
  final double? latencyMs;
  final Map<String, dynamic>? usage;
  final double? costUsd;
  final String? model;

  AgentDecision({
    required this.agent,
    required this.generation,
    required this.status,
    this.rationale = '',
    this.actions = const [],
    this.observation,
    this.diagnosis,
    this.latencyMs,
    this.usage,
    this.costUsd,
    this.model,
    DateTime? time,
  }) : time = time ?? DateTime.now().toUtc();

  Map<String, dynamic> toMap() => {
    'schema': 'aegis.decision/1',
    'agent': agent,
    'generation': generation,
    'time': time.toIso8601String(),
    'status': status,
    'rationale': rationale,
    'actions': actions.map((a) => a.toMap()).toList(),
    if (diagnosis != null) 'diagnosis': diagnosis,
    if (latencyMs != null) 'latencyMs': latencyMs,
    if (usage != null) 'usage': usage,
    if (costUsd != null) 'costUsd': costUsd,
    if (model != null) 'model': model,
    if (observation != null) 'observation': observation,
  };
}

abstract class OptimizationAgent {
  /// Called for each proposed action; the host submits it to the core.
  TuningSuggestion? onSuggestion;

  /// Called once per consultation (also when no action is proposed).
  DecisionListener? onDecision;

  /// Short identifier used in logs and as the action `source`.
  String get id;
  String get name;
  bool get available;

  /// Fire-and-forget consultation (UI mode). Must never block the engine.
  void processSnapshot(GenerationSnapshot snapshot);

  /// Awaitable consultation (lockstep experiment mode). The default simply
  /// delegates to [processSnapshot]; remote agents complete after the reply.
  Future<void> consult(GenerationSnapshot snapshot) async => processSnapshot(snapshot);

  /// Result of an action submitted on behalf of this agent (the core's
  /// ActionRecord: accepted, code, message, oldValue, newValue…).
  void onActionResult(Map<String, dynamic> result) {}

  void dispose();
}
