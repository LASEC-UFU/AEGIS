import 'dart:math' as math;

import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

/// Local adaptive supervisor using UCB1 (Upper Confidence Bound) bandit
/// selection on top of domain-specific heuristics.
///
/// Each tunable parameter is treated as a "bandit arm". Domain heuristics
/// decide WHETHER an adjustment is warranted and what direction to take;
/// UCB1 decides WHICH eligible adjustment to apply when several compete.
///
/// After each applied action the agent observes the fitness delta N
/// generations later and updates the arm's empirical reward, letting the
/// bandit gradually prefer adjustments that have historically helped.
class LocalAdaptiveAgent implements OptimizationAgent {
  @override
  TuningSuggestion? onSuggestion;

  final Map<String, double> Function() _currentParameters;
  final int cycleLength;
  final int parameterCooldownCycles;

  // ── UCB1 bandit state ─────────────────────────────────────────────────────
  final Map<String, _ArmStats> _arms = {};
  int _totalPulls = 0;

  // Reward observation window (in generations after action applied)
  static const int _rewardHorizon = 50;

  // UCB exploration constant (higher = more exploration of untried arms)
  static const double _ucbC = 0.5;

  // ── Scheduling ────────────────────────────────────────────────────────────
  int _nextEvaluationGeneration;
  int _lastSeenGeneration = -1;

  // ── Pending signal (two-window persistence for moderate signals) ──────────
  String? _pendingSignal;
  int _pendingCount = 0;

  // ── Cooldown: min generations between changes to the same parameter ───────
  final Map<String, int> _lastParameterChange = {};

  // ── Reward observation queue: parameter → (preFitness, appliedAtGen) ─────
  final Map<String, _PendingObservation> _pendingRewards = {};

  LocalAdaptiveAgent({
    required Map<String, double> Function() currentParameters,
    this.cycleLength = 25,
    this.parameterCooldownCycles = 2,
  }) : _currentParameters = currentParameters,
       _nextEvaluationGeneration = cycleLength;

  @override
  String get name => 'Agente local (UCB1)';

  @override
  bool get available => true;

  @override
  void processSnapshot(GenerationSnapshot snapshot) {
    if (snapshot.generation <= _lastSeenGeneration) return;
    _lastSeenGeneration = snapshot.generation;

    // ── Collect rewards from previous actions ─────────────────────────────
    _collectRewards(snapshot);

    if (snapshot.generation < _nextEvaluationGeneration) return;
    _nextEvaluationGeneration = snapshot.generation + cycleLength;

    final params = _currentParameters();
    final candidates = _buildCandidates(snapshot, params);
    if (candidates.isEmpty) {
      _pendingSignal = null;
      _pendingCount = 0;
      return;
    }

    // ── Signal persistence (moderate signals must appear twice) ───────────
    final topSignal = candidates.first.signal;
    if (_pendingSignal == topSignal) {
      _pendingCount++;
    } else {
      _pendingSignal = topSignal;
      _pendingCount = 1;
    }

    // ── Apply the best UCB1-scored eligible candidate ─────────────────────
    final eligible = candidates.where((c) {
      if (c.severe) return true; // severe: bypass persistence
      if (_pendingCount < 2 && c.signal == topSignal) return false;
      final lastChange = _lastParameterChange[c.parameter];
      if (lastChange == null) return true;
      return snapshot.generation - lastChange >= cycleLength * parameterCooldownCycles;
    }).toList();

    if (eligible.isEmpty) return;

    final best = _ucbSelect(eligible);

    _lastParameterChange[best.parameter] = snapshot.generation;
    _pendingRewards[best.parameter] = _PendingObservation(
      preFitness: snapshot.bestFitness,
      appliedAtGeneration: snapshot.generation,
    );
    _pendingSignal = null;
    _pendingCount = 0;
    ++_totalPulls;
    _arms.putIfAbsent(best.parameter, _ArmStats.new).pulls++;

    onSuggestion?.call(
      best.parameter,
      best.value,
      'Agente local UCB1: ${best.reason} '
      '[braço ${_armSummary(best.parameter)}]',
    );
  }

