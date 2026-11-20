import 'dart:math' as math;

import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

/// Local adaptive supervisor: UCB1 bandit selection on top of domain
/// heuristics.
///
/// Every [cycleLength] generations the agent builds a list of candidate
/// adjustments from the snapshot (stagnation, diversity, success rate,
/// free-run divergence, overfitting, input usage). Moderate signals must
/// persist for two consecutive cycles; severe signals act immediately. A
/// parameter changed less than `cycleLength × parameterCooldownCycles`
/// generations ago is never changed again (severe or not).
///
/// UCB1 picks among eligible candidates. Arms are (parameter, direction)
/// pairs. The reward of an action is measured [rewardHorizon] generations
/// later on the champion's validation RMSE, relative to the trend observed
/// in the [rewardHorizon] generations before the action (drift baseline):
///   r = clip(scale × [(-Δrel_after) − (-Δrel_before)], −1, 1).
/// Observations spanning a curriculum phase change are inconclusive and do
/// not update the arm. Actions rejected by the core are not counted.
class LocalAdaptiveAgent extends OptimizationAgent {
  final Map<String, double> Function() _currentParameters;
  final int cycleLength;
  final int parameterCooldownCycles;
  final int rewardHorizon;
  final double ucbC;
  final double rewardScale;

  // ── UCB1 bandit state ─────────────────────────────────────────────────────
  final Map<String, _ArmStats> _arms = {};
  int _totalPulls = 0;

  // ── Scheduling ────────────────────────────────────────────────────────────
  int _nextEvaluationGeneration;
  int _lastSeenGeneration = -1;

  // ── Signal persistence (moderate signals must appear twice) ───────────────
  String? _pendingSignal;
  int _pendingCount = 0;

  // ── Cooldown: generation of the last change of each parameter ─────────────
  final Map<String, int> _lastParameterChange = {};

  // ── Reward bookkeeping ────────────────────────────────────────────────────
  final Map<String, _PendingObservation> _pendingRewards = {};
  final List<(int, double, int)> _valHistory = []; // (generation, rmseVal, phase)
  _PendingObservation? _lastSubmitted;

  int inconclusiveObservations = 0;

  LocalAdaptiveAgent({
    required Map<String, double> Function() currentParameters,
    this.cycleLength = 25,
    this.parameterCooldownCycles = 2,
    this.rewardHorizon = 50,
    this.ucbC = 0.5,
    this.rewardScale = 10.0,
  }) : _currentParameters = currentParameters,
       _nextEvaluationGeneration = cycleLength;

  @override
  String get id => 'local-ucb1';

  @override
  String get name => 'Agente local (UCB1)';

  @override
  bool get available => true;

  /// Read-only view of the bandit statistics (for logs and the UI).
  Map<String, Map<String, num>> get armStatistics => {
    for (final e in _arms.entries)
      e.key: {'pulls': e.value.pulls, 'rewards': e.value.rewards, 'avgReward': e.value.avgReward},
  };

  @override
  void processSnapshot(GenerationSnapshot snapshot) {
    if (snapshot.generation <= _lastSeenGeneration) return;
    _lastSeenGeneration = snapshot.generation;
    _recordValidation(snapshot);
    _collectRewards(snapshot);

    if (snapshot.generation < _nextEvaluationGeneration) return;
    _nextEvaluationGeneration = snapshot.generation + cycleLength;

    final params = {..._currentParameters(), ...snapshot.parameters};
    final candidates = _buildCandidates(snapshot, params);
    if (candidates.isEmpty) {
      _pendingSignal = null;
      _pendingCount = 0;
      _emit(snapshot, 'no_action', 'nenhum sinal acima dos limiares');
      return;
    }

    final topSignal = candidates.first.signal;
    if (_pendingSignal == topSignal) {
      _pendingCount++;
    } else {
      _pendingSignal = topSignal;
      _pendingCount = 1;
    }

    final cooldown = cycleLength * parameterCooldownCycles;
    final eligible = candidates.where((c) {
      final lastChange = _lastParameterChange[c.parameter];
      if (lastChange != null && snapshot.generation - lastChange < cooldown) return false;
      if (c.severe) return true; // severe: bypasses persistence, not cooldown
      return !(_pendingCount < 2 && c.signal == topSignal);
    }).toList();

    if (eligible.isEmpty) {
      _emit(snapshot, 'insufficient_evidence',
          'sinal "$topSignal" aguardando persistência ou parâmetro em cooldown',
          signals: candidates.map((c) => c.signal).toList());
      return;
    }

    final best = _ucbSelect(eligible);
    final arm = best.arm;
    _lastParameterChange[best.parameter] = snapshot.generation;
    final obs = _PendingObservation(
      arm: arm,
      preVal: snapshot.bestModelValidationRMSE ?? snapshot.bestModelRMSE,
      preTrend: _trend(snapshot.generation - rewardHorizon, snapshot.generation),
      appliedAtGeneration: snapshot.generation,
      phase: snapshot.phase,
    );
    _pendingRewards[arm] = obs;
    _lastSubmitted = obs;
    _pendingSignal = null;
    _pendingCount = 0;
    ++_totalPulls;
    _arms.putIfAbsent(arm, _ArmStats.new).pulls++;

    final reason = 'Agente local UCB1: ${best.reason} [braço ${_armSummary(arm)}]';
    _emit(snapshot, 'action', best.reason,
        actions: [ProposedAction(best.parameter, best.value, reason)],
        signals: candidates.map((c) => c.signal).toList());
    onSuggestion?.call(best.parameter, best.value, reason);
  }

