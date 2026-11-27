import 'dart:math' as math;

import '../agent/generation_snapshot.dart';
import 'fuzzy_policy_agent.dart';
import 'optimization_agent.dart';

/// Adaptive convergence controller (CAC, docs/architecture/14_CONTROLADOR_ADAPTATIVO.md).
///
/// Every block of generations it
///  1. updates a local convergence model of the champion's validation
///     free-run error (Theil–Sen slope of L = log RMSE over a window);
///  2. scores the previous action against the forecast made when it was
///     taken (gain beyond the predicted gain);
///  3. classifies the situation with the fuzzy variables;
///  4. chooses one arm — (parameter, direction) for EVERY parameter of the
///     core's action schema, a restart, or "no action" — by Thompson
///     sampling with a prior from the expert fuzzy rules;
///  5. estimates the number of generations h until it acts again and
///     records the forecast L̂(g + h), so the estimate can be calibrated.
/// Events (no admissible champion, divergence, phase change) bring the next
/// decision forward.
class AdaptiveConvergenceController extends OptimizationAgent {
  /// Core action schema (`aegis.actions/1`), read when deciding.
  final Map<String, dynamic>? Function() actionSchema;
  final Map<String, double> Function() currentParameters;
  final FuzzyRuleBase ruleBase;
  final int phaseStagnationLimit;
  final int hMin, hMax, window;
  final double epsilon; // relevant gain in log-RMSE units (0.005 ≈ 0.5 %)
  final double priorScale, priorVariance;
  /// v2: prior advantage of "no action", drift cost away from the anchor
  /// (per max step, for fitness weights) and prior of the return-to-anchor arm.
  final double nonePrior, driftPenalty, anchorPrior;
  /// v4: rule version (3 = expert fuzzy prior, 4 = measured impact map of
  /// T1–T3), the overfitting gate on gapOS = log(val / train one-step RMSE)
  /// and the number of recent snapshots whose median gives the signal.
  final int version;
  final double overfitGate;
  final int gapWindow;
  /// v4.1: offer only arms with a measured gain (impact map prior > 0, or a
  /// positive mean reward over at least [minEvidence] uses in the table).
  final bool measuredOnly;
  final int minEvidence;
  final math.Random _rng;

  AdaptiveConvergenceController({
    required this.actionSchema,
    required this.currentParameters,
    FuzzyRuleBase? ruleBase,
    this.phaseStagnationLimit = 150,
    this.hMin = 25,
    this.hMax = 200,
    this.window = 80,
    this.epsilon = 0.005,
    this.priorScale = 0.4,
    this.priorVariance = 0.01,
    this.nonePrior = 0.25,
    this.driftPenalty = 0.5,
    this.anchorPrior = 0.1,
    this.version = 3,
    this.overfitGate = 0.15,
    this.gapWindow = 10,
    this.measuredOnly = false,
    this.minEvidence = 3,
    int seed = 1,
    Map<String, dynamic>? table,
  })  : ruleBase = ruleBase ?? FuzzyRuleBase.expert(),
        _rng = math.Random(seed) {
    if (table != null) loadTable(table);
  }

  @override
  String get id => version >= 4 ? (measuredOnly ? 'cac41' : 'cac4') : 'cac';

  bool _hasGain(String arm) {
    final st = _global[arm];
    return st != null && st.n >= minEvidence && st.sum / st.n > 0;
  }
  @override
  String get name => 'Controlador adaptativo de convergência (CAC)';
  @override
  bool get available => true;

  // ── state ────────────────────────────────────────────────────────────
  final List<(int, double)> _trace = []; // (generation, log RMSE)
  int _nextDecision = 0;
  int _lastPhase = -1;
  bool? _lastAdmissible;
  _Pending? _pending;
  final Map<String, _Stats> _global = {};
  final Map<String, _Stats> _situational = {};
  int inconclusive = 0;
  /// Fitness-weight values at the first decision (the pre-registered package).
  final Map<String, double> anchors = {};
  final List<Map<String, dynamic>> calibration = [];
  final List<double> _gaps = [];