  /// Build all candidates this cycle, ordered by descending priority score.
  List<_Candidate> _buildCandidates(
    GenerationSnapshot snapshot,
    Map<String, double> params,
  ) {
    final list = <_Candidate>[];

    final trainRmse = snapshot.bestModelRMSE;
    final validRmse = snapshot.bestModelValidationRMSE;
    final freeRunRmse = snapshot.freeRunRmse;

    // ── Free-run divergence ───────────────────────────────────────────────
    if (_validPositive(trainRmse) && _validPositive(freeRunRmse)) {
      final ratio = freeRunRmse! / math.max(trainRmse, 1e-12);
      final validRef = _validPositive(validRmse) ? validRmse! : trainRmse;
      if (ratio > 4.0 || freeRunRmse > math.max(0.08, validRef * 3.0)) {
        final penalty = _v(params, 'freeRunPenalty', 0.5);
        if (penalty < 1.6) {
          final frPenC = _candidate(
            signal: 'free-run-penalty',
            parameter: 'freeRunPenalty',
            current: penalty,
            proposed: math.max(penalty + 0.15, penalty * 1.25),
            min: 0.0,
            max: 2.0,
            severe: ratio > 8.0,
            reason:
                'free-run divergiu ${ratio.toStringAsFixed(1)}x; '
                'aumentando penalizacao.',
          );
          if (frPenC != null) list.add(frPenC);
        } else {
          final horizon = _v(params, 'freeRunHorizon', 50);
          final c = _candidate(
            signal: 'free-run-horizon',
            parameter: 'freeRunHorizon',
            current: horizon,
            proposed: math.max(horizon + 25, horizon * 1.35),
            min: 10,
            max: 500,
            integer: true,
            severe: ratio > 10.0,
            reason: 'free-run divergente mesmo com penalizacao alta; '
                'ampliando horizonte.',
          );
          if (c != null) list.add(c);
        }
      }
    }

    // ── Near-zero R² persistente: busca presa em modelo trivial ──────────
    final r2 = snapshot.bestModelR2;
    final inputRatio = snapshot.inputContributionRatio;
    final stagnating =
        snapshot.stagnationCounter >= math.max(25, cycleLength);
    if (r2.isFinite && r2 < 0.05 && stagnating) {
      // Se input_contribution_ratio é quase nulo mesmo com stagnation,
      // a penalidade noInputPenalty pode estar bloqueando bons modelos AR.
      // Reduzir levemente para abrir espaço a modelos mistos AR+u.
      if (inputRatio != null && inputRatio.isFinite && inputRatio < 0.15) {
        final penalty = _v(params, 'noInputPenalty', 0.5);
        final c = _candidate(
          signal: 'trivial-model-relax',
          parameter: 'noInputPenalty',
          current: penalty,
          proposed: (penalty - 0.1).clamp(0.1, 2.0),
          min: 0.1,
          max: 2.0,
          severe: r2 < 0.01 &&
              snapshot.stagnationCounter >= cycleLength * 3,
          reason:
              'R²=${r2.toStringAsFixed(3)} com contribuicao de entrada baixa '
              '(${(inputRatio * 100).toStringAsFixed(0)}%); relaxando '
              'penalidade AR para explorar modelos mistos.',
        );
        if (c != null) list.add(c);
      }

      // Reinicialização mais agressiva em modelo trivial
      final ratio = _v(params, 'reinitializationRatio', 0.1);
      final c = _candidate(
        signal: 'trivial-reinit',
        parameter: 'reinitializationRatio',
        current: ratio,
        proposed: ratio + 0.08,
        min: 0.0,
        max: 0.4,
        severe: snapshot.stagnationCounter >= cycleLength * 4,
        reason: 'R² quasi-nulo por ${snapshot.stagnationCounter} gerações; '
            'reinicializando populacao.',
      );
      if (c != null) list.add(c);
    }

    // ── Baixa contribuição de entrada (modelo ignora u) ───────────────────
    if (snapshot.phase >= 1 &&
        inputRatio != null &&
        inputRatio.isFinite &&
        inputRatio < 0.25) {
      final penalty = _v(params, 'noInputPenalty', 0.5);
      final c = _candidate(
        signal: 'input-underuse',
        parameter: 'noInputPenalty',
        current: penalty,
        proposed: penalty + 0.2,
        min: 0.0,
        max: 2.0,
        severe: inputRatio < 0.1,
        reason: 'contribuicao das entradas = '
            '${(inputRatio * 100).toStringAsFixed(1)}%; '
            'aumentando pressao por regressores de entrada.',
      );
      if (c != null) list.add(c);
    }

    // ── Estagnação com diversidade colapsada ──────────────────────────────
    final diversity = snapshot.phenotypicDiversity;
    final safeDiv = (diversity.isFinite && diversity < 1e20)
        ? diversity
        : 0.0; // overflow defensivo: div astronomica = colapsada
    final collapsed = safeDiv < 0.05 || snapshot.populationVariance < 1e-5;
    final lowSuccess = snapshot.successRate < 0.04;

    if (stagnating && lowSuccess && collapsed) {
      final ratio = _v(params, 'reinitializationRatio', 0.1);
      final c = _candidate(
        signal: 'diversity-collapse',
        parameter: 'reinitializationRatio',
        current: ratio,
        proposed: ratio + 0.05,
        min: 0.0,
        max: 0.4,
        severe: snapshot.stagnationCounter >= cycleLength * 3,
        reason: 'estagnacao com diversidade colapsada; '
            'ampliando reinicializacao parcial.',
      );
      if (c != null) list.add(c);
    }

    // ── Estagnação com taxa de sucesso baixa ──────────────────────────────
    if (stagnating && lowSuccess) {
      final mutation = _v(params, 'mutationFactor', 0.5);
      if (mutation < 1.2) {
        list.add(_candidate(
              signal: 'stagnation-mutation',
              parameter: 'mutationFactor',
              current: mutation,
              proposed: mutation + 0.1,
              min: 0.1,
              max: 1.2,
              severe: snapshot.stagnationCounter >= cycleLength * 4,
              reason: 'taxa de sucesso baixa durante estagnacao; '
                  'aumentando mutacao.',
            ) ??
            _candidate(
              signal: 'stagnation-migration',
              parameter: 'migrationRate',
              current: _v(params, 'migrationRate', 0.1),
              proposed: _v(params, 'migrationRate', 0.1) + 0.03,
              min: 0.0,
              max: 0.3,
              severe: false,
              reason: 'mutacao saturada; aumentando migracao entre ilhas.',
            )!);
      } else {
        final migration = _v(params, 'migrationRate', 0.1);
        final c = _candidate(
          signal: 'stagnation-migration',
          parameter: 'migrationRate',
          current: migration,
          proposed: migration + 0.03,
          min: 0.0,
          max: 0.3,
          severe: false,
          reason: 'estagnacao; aumentando troca entre ilhas.',
        );
        if (c != null) list.add(c);
      }
    }

    // ── Overfitting (val >> train) ─────────────────────────────────────────
    if (_validPositive(trainRmse) && _validPositive(validRmse)) {
      final gap = validRmse! / math.max(trainRmse, 1e-12);
      if (gap > 1.5) {
        final penalty = _v(params, 'complexityPenalty', 0.01);
        final c = _candidate(
          signal: 'overfitting',
          parameter: 'complexityPenalty',
          current: penalty,
          proposed: math.max(penalty + 0.005, penalty * 1.25),
          min: 0.0,
          max: 0.2,
          severe: gap > 2.5,
          reason: 'val=${gap.toStringAsFixed(1)}x treino; reforçando '
              'parcimonia.',
        );
        if (c != null) list.add(c);
      }
    }

    // ── Refinamento saudável (reduzir mutação) ────────────────────────────
    if (snapshot.phase >= 2 &&
        snapshot.successRate > 0.25 &&
        snapshot.stagnationCounter < cycleLength ~/ 2) {
      final mutation = _v(params, 'mutationFactor', 0.5);
      if (mutation > 0.4) {
        final c = _candidate(
          signal: 'healthy-refinement',
          parameter: 'mutationFactor',
          current: mutation,
          proposed: mutation - 0.05,
          min: 0.35,
          max: 1.2,
          severe: false,
          reason: 'busca saudavel em fase tardia; reduzindo mutacao '
              'para refinamento fino.',
        );
        if (c != null) list.add(c);
      }
    }

    return list;
  }