  @override
  void onActionResult(Map<String, dynamic> result) {
    if (result['accepted'] == true) return;
    // The core rejected the action: undo the pull so the arm is not credited.
    final obs = _lastSubmitted;
    if (obs == null) return;
    final arm = _arms[obs.arm];
    if (arm != null && arm.pulls > 0) arm.pulls--;
    if (_totalPulls > 0) _totalPulls--;
    _pendingRewards.remove(obs.arm);
    final param = obs.arm.split(':').first;
    if (result['code'] != 'cooldown') _lastParameterChange.remove(param);
    _lastSubmitted = null;
  }

  void _emit(GenerationSnapshot s, String status, String rationale,
      {List<ProposedAction> actions = const [], List<String> signals = const []}) {
    onDecision?.call(AgentDecision(
      agent: id,
      generation: s.generation,
      status: status,
      rationale: rationale,
      actions: actions,
      diagnosis: {'signals': signals, 'totalPulls': _totalPulls},
    ));
  }

  // ── Validation history and reward ───────────────────────────────────────
  void _recordValidation(GenerationSnapshot s) {
    final v = s.bestModelValidationRMSE ?? s.bestModelRMSE;
    if (v.isFinite) _valHistory.add((s.generation, v, s.phase));
    while (_valHistory.length > 4 * rewardHorizon + 10) {
      _valHistory.removeAt(0);
    }
  }

  /// Relative change of validation RMSE between two generations (NaN if unknown).
  double _trend(int fromGen, int toGen) {
    double? a, b;
    for (final (g, v, _) in _valHistory) {
      if (g <= fromGen) a = v;
      if (g <= toGen) b = v;
    }
    if (a == null || b == null || a.abs() < 1e-300) return double.nan;
    return (b - a) / a.abs();
  }

  bool _phaseChangedBetween(int fromGen, int toGen) {
    int? phase;
    for (final (g, _, p) in _valHistory) {
      if (g < fromGen || g > toGen) continue;
      if (phase != null && p != phase) return true;
      phase = p;
    }
    return false;
  }

  void _collectRewards(GenerationSnapshot snapshot) {
    final done = <String>[];
    _pendingRewards.forEach((arm, obs) {
      if (snapshot.generation - obs.appliedAtGeneration < rewardHorizon) return;
      done.add(arm);
      final post = snapshot.bestModelValidationRMSE ?? snapshot.bestModelRMSE;
      if (_phaseChangedBetween(obs.appliedAtGeneration, snapshot.generation) ||
          !post.isFinite || !obs.preVal.isFinite || obs.preVal.abs() < 1e-300) {
        inconclusiveObservations++;
        return;
      }
      final after = -(post - obs.preVal) / obs.preVal.abs();
      final before = obs.preTrend.isFinite ? -obs.preTrend : 0.0;
      final reward = ((after - before) * rewardScale).clamp(-1.0, 1.0).toDouble();
      _arms.putIfAbsent(arm, _ArmStats.new).addReward(reward);
    });
    for (final a in done) {
      _pendingRewards.remove(a);
    }
  }