  /// v4 overfitting signal: median of gapOS over the last [gapWindow]
  /// snapshots (null until available).
  double? overfitSignal() {
    if (_gaps.isEmpty) return null;
    final v = _gaps.sublist(math.max(0, _gaps.length - gapWindow))..sort();
    return v.length.isOdd ? v[v.length ~/ 2] : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
  }

  /// v4 gate: complexity weights may be raised only when the champion
  /// overfits (T4: gapOS 0.23–0.76 on CT, −0.10–0.04 on WH and SB).
  bool get gateOpen => (overfitSignal() ?? double.negativeInfinity) >= overfitGate;

  CacImpact _impact(String name, String kind, String dir) {
    for (final e in cacImpactMapV4) {
      if (e.arm == '$name:$dir' || e.arm == '$name:*' || (kind == 'de' && e.arm == 'de:*')) return e;
    }
    return CacImpact('$name:$dir', 'allow', -0.05, 0, 'não medido');
  }

  /// Arm statistics, for logs and persistence.
  Map<String, dynamic> tableJson() => {
        'schema': 'aegis.cac_table/1',
        'global': _global.map((k, v) => MapEntry(k, v.toJson())),
        'situational': _situational.map((k, v) => MapEntry(k, v.toJson())),
      };

  void loadTable(Map<String, dynamic> t) {
    (t['global'] as Map?)?.forEach((k, v) => _global[k as String] = _Stats.fromJson(v as Map));
    (t['situational'] as Map?)?.forEach((k, v) => _situational[k as String] = _Stats.fromJson(v as Map));
  }

