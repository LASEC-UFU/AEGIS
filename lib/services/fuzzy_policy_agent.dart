import 'dart:convert';
import 'dart:math' as math;

import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

/// Membership function: trapezoid (a ≤ b ≤ c ≤ d). Triangles use b == c;
/// left/right shoulders use a == b == -inf / c == d == +inf.
class Trapezoid {
  final double a, b, c, d;
  const Trapezoid(this.a, this.b, this.c, this.d);

  double mu(double x) {
    if (x.isNaN) return 0.0;
    if (x < a || x > d) return 0.0;
    if (x >= b && x <= c) return 1.0;
    if (x < b) return b == a ? 1.0 : (x - a) / (b - a);
    return d == c ? 1.0 : (d - x) / (d - c);
  }

  List<double> toJson() => [a, b, c, d];
  factory Trapezoid.fromJson(List<dynamic> v) =>
      Trapezoid(_d(v[0]), _d(v[1]), _d(v[2]), _d(v[3]));
  static double _d(dynamic x) => x == null ? double.infinity : (x as num).toDouble();
}

/// One rule: IF all antecedents THEN param += delta (zero-order Sugeno).
class FuzzyRule {
  final String id;
  final Map<String, String> antecedents; // variable → linguistic term
  final String param;
  final double delta;
  final double weight; // rule credibility in [0, 1] (0 disables the rule)
  final String explanation;

  const FuzzyRule({
    required this.id,
    required this.antecedents,
    required this.param,
    required this.delta,
    this.weight = 1.0,
    this.explanation = '',
  });

  FuzzyRule copyWith({double? delta, double? weight}) => FuzzyRule(
    id: id,
    antecedents: antecedents,
    param: param,
    delta: delta ?? this.delta,
    weight: weight ?? this.weight,
    explanation: explanation,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'if': antecedents,
    'then': {'param': param, 'delta': delta},
    'weight': weight,
    'explanation': explanation,
  };

  factory FuzzyRule.fromJson(Map<String, dynamic> j) => FuzzyRule(
    id: j['id'] as String,
    antecedents: (j['if'] as Map).map((k, v) => MapEntry(k as String, v as String)),
    param: (j['then'] as Map)['param'] as String,
    delta: ((j['then'] as Map)['delta'] as num).toDouble(),
    weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
    explanation: (j['explanation'] as String?) ?? '',
  );
}

/// Complete, serialisable rule base (variables, terms, rules, thresholds).
class FuzzyRuleBase {
  final String name;
  final Map<String, Map<String, Trapezoid>> variables;
  final List<FuzzyRule> rules;
  final Map<String, List<double>> bounds; // param → [min, max, maxStep]
  final double evidenceThreshold;

  const FuzzyRuleBase({
    required this.name,
    required this.variables,
    required this.rules,
    required this.bounds,
    this.evidenceThreshold = 0.4,
  });

  static const double inf = double.infinity;

  /// Hand-written expert rule base (version 1). Variables:
  ///  stag — champion stagnation / phaseStagnationLimit
  ///  sr   — trial success rate
  ///  div  — unique structures / total population
  ///  gap  — (RMSE_val − RMSE_train) / RMSE_train
  ///  sim  — free-run RMSE (full validation) / one-step RMSE_val
  factory FuzzyRuleBase.expert() => FuzzyRuleBase(
    name: 'expert-v1',
    variables: {
      'stag': {
        'low': const Trapezoid(-inf, -inf, 0.15, 0.3),
        'medium': const Trapezoid(0.2, 0.4, 0.5, 0.7),
        'high': const Trapezoid(0.55, 0.8, inf, inf),
      },
      'sr': {
        'low': const Trapezoid(-inf, -inf, 0.03, 0.08),
        'medium': const Trapezoid(0.05, 0.1, 0.15, 0.3),
        'high': const Trapezoid(0.2, 0.35, inf, inf),
      },
      'div': {
        'low': const Trapezoid(-inf, -inf, 0.1, 0.2),
        'medium': const Trapezoid(0.12, 0.25, 0.35, 0.5),
        'high': const Trapezoid(0.4, 0.6, inf, inf),
      },
      'gap': {
        'ok': const Trapezoid(-inf, -inf, 0.1, 0.3),
        'high': const Trapezoid(0.2, 0.5, inf, inf),
      },
      'sim': {
        'ok': const Trapezoid(-inf, -inf, 1.5, 3.0),
        'high': const Trapezoid(2.0, 5.0, inf, inf),
      },
    },
    rules: const [
      FuzzyRule(id: 'R1', antecedents: {'stag': 'high', 'sr': 'low'}, param: 'mutationFactor', delta: 0.1,
          explanation: 'stagnation with failing trials: larger differential steps'),
      FuzzyRule(id: 'R2', antecedents: {'stag': 'high', 'div': 'low'}, param: 'reinitializationRatio', delta: 0.05,
          explanation: 'stagnation with structural collapse: more random immigrants'),
      FuzzyRule(id: 'R3', antecedents: {'stag': 'high', 'div': 'low'}, param: 'structuralMutationRate', delta: 0.05,
          explanation: 'stagnation with structural collapse: more add/delete/replace moves'),
      FuzzyRule(id: 'R4', antecedents: {'stag': 'medium', 'sr': 'low'}, param: 'crossoverRate', delta: -0.1,
          explanation: 'slowing progress: inherit fewer regressors per trial (smaller moves)'),
      FuzzyRule(id: 'R5', antecedents: {'stag': 'low', 'sr': 'high'}, param: 'mutationFactor', delta: -0.05,
          explanation: 'healthy progress: refine with smaller steps'),
      FuzzyRule(id: 'R6', antecedents: {'gap': 'high'}, param: 'complexityPenalty', delta: 0.01,
          explanation: 'validation error well above training error: more parsimony'),
      FuzzyRule(id: 'R7', antecedents: {'sim': 'high'}, param: 'freeRunPenalty', delta: 0.25,
          explanation: 'simulation much worse than one-step prediction: weight free-run error'),
      FuzzyRule(id: 'R8', antecedents: {'stag': 'high', 'sr': 'low', 'div': 'high'}, param: 'migrationRate', delta: 0.05,
          explanation: 'diverse but stuck islands: exchange more individuals'),
    ],
    bounds: const {
      'mutationFactor': [0.1, 1.0, 0.3],
      'crossoverRate': [0.1, 1.0, 0.3],
      'reinitializationRatio': [0.0, 0.4, 0.2],
      'structuralMutationRate': [0.0, 0.4, 0.2],
      'complexityPenalty': [0.0, 0.2, 0.1],
      'freeRunPenalty': [0.0, 3.0, 1.0],
      'migrationRate': [0.0, 0.3, 0.2],
    },
  );