  // ── Candidate generation (domain heuristics) ────────────────────────────
  List<_Candidate> _buildCandidates(GenerationSnapshot snapshot, Map<String, double> params) {
    final list = <_Candidate>[];
    final trainRmse = snapshot.bestModelRMSE;
    final validRmse = snapshot.bestModelValidationRMSE;
    final freeRunRmse = snapshot.freeRunRmse;

    // Free-run divergence
    if (_validPositive(trainRmse) && _validPositive(freeRunRmse)) {
      final ratio = freeRunRmse! / math.max(trainRmse, 1e-12);
      final validRef = _validPositive(validRmse) ? validRmse! : trainRmse;
      if (ratio > 4.0 || freeRunRmse > math.max(0.08, validRef * 3.0)) {
        final penalty = _v(params, 'freeRunPenalty', 0.5);
        if (penalty < 1.6) {
          final c = _candidate(
            signal: 'free-run-penalty', parameter: 'freeRunPenalty', current: penalty,
            proposed: math.max(penalty + 0.15, penalty * 1.25), min: 0.0, max: 2.0,
            severe: ratio > 8.0,
            reason: 'free-run divergiu ${ratio.toStringAsFixed(1)}x; aumentando penalizacao.',
          );
          if (c != null) list.add(c);
        } else {
          final horizon = _v(params, 'freeRunHorizon', 50);
          final c = _candidate(
            signal: 'free-run-horizon', parameter: 'freeRunHorizon', current: horizon,
            proposed: math.max(horizon + 25, horizon * 1.35), min: 10, max: 500, integer: true,
            severe: ratio > 10.0,
            reason: 'free-run divergente mesmo com penalizacao alta; ampliando horizonte.',
          );
          if (c != null) list.add(c);
        }
      }
    }

    // Persistent near-zero R²: search stuck on a trivial model
    final r2 = snapshot.bestModelR2;
    final inputRatio = snapshot.inputContributionRatio;
    final stagnating = snapshot.stagnationCounter >= math.max(25, cycleLength);
    if (r2.isFinite && r2 < 0.05 && stagnating) {
      if (inputRatio != null && inputRatio.isFinite && inputRatio < 0.15) {
        final penalty = _v(params, 'noInputPenalty', 0.5);
        final c = _candidate(
          signal: 'trivial-model-relax', parameter: 'noInputPenalty', current: penalty,
          proposed: (penalty - 0.1).clamp(0.1, 2.0), min: 0.1, max: 2.0,
          severe: r2 < 0.01 && snapshot.stagnationCounter >= cycleLength * 3,
          reason: 'R²=${r2.toStringAsFixed(3)} com contribuicao de entrada baixa '
              '(${(inputRatio * 100).toStringAsFixed(0)}%); relaxando penalidade AR.',
        );
        if (c != null) list.add(c);
      }
      final ratio = _v(params, 'reinitializationRatio', 0.1);
      final c = _candidate(
        signal: 'trivial-reinit', parameter: 'reinitializationRatio', current: ratio,
        proposed: ratio + 0.08, min: 0.0, max: 0.4,
        severe: snapshot.stagnationCounter >= cycleLength * 4,
        reason: 'R² quasi-nulo por ${snapshot.stagnationCounter} gerações; reinicializando populacao.',
      );
      if (c != null) list.add(c);
    }

    // Low input contribution
    if (snapshot.phase >= 1 && inputRatio != null && inputRatio.isFinite && inputRatio < 0.25) {
      final penalty = _v(params, 'noInputPenalty', 0.5);
      final c = _candidate(
        signal: 'input-underuse', parameter: 'noInputPenalty', current: penalty,
        proposed: penalty + 0.2, min: 0.0, max: 2.0, severe: inputRatio < 0.1,
        reason: 'contribuicao das entradas = ${(inputRatio * 100).toStringAsFixed(1)}%; '
            'aumentando pressao por regressores de entrada.',
      );
      if (c != null) list.add(c);
    }

    // Stagnation with collapsed diversity
    final diversity = snapshot.phenotypicDiversity;
    final safeDiv = (diversity.isFinite && diversity < 1e20) ? diversity : 0.0;
    final collapsed = safeDiv < 0.05 || snapshot.populationVariance < 1e-5;
    final lowSuccess = snapshot.successRate < 0.04;
    if (stagnating && lowSuccess && collapsed) {
      final ratio = _v(params, 'reinitializationRatio', 0.1);
      final c = _candidate(
        signal: 'diversity-collapse', parameter: 'reinitializationRatio', current: ratio,
        proposed: ratio + 0.05, min: 0.0, max: 0.4,
        severe: snapshot.stagnationCounter >= cycleLength * 3,
        reason: 'estagnacao com diversidade colapsada; ampliando reinicializacao parcial.',
      );
      if (c != null) list.add(c);
    }

    // Stagnation with low success rate
    if (stagnating && lowSuccess) {
      final mutation = _v(params, 'mutationFactor', 0.5);
      final migration = _v(params, 'migrationRate', 0.1);
      final cm = mutation < 1.0
          ? _candidate(
              signal: 'stagnation-mutation', parameter: 'mutationFactor', current: mutation,
              proposed: mutation + 0.1, min: 0.1, max: 1.0,
              severe: snapshot.stagnationCounter >= cycleLength * 4,
              reason: 'taxa de sucesso baixa durante estagnacao; aumentando mutacao.',
            )
          : null;
      final c = cm ??
          _candidate(
            signal: 'stagnation-migration', parameter: 'migrationRate', current: migration,
            proposed: migration + 0.03, min: 0.0, max: 0.3, severe: false,
            reason: 'estagnacao; aumentando troca entre ilhas.',
          );
      if (c != null) list.add(c);
    }

    // Overfitting (validation ≫ training)
    if (_validPositive(trainRmse) && _validPositive(validRmse)) {
      final gap = validRmse! / math.max(trainRmse, 1e-12);
      if (gap > 1.5) {
        final penalty = _v(params, 'complexityPenalty', 0.01);
        final c = _candidate(
          signal: 'overfitting', parameter: 'complexityPenalty', current: penalty,
          proposed: math.max(penalty + 0.005, penalty * 1.25), min: 0.0, max: 0.2,
          severe: gap > 2.5,
          reason: 'val=${gap.toStringAsFixed(1)}x treino; reforçando parcimonia.',
        );
        if (c != null) list.add(c);
      }
    }

    // Healthy late search → reduce mutation
    if (snapshot.phase >= 2 && snapshot.successRate > 0.25 &&
        snapshot.stagnationCounter < cycleLength ~/ 2) {
      final mutation = _v(params, 'mutationFactor', 0.5);
      if (mutation > 0.4) {
        final c = _candidate(
          signal: 'healthy-refinement', parameter: 'mutationFactor', current: mutation,
          proposed: mutation - 0.05, min: 0.35, max: 1.0, severe: false,
          reason: 'busca saudavel em fase tardia; reduzindo mutacao para refinamento fino.',
        );
        if (c != null) list.add(c);
      }
    }
    return list;
  }

