import '../agent/generation_snapshot.dart';
import 'fuzzy_policy_agent.dart';
import 'optimization_agent.dart';

/// Scripted intervention agent for the CAC training programme
/// (docs/architecture/15_PLANO_TREINO_CAC.md §2): applies exactly the listed
/// actions at exactly the listed generations and records the situation
/// (fuzzy variables, phase, champion) at each of them.
///
/// Spec: items separated by ';', each `param=value@g` (absolute) or
/// `param+=delta@g` / `param-=delta@g` (relative to the current value at g).
/// When [actionSchema] is given, relative values are clamped to the schema
/// range (and rounded for integer parameters).
class ScriptedAgent extends OptimizationAgent {
  final List<({String param, String op, double value, int generation})> script;
  final int phaseStagnationLimit;
  final Map<String, dynamic>? Function()? actionSchema;
  final Set<int> _done = {};

  ScriptedAgent(this.script, {this.phaseStagnationLimit = 150, this.actionSchema});

  factory ScriptedAgent.parse(String spec,
      {int phaseStagnationLimit = 150, Map<String, dynamic>? Function()? actionSchema}) {
    final items = <({String param, String op, double value, int generation})>[];
    for (final part in spec.split(';').where((p) => p.trim().isNotEmpty)) {
      final m = RegExp(r'^\s*([A-Za-z]+)(\+=|-=|=)([0-9.eE+-]+)@(\d+)\s*$').firstMatch(part);
      if (m == null) throw FormatException('bad script item: $part');
      items.add((param: m[1]!, op: m[2]!, value: double.parse(m[3]!), generation: int.parse(m[4]!)));
    }
    return ScriptedAgent(items, phaseStagnationLimit: phaseStagnationLimit, actionSchema: actionSchema);
  }

  @override
  String get id => 'script';
  @override
  String get name => 'Intervenção roteirizada';
  @override
  bool get available => true;

  double _resolve(({String param, String op, double value, int generation}) a, GenerationSnapshot s) {
    if (a.op == '=') return a.value;
    final cur = s.parameters[a.param];
    if (cur == null) return double.nan;
    var v = a.op == '+=' ? cur + a.value : cur - a.value;
    final params = (actionSchema?.call()?['parameters'] as List?) ?? const [];
    for (final raw in params) {
      final m = raw as Map;
      if (m['name'] != a.param) continue;
      v = v.clamp((m['min'] as num).toDouble(), (m['max'] as num).toDouble()).toDouble();
      if (m['integer'] == true) v = v.roundToDouble();
    }
    return v;
  }

  @override
  void processSnapshot(GenerationSnapshot s) {
    for (var i = 0; i < script.length; i++) {
      final a = script[i];
      if (_done.contains(i) || s.generation < a.generation) continue;
      _done.add(i);
      final value = _resolve(a, s);
      final f = fuzzyFeatures(s, phaseStagnationLimit: phaseStagnationLimit);
      final reason = 'script: ${a.param}${a.op}${a.value} -> $value at generation ${a.generation}';
      onDecision?.call(AgentDecision(
        agent: id,
        generation: s.generation,
        status: value.isNaN ? 'skipped' : 'action',
        rationale: reason,
        actions: value.isNaN ? const [] : [ProposedAction(a.param, value, reason)],
        diagnosis: {
          'scheduledGeneration': a.generation,
          'features': f.map((k, v) => MapEntry(k, v.isFinite ? v : null)),
          'phase': s.phase,
          'numRegressors': s.bestModelComplexity,
          'valFreeRunFull': s.freeRunRmseValidationFull,
          'championAdmissible': s.championAdmissible,
          'parameterBefore': s.parameters[a.param],
          'parameterAfter': value.isNaN ? null : value,
        },
      ));
      if (!value.isNaN) onSuggestion?.call(a.param, value, reason);
    }
  }

  @override
  void dispose() {}
}