  Map<String, dynamic> toJson() => {
    'schema': 'aegis.fuzzy_rule_base/1',
    'name': name,
    'evidenceThreshold': evidenceThreshold,
    'variables': variables.map((v, terms) =>
        MapEntry(v, terms.map((t, mf) => MapEntry(t, mf.toJson().map(_enc).toList())))),
    'rules': rules.map((r) => r.toJson()).toList(),
    'bounds': bounds,
  };

  static Object? _enc(double x) => x.isInfinite ? null : x; // null = ±∞ shoulder

  factory FuzzyRuleBase.fromJson(Map<String, dynamic> j) {
    final vars = <String, Map<String, Trapezoid>>{};
    (j['variables'] as Map).forEach((v, terms) {
      vars[v as String] = (terms as Map).map((t, mf) {
        final l = (mf as List).toList();
        // null shoulders: left side → -∞, right side → +∞
        final a = l[0] == null ? -inf : (l[0] as num).toDouble();
        final b = l[1] == null ? -inf : (l[1] as num).toDouble();
        final c = l[2] == null ? inf : (l[2] as num).toDouble();
        final d = l[3] == null ? inf : (l[3] as num).toDouble();
        return MapEntry(t as String, Trapezoid(a, b, c, d));
      });
    });
    return FuzzyRuleBase(
      name: (j['name'] as String?) ?? 'custom',
      variables: vars,
      rules: (j['rules'] as List).map((r) => FuzzyRule.fromJson(r as Map<String, dynamic>)).toList(),
      bounds: (j['bounds'] as Map).map((k, v) =>
          MapEntry(k as String, (v as List).map((e) => (e as num).toDouble()).toList())),
      evidenceThreshold: (j['evidenceThreshold'] as num?)?.toDouble() ?? 0.4,
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Fuzzy features extracted from a snapshot (crisp inputs to the rule base).
Map<String, double> fuzzyFeatures(GenerationSnapshot s, {int phaseStagnationLimit = 150}) {
  final totalPop = s.islandStatuses.fold<int>(0, (a, i) => a + i.populationSize);
  final train = s.bestModelRMSE;
  final val = s.bestModelValidationRMSE ?? double.nan;
  final sim = s.freeRunRmseValidationFull ?? double.nan;
  return {
    'stag': s.globalStagnation / math.max(1, phaseStagnationLimit),
    'sr': s.successRate,
    'div': totalPop > 0 ? s.uniqueStructures / totalPop : double.nan,
    'gap': (train.isFinite && train > 0 && val.isFinite) ? (val - train) / train : double.nan,
    'sim': s.freeRunDiverged
        ? 10.0
        : ((val.isFinite && val > 0 && sim.isFinite) ? sim / val : double.nan),
  };
}

/// Interpretable local policy: every [cycleLength] generations it fires the
/// rule base, aggregates the consequents per parameter (weighted average of
/// rule deltas, strength = max firing degree × rule weight) and proposes at
/// most one action — the parameter with the largest normalised move — when
/// its strength reaches the evidence threshold. Otherwise it reports
/// "insufficient_evidence" (some rule fired weakly) or "no_action".
class FuzzyPolicyAgent extends OptimizationAgent {
  final FuzzyRuleBase ruleBase;
  final int cycleLength;
  final int parameterCooldownCycles;
  final int phaseStagnationLimit;
  final String agentId;

  int _nextEvaluation;
  int _lastSeen = -1;
  final Map<String, int> _lastChange = {};
  String? _lastParam;

  FuzzyPolicyAgent({
    FuzzyRuleBase? ruleBase,
    this.cycleLength = 25,
    this.parameterCooldownCycles = 2,
    this.phaseStagnationLimit = 150,
    String? id,
  }) : ruleBase = ruleBase ?? FuzzyRuleBase.expert(),
       agentId = id ?? 'fuzzy',
       _nextEvaluation = cycleLength;

  @override
  String get id => agentId;

  @override
  String get name => 'Agente local (fuzzy ${ruleBase.name})';

  @override
  bool get available => true;

  /// Firing degree of each rule for the given features.
  Map<String, double> firing(Map<String, double> f) {
    final out = <String, double>{};
    for (final r in ruleBase.rules) {
      var w = 1.0;
      for (final e in r.antecedents.entries) {
        final mf = ruleBase.variables[e.key]?[e.value];
        final x = f[e.key] ?? double.nan;
        w = math.min(w, mf == null ? 0.0 : mf.mu(x)); // t-norm: minimum
      }
      out[r.id] = w * r.weight;
    }
    return out;
  }

  @override
  void processSnapshot(GenerationSnapshot snapshot) {
    if (snapshot.generation <= _lastSeen) return;
    _lastSeen = snapshot.generation;
    if (snapshot.generation < _nextEvaluation) return;
    _nextEvaluation = snapshot.generation + cycleLength;

    final features = fuzzyFeatures(snapshot, phaseStagnationLimit: phaseStagnationLimit);
    final fire = firing(features);
    // Aggregate per parameter.
    final sumW = <String, double>{}, den = <String, double>{}, strength = <String, double>{};
    final why = <String, List<String>>{};
    for (final r in ruleBase.rules) {
      final w = fire[r.id] ?? 0.0;
      if (w <= 0) continue;
      sumW[r.param] = (sumW[r.param] ?? 0) + w * r.delta;
      den[r.param] = (den[r.param] ?? 0) + w;
      strength[r.param] = math.max(strength[r.param] ?? 0, w);
      (why[r.param] ??= []).add('${r.id}(${w.toStringAsFixed(2)}): ${r.explanation}');
    }
    final diagnosis = {
      'features': features.map((k, v) => MapEntry(k, v.isFinite ? v : null)),
      'firing': fire,
      'ruleBase': ruleBase.name,
    };
    if (sumW.isEmpty) {
      _emit(snapshot, 'no_action', 'nenhuma regra ativa', diagnosis);
      return;
    }
    final cooldown = cycleLength * parameterCooldownCycles;
    String? bestParam;
    double bestScore = 0;
    for (final p in sumW.keys) {
      final last = _lastChange[p];
      if (last != null && snapshot.generation - last < cooldown) continue;
      final b = ruleBase.bounds[p];
      if (b == null) continue;
      final delta = sumW[p]! / den[p]!;
      final score = strength[p]! * (delta.abs() / b[2]);
      if (strength[p]! >= ruleBase.evidenceThreshold && score > bestScore) {
        bestScore = score;
        bestParam = p;
      }
    }
    if (bestParam == null) {
      final maxStrength = strength.values.fold<double>(0, math.max);
      _emit(snapshot, 'insufficient_evidence',
          'ativação máxima ${maxStrength.toStringAsFixed(2)} abaixo do limiar '
          '${ruleBase.evidenceThreshold} ou parâmetro em cooldown', diagnosis);
      return;
    }
    final b = ruleBase.bounds[bestParam]!;
    final current = snapshot.parameters[bestParam];
    if (current == null || !current.isFinite) {
      _emit(snapshot, 'insufficient_evidence', 'valor corrente de $bestParam desconhecido', diagnosis);
      return;
    }
    final delta = (sumW[bestParam]! / den[bestParam]!).clamp(-b[2], b[2]);
    final value = (current + delta).clamp(b[0], b[1]).toDouble();
    if ((value - current).abs() < 1e-9) {
      _emit(snapshot, 'no_action', '$bestParam já no limite', diagnosis);
      return;
    }
    _lastChange[bestParam] = snapshot.generation;
    _lastParam = bestParam;
    final reason = 'Agente fuzzy: ${why[bestParam]!.join('; ')}';
    _emit(snapshot, 'action', reason, diagnosis,
        actions: [ProposedAction(bestParam, value, reason)]);
    onSuggestion?.call(bestParam, value, reason);
  }

  @override
  void onActionResult(Map<String, dynamic> result) {
    if (result['accepted'] == true || _lastParam == null) return;
    if (result['code'] != 'cooldown') _lastChange.remove(_lastParam);
    _lastParam = null;
  }

  void _emit(GenerationSnapshot s, String status, String rationale, Map<String, dynamic> diagnosis,
      {List<ProposedAction> actions = const []}) {
    onDecision?.call(AgentDecision(
      agent: id,
      generation: s.generation,
      status: status,
      rationale: rationale,
      actions: actions,
      diagnosis: diagnosis,
    ));
  }

  @override
  void dispose() {}
}