  // ── convergence model ───────────────────────────────────────────────
  /// Theil–Sen slope of L over the last [window] points: (ρ = −slope, σ_L, L now).
  ({double rho, double sigma, double level})? convergence() {
    if (_trace.length < 5) return null;
    final pts = _trace.sublist(math.max(0, _trace.length - window));
    final slopes = <double>[];
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        final dg = pts[j].$1 - pts[i].$1;
        if (dg > 0) slopes.add((pts[j].$2 - pts[i].$2) / dg);
      }
    }
    if (slopes.isEmpty) return null;
    slopes.sort();
    final slope = slopes[slopes.length ~/ 2];
    final inter = <double>[for (final p in pts) p.$2 - slope * p.$1]..sort();
    final b = inter[inter.length ~/ 2];
    var ss = 0.0;
    for (final p in pts) {
      final r = p.$2 - (b + slope * p.$1);
      ss += r * r;
    }
    final sigma = math.sqrt(ss / math.max(1, pts.length - 2));
    return (rho: math.max(0.0, -slope), sigma: sigma, level: pts.last.$2);
  }

  /// Generations until the next decision (§5 of the design).
  int horizon(double rho, double sigma) {
    // Stalled (less than ε expected even over hMax): act again soon.
    if (rateTerm(rho) == 'stalled') return hMin;
    var h = (sigma + epsilon) / rho; // detection horizon: gain ε above the noise
    if (rateTerm(rho) == 'fast') h = math.max(h, hMax / 2); // fast: do not disturb
    final c = h.clamp(hMin.toDouble(), hMax.toDouble());
    return (c / 5).round() * 5;
  }

  String rateTerm(double rho) {
    if (rho * hMin >= 4 * epsilon) return 'fast';
    if (rho * hMax >= epsilon) return 'slow';
    return 'stalled';
  }

  // ── consultation ─────────────────────────────────────────────────────
  @override
  void processSnapshot(GenerationSnapshot s) {
    final rmse = s.freeRunRmseValidationFull ?? s.bestModelValidationRMSE;
    if (rmse != null && rmse.isFinite && rmse > 0) _trace.add((s.generation, math.log(rmse)));
    final tr = s.bestModelRMSE, va = s.bestModelValidationRMSE;
    if (va != null && tr.isFinite && va.isFinite && tr > 0 && va > 0) _gaps.add(math.log(va / tr));
    final g = s.generation;
    final model = convergence();

    // Score a pending action whose horizon has elapsed.
    final p = _pending;
    if (p != null && g >= p.dueGeneration) {
      _pending = null;
      final now = model?.level;
      if (now == null || s.phase != p.phase) {
        inconclusive++;
      } else {
        final denom = math.max(epsilon, (p.level0 - p.forecast).abs());
        final r = ((p.forecast - now) / denom).clamp(-1.0, 1.0).toDouble();
        _update(p.arm, p.situation, r);
        calibration.add({'generation': p.generation, 'h': p.dueGeneration - p.generation,
          'forecast': p.forecast, 'observed': now, 'arm': p.arm, 'reward': r});
      }
    }

    // Events that bring the decision forward.
    final events = <String>[];
    if (_lastPhase >= 0 && s.phase != _lastPhase) events.add('phase_change');
    if (s.championAdmissible == false && _lastAdmissible != false) events.add('inadmissible_champion');
    if (s.freeRunDiverged) events.add('free_run_diverged');
    _lastPhase = s.phase;
    _lastAdmissible = s.championAdmissible;
    if (g < _nextDecision && events.isEmpty) return;
    if (_pending != null && events.isEmpty) return; // still measuring the last action

    if (model == null) {
      _nextDecision = g + hMin;
      onDecision?.call(AgentDecision(agent: id, generation: g, status: 'insufficient_evidence',
          rationale: 'convergence model needs at least 5 points'));
      return;
    }
    final feats = fuzzyFeatures(s, phaseStagnationLimit: phaseStagnationLimit);
    final situation = _situation(feats, model.rho, s);
    final premature = _term(feats, 'div') == 'low' && rateTerm(model.rho) == 'stalled' &&
        (_term(feats, 'stag') == 'medium' || _term(feats, 'stag') == 'high');
    final arms = _arms(s, premature: premature);
    final prior = _fuzzyPrior(feats);
    String best = 'none';
    var bestDraw = -double.infinity;
    for (final e in arms.entries) {
      final key = e.key.key;
      // v3: the expert fuzzy prior applies to DE operators only, not to fitness weights.
      // v4: the measured impact map replaces the hand-written fuzzy prior.
      final fz = version >= 4 || anchors.containsKey(e.value.param) ? 0.0 : (prior[key] ?? 0.0);
      final p0 = fz + e.value.impactPrior + e.value.priorAdj + (key == 'none' ? nonePrior : 0.0);
      final draw = _draw(key, situation, p0);
      if (draw > bestDraw) { bestDraw = draw; best = key; }
    }
    final chosen = arms.entries.firstWhere((e) => e.key.key == best).value;
    // v4: weight actions are judged only after their measured transient.
    final h = math.max(horizon(model.rho, model.sigma), chosen.minHorizon);
    final forecast = model.level - model.rho * h;
    _nextDecision = g + h;
    final diag = {
      'situation': situation, 'rho': model.rho, 'sigmaL': model.sigma, 'rate': rateTerm(model.rho),
      'h': h, 'forecastLogRmse': forecast, 'levelLogRmse': model.level, 'events': events,
      'arms': arms.length, 'chosen': best,
      if (version >= 4) 'overfitGap': overfitSignal(),
      if (version >= 4) 'gateOpen': gateOpen,
    };
    if (best == 'none') {
      _pending = _Pending('none', situation, g, g + h, model.level, forecast, s.phase);
      onDecision?.call(AgentDecision(agent: id, generation: g, status: 'no_action',
          rationale: 'no arm expected to beat the forecast; next decision in $h generations', diagnosis: diag));
      return;
    }
    final spec = chosen;
    final reason = 'CAC: ${spec.param} ${spec.value} (situação $situation, ρ=${model.rho.toStringAsExponential(2)}, '
        'próxima decisão em $h gerações)';
    _pending = _Pending(best, situation, g, g + h, model.level, forecast, s.phase);
    onDecision?.call(AgentDecision(agent: id, generation: g, status: 'action', rationale: reason,
        actions: [ProposedAction(spec.param, spec.value, reason)], diagnosis: diag));
    onSuggestion?.call(spec.param, spec.value, reason);
  }

  @override
  void onActionResult(Map<String, dynamic> result) {
    // Rejected by the core (range, step, cooldown, budget): not an experience.
    if (result['accepted'] != true) _pending = null;
  }

  @override
  void dispose() {}

  /// Arms offered for this snapshot: arm key → proposed value (for tests and logs).
  Map<String, double> candidateMoves(GenerationSnapshot s, {bool premature = false}) =>
      _arms(s, premature: premature).map((k, v) => MapEntry(k.key, v.value));

  // ── arms over every parameter of the schema ───────────────────────────
  Map<MapEntry<String, int>, _Move> _arms(GenerationSnapshot s, {bool premature = false}) {
    final out = <MapEntry<String, int>, _Move>{const MapEntry('none', 0): const _Move('', 0)};
    final schema = actionSchema();
    final params = (schema?['parameters'] as List?) ?? const [];
    final allowBudget = schema?['allowBudgetActions'] == true;
    final current = currentParameters();
    final simulation = s.errorMode == 'simulation';
    for (final raw in params) {
      final m = raw as Map;
      final name = m['name'] as String;
      final kind = (m['kind'] as String?) ?? '';
      if ((m['budget'] == true || m['budgetAffecting'] == true) && !allowBudget) continue;
      if (simulation && (name == 'freeRunPenalty' || name == 'freeRunHorizon')) continue; // inert
      if (version >= 4 && _impact(name, kind, '*').rule == 'masked') continue; // measured inert
      final lo = (m['min'] as num).toDouble(), hi = (m['max'] as num).toDouble();
      final integer = m['integer'] == true;
      final maxStep = (m['maxStep'] as num?)?.toDouble() ?? (m['max_step'] as num?)?.toDouble() ?? (hi - lo);
      if (kind == 'event') {
        // Restart events: a partial restart (30 %) is always an option; the
        // cataclysmic restart (CHC, Eshelman 1991: everything but the elite,
        // which the core always keeps) only when the diagnosis is premature
        // convergence (low diversity, stalled convergence, stagnation).
        final ip = version >= 4 ? _impact(name, kind, '*').prior : 0.0;
        // v4.1: no measured gain → offered only once the arm table shows one.
        if (version >= 4 && measuredOnly && ip <= 0 && !_hasGain('$name:partial')) continue;
        out[MapEntry('$name:partial', 1)] = _Move(name, 0.3.clamp(lo, hi).toDouble(), 0.0, ip);
        if (premature) out[MapEntry('$name:cataclysm', 1)] = _Move(name, hi, 0.0, ip);
        continue;
      }
      final cur = current[name] ?? (s.parameters[name]);
      if (cur == null) continue;
      // v2 anchors: fitness weights start at the package values; moving away
      // costs prior mass, and a return-to-anchor arm is offered.
      final weight = kind == 'weight';
      if (weight) anchors.putIfAbsent(name, () => cur);
      final anchor = anchors[name];
      // v3: fitness weights move in tenths of the max step (one γ step of 0.05
      // collapsed every CT model to K = 3, irreversibly); DE parameters in halves.
      var step = weight ? maxStep / 10 : maxStep / 2;
      if (integer) step = math.max(1, step.roundToDouble());
      for (final dir in const [1, -1]) {
        var v = (cur + dir * step).clamp(lo, hi).toDouble();
        if (integer) v = v.roundToDouble();
        if ((v - cur).abs() < 1e-12) continue;
        var adj = 0.0;
        if (weight && anchor != null && maxStep > 0) {
          final away = ((v - anchor).abs() - (cur - anchor).abs()) / maxStep;
          if (away > 0) adj = -driftPenalty * away * 2; // per half step = one move
        }
        var ip = 0.0, mh = 0;
        if (version >= 4) {
          final imp = _impact(name, kind, dir > 0 ? '+' : '-');
          if (imp.rule == 'blocked') continue;
          if (imp.rule == 'gated' && !gateOpen) continue;
          ip = imp.prior;
          // α↑ is neutral on WH/SB and helpful on CT: positive prior only with the gate.
          if (name == 'alpha' && dir > 0 && gateOpen) ip = 0.2;
          // v4.1 (T5: "within the noise on CT" is not harmless on WH): only arms
          // with a measured gain; the others need positive evidence in the table.
          final key = '$name:${dir > 0 ? '+' : '-'}';
          if (measuredOnly && ip <= 0 && !_hasGain(key)) continue;
          mh = imp.horizon;
          if (weight && mh == 0) mh = 200; // any weight move: measured transient (T2)
        }
        out[MapEntry('$name:${dir > 0 ? '+' : '-'}', dir)] = _Move(name, v, adj, ip, mh);
      }
      if (weight && anchor != null && (cur - anchor).abs() > 1e-12) {
        final back = cur + (anchor - cur).clamp(-maxStep, maxStep);
        out[MapEntry('$name:anchor', 0)] = _Move(name, integer ? back.roundToDouble() : back, anchorPrior, 0.0,
            version >= 4 ? 200 : 0);
      }
    }
    return out;
  }

  Map<String, double> _fuzzyPrior(Map<String, double> feats) {
    final prior = <String, double>{};
    for (final r in ruleBase.rules) {
      var fire = 1.0;
      for (final e in r.antecedents.entries) {
        final mf = ruleBase.variables[e.key]?[e.value];
        final x = feats[e.key] ?? double.nan;
        fire = math.min(fire, mf == null ? 0.0 : mf.mu(x));
      }
      if (fire <= 0) continue;
      final key = '${r.param}:${r.delta >= 0 ? '+' : '-'}';
      prior[key] = math.max(prior[key] ?? 0.0, priorScale * fire * r.weight);
    }
    return prior;
  }

  /// Linguistic term of highest membership for a fuzzy variable ('?' if undefined).
  String _term(Map<String, double> f, String v) {
    final x = f[v] ?? double.nan;
    final terms = ruleBase.variables[v];
    if (terms == null || x.isNaN) return '?';
    var best = '?';
    var mu = 0.0;
    terms.forEach((t, mf) { final m = mf.mu(x); if (m > mu) { mu = m; best = t; } });
    return best;
  }

  String _situation(Map<String, double> f, double rho, GenerationSnapshot s) {
    String term(String v) => _term(f, v);
    final adm = s.championAdmissible == null ? '-' : (s.championAdmissible! ? 'adm' : 'inadm');
    return 'p${s.phase}|stag=${term('stag')}|sr=${term('sr')}|div=${term('div')}|rate=${rateTerm(rho)}|$adm';
  }

  double _draw(String arm, String situation, double priorMean) {
    final gs = _global[arm], ss = _situational['$situation#$arm'];
    // Normal–normal update: prior N(priorMean, priorVariance), observation noise 0.25.
    const noise = 0.25;
    var prec = 1 / priorVariance, mean = priorMean / priorVariance;
    void add(_Stats? st, double w) {
      if (st == null || st.n == 0) return;
      prec += w * st.n / noise;
      mean += w * st.sum / noise;
    }
    add(gs, 0.3); // global evidence counts less than situational
    add(ss, 1.0);
    final mu = mean / prec, sd = math.sqrt(1 / prec);
    return mu + sd * _gauss();
  }

  double _gauss() {
    final u1 = math.max(1e-12, _rng.nextDouble()), u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  void _update(String arm, String situation, double r) {
    _global.putIfAbsent(arm, _Stats.new).add(r);
    _situational.putIfAbsent('$situation#$arm', _Stats.new).add(r);
  }
}