  // ── UCB1 selection ────────────────────────────────────────────────────────
  _Candidate _ucbSelect(List<_Candidate> candidates) {
    if (candidates.length == 1) return candidates.first;
    if (_totalPulls == 0) return candidates.first;

    double bestScore = -double.infinity;
    _Candidate best = candidates.first;

    for (final c in candidates) {
      final arm = _arms[c.parameter];
      final score = arm == null
          ? double.infinity // untried arm → always explore first
          : arm.avgReward +
              _ucbC *
                  math.sqrt(
                    math.log(_totalPulls + 1) / (arm.pulls + 1),
                  );
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  // ── Reward collection ─────────────────────────────────────────────────────
  void _collectRewards(GenerationSnapshot snapshot) {
    final toRemove = <String>[];
    _pendingRewards.forEach((param, obs) {
      if (snapshot.generation - obs.appliedAtGeneration >= _rewardHorizon) {
        final postFitness = snapshot.bestFitness;
        final reward = obs.preFitness.isFinite && postFitness.isFinite
            ? obs.preFitness - postFitness // positive = improved
            : 0.0;
        _arms.putIfAbsent(param, _ArmStats.new).addReward(reward);
        toRemove.add(param);
      }
    });
    for (final p in toRemove) {
      _pendingRewards.remove(p);
    }
  }

  String _armSummary(String param) {
    final arm = _arms[param];
    if (arm == null || arm.pulls == 0) return 'novo';
    return 'pulls=${arm.pulls}, '
        'avgReward=${arm.avgReward.toStringAsFixed(3)}';
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
    var value = proposed.toDouble().clamp(min, max);
    if (integer) value = value.roundToDouble();
    if ((value - current).abs() < 1e-9) return null;
    return _Candidate(
      signal: signal,
      parameter: parameter,
      value: value,
      severe: severe,
      reason: reason,
    );
  }

  double _v(Map<String, double> p, String name, double fallback) =>
      p[name] ?? fallback;

  bool _validPositive(double? value) =>
      value != null && value.isFinite && value > 0;

  @override
  void dispose() {}
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _ArmStats {
  int pulls = 0;
  double _totalReward = 0.0;
  double get avgReward => pulls > 0 ? _totalReward / pulls : 0.0;
  void addReward(double r) => _totalReward += r;
}

class _PendingObservation {
  final double preFitness;
  final int appliedAtGeneration;
  const _PendingObservation({
    required this.preFitness,
    required this.appliedAtGeneration,
  });
}

class _Candidate {
  final String signal;
  final String parameter;
  final double value;
  final bool severe;
  final String reason;
  const _Candidate({
    required this.signal,
    required this.parameter,
    required this.value,
    required this.severe,
    required this.reason,
  });
}