  // ── UCB1 selection ────────────────────────────────────────────────────────
  _Candidate _ucbSelect(List<_Candidate> candidates) {
    if (candidates.length == 1 || _totalPulls == 0) return candidates.first;
    double bestScore = -double.infinity;
    _Candidate best = candidates.first;
    for (final c in candidates) {
      final arm = _arms[c.arm];
      final score = (arm == null || arm.pulls == 0)
          ? double.infinity // untried arm → explore first
          : arm.avgReward + ucbC * math.sqrt(math.log(_totalPulls + 1) / arm.pulls);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  String _armSummary(String arm) {
    final a = _arms[arm];
    if (a == null || a.rewards == 0) return 'novo';
    return 'pulls=${a.pulls}, avgReward=${a.avgReward.toStringAsFixed(3)}';
  }

  _Candidate? _candidate({
    required String signal,
    required String parameter,
    required double current,
    required num proposed,
    required double min,
    required double max,
    required bool severe,
    required String reason,
    bool integer = false,
  }) {
    var value = proposed.toDouble().clamp(min, max).toDouble();
    if (integer) value = value.roundToDouble();
    if ((value - current).abs() < 1e-9) return null;
    return _Candidate(
      signal: signal,
      parameter: parameter,
      value: value,
      severe: severe,
      reason: reason,
      direction: value > current ? 'up' : 'down',
    );
  }

  double _v(Map<String, double> p, String name, double fallback) => p[name] ?? fallback;

  bool _validPositive(double? value) => value != null && value.isFinite && value > 0;

  @override
  void dispose() {}
}

class _ArmStats {
  int pulls = 0;
  int rewards = 0;
  double _totalReward = 0.0;
  double get avgReward => rewards > 0 ? _totalReward / rewards : 0.0;
  void addReward(double r) {
    _totalReward += r;
    rewards++;
  }
}

class _PendingObservation {
  final String arm;
  final double preVal;
  final double preTrend;
  final int appliedAtGeneration;
  final int phase;
  const _PendingObservation({
    required this.arm,
    required this.preVal,
    required this.preTrend,
    required this.appliedAtGeneration,
    required this.phase,
  });
}

class _Candidate {
  final String signal;
  final String parameter;
  final double value;
  final bool severe;
  final String reason;
  final String direction;
  const _Candidate({
    required this.signal,
    required this.parameter,
    required this.value,
    required this.severe,
    required this.reason,
    required this.direction,
  });

  String get arm => '$parameter:$direction';
}
