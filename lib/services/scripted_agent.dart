import '../agent/generation_snapshot.dart';
import 'fuzzy_policy_agent.dart';
import 'optimization_agent.dart';

/// Scripted intervention agent for the CAC training programme
/// (docs/architecture/15_PLANO_TREINO_CAC.md §2): applies exactly the listed
/// actions at exactly the listed generations and records the situation
/// (fuzzy variables, phase, champion) at each of them. Spec:
/// `param=value@generation[;param=value@generation...]`.
class ScriptedAgent extends OptimizationAgent {
  final List<({String param, double value, int generation})> script;
  final int phaseStagnationLimit;
  final Set<int> _done = {};

  ScriptedAgent(this.script, {this.phaseStagnationLimit = 150});

  factory ScriptedAgent.parse(String spec, {int phaseStagnationLimit = 150}) {
    final items = <({String param, double value, int generation})>[];
    for (final part in spec.split(';').where((p) => p.trim().isNotEmpty)) {
      final m = RegExp(r'^\s*([A-Za-z]+)=([-0-9.eE+]+)@(\d+)\s*$').firstMatch(part);
      if (m == null) throw FormatException('bad script item: $part');
      items.add((param: m[1]!, value: double.parse(m[2]!), generation: int.parse(m[3]!)));
    }
    return ScriptedAgent(items, phaseStagnationLimit: phaseStagnationLimit);
  }

  @override
  String get id => 'script';
  @override
  String get name => 'Intervenção roteirizada';
  @override
  bool get available => true;

  @override
  void processSnapshot(GenerationSnapshot s) {
    for (var i = 0; i < script.length; i++) {
      final a = script[i];
      if (_done.contains(i) || s.generation < a.generation) continue;
      _done.add(i);
      final f = fuzzyFeatures(s, phaseStagnationLimit: phaseStagnationLimit);
      final reason = 'script: ${a.param}=${a.value} at generation ${a.generation}';
      onDecision?.call(AgentDecision(
        agent: id,
        generation: s.generation,
        status: 'action',
        rationale: reason,
        actions: [ProposedAction(a.param, a.value, reason)],
        diagnosis: {
          'scheduledGeneration': a.generation,
          'features': f.map((k, v) => MapEntry(k, v.isFinite ? v : null)),
          'phase': s.phase,
          'numRegressors': s.bestModelComplexity,
          'valFreeRunFull': s.freeRunRmseValidationFull,
          'championAdmissible': s.championAdmissible,
          'parameterBefore': s.parameters[a.param],
        },
      ));
      onSuggestion?.call(a.param, a.value, reason);
    }
  }

  @override
  void dispose() {}
}