class _Move {
  final String param;
  final double value;
  final double priorAdj; // v2: anchor drift cost (−) or return-to-anchor prior (+)
  final double impactPrior; // v4: measured prior (impact map)
  final int minHorizon; // v4: measured transient before judging
  const _Move(this.param, this.value, [this.priorAdj = 0.0, this.impactPrior = 0.0, this.minHorizon = 0]);
}

class _Pending {
  final String arm, situation;
  final int generation, dueGeneration, phase;
  final double level0, forecast;
  _Pending(this.arm, this.situation, this.generation, this.dueGeneration, this.level0, this.forecast, this.phase);
}

class _Stats {
  int n = 0;
  double sum = 0;
  void add(double r) { n++; sum += r; }
  Map<String, dynamic> toJson() => {'n': n, 'sum': sum};
  static _Stats fromJson(Map j) => _Stats()
    ..n = (j['n'] as num).toInt()
    ..sum = (j['sum'] as num).toDouble();
}
/// CAC v4 (docs/architecture/15_PLANO_TREINO_CAC.md §11): the measured
/// impact map of T1–T3 (validation only). One entry per (parameter,
/// direction); `prior` is the prior mean in reward units, `gate` names the
/// condition under which the arm is offered, `horizon` the minimum number of
/// generations before the action is judged (measured transient).
class CacImpact {
  final String arm; // 'param:+' or 'param:-' or 'param:*'
  final String rule; // 'allow' | 'gated' | 'blocked' | 'masked'
  final double prior;
  final int horizon;
  final String evidence;
  const CacImpact(this.arm, this.rule, this.prior, this.horizon, this.evidence);
}

const cacImpactMapV4 = <CacImpact>[
  CacImpact('denominatorPenalty:+', 'gated', 0.3, 200,
      'β↑: CT 7–9/10 melhores em T1/T2 (todos os tercis de gapOS); WH/SB piora 5/5 (T2)'),
  CacImpact('alpha:+', 'allow', 0.0, 200,
      'α↑: CT −0,05 a −0,24 e métrica final melhor; WH/SB dentro do ruído (T2). Prior positivo só com o portão'),
  CacImpact('exponentPenalty:+', 'blocked', 0.0, 200,
      'δ↑: WH/SB +0,44 a +1,67, 5/5 piores; CT melhora a busca mas piora a métrica final (T1, T2)'),
  CacImpact('complexityPenalty:+', 'blocked', 0.0, 200,
      'γ↑: dano dose-dependente no CT (T1) e no WH/SB já com +0,002 (T2)'),
  CacImpact('noInputPenalty:*', 'masked', 0.0, 0,
      'ζ: inerte, pisos do currículo acima dos valores testados (T1)'),
  CacImpact('freeRunPenalty:*', 'masked', 0.0, 0, 'θ: inerte em modo simulação (placebo do T0–T2)'),
  CacImpact('freeRunHorizon:*', 'masked', 0.0, 0, 'horizonte livre: inerte em modo simulação (placebo do T1)'),
  CacImpact('stabilityPenalty:*', 'allow', -0.05, 0, 'η: dentro do ruído (T1); o veto já garante admissibilidade'),
  CacImpact('de:*', 'allow', -0.05, 0,
      'operadores do DE (F, CR, migração, imigrantes, mutação estrutural): dentro do ruído (T1)'),
  CacImpact('triggerRestart:*', 'allow', -0.05, 0, 'reinício parcial e cataclismo: dentro do ruído no CT (T1)'),
];
