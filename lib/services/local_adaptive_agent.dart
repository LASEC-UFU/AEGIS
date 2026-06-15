import 'dart:math' as math;

import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

/// Conservative local supervisor for the evolutionary engine.
///
/// It evaluates indicators at fixed generation windows, requires persistence
/// for moderate signals, and applies at most one bounded change per window.
class LocalAdaptiveAgent implements OptimizationAgent {
  @override
  TuningSuggestion? onSuggestion;

  final Map<String, double> Function() _currentParameters;
  final int cycleLength;
  final int parameterCooldownCycles;

  int _nextEvaluationGeneration;
  int _lastSeenGeneration = -1;
  String? _pendingSignal;
  int _pendingCount = 0;
  final Map<String, int> _lastParameterChange = {};

  LocalAdaptiveAgent({
    required Map<String, double> Function() currentParameters,
    this.cycleLength = 25,
    this.parameterCooldownCycles = 2,
  }) : _currentParameters = currentParameters,
       _nextEvaluationGeneration = cycleLength;

  @override
  String get name => 'Agente local adaptativo';

  @override
  bool get available => true;

  @override
  void processSnapshot(GenerationSnapshot snapshot) {
    if (snapshot.generation <= _lastSeenGeneration) return;
    _lastSeenGeneration = snapshot.generation;
    if (snapshot.generation < _nextEvaluationGeneration) return;
    _nextEvaluationGeneration = snapshot.generation + cycleLength;

    final candidate = _chooseCandidate(snapshot, _currentParameters());
    if (candidate == null) {
      _pendingSignal = null;
      _pendingCount = 0;
      return;
    }

    if (_pendingSignal == candidate.signal) {
      _pendingCount++;
    } else {
      _pendingSignal = candidate.signal;
      _pendingCount = 1;
    }

    final lastChange = _lastParameterChange[candidate.parameter];
    final cooldown = cycleLength * parameterCooldownCycles;
    if (lastChange != null && snapshot.generation - lastChange < cooldown) {
      return;
    }

    // Severe conditions act immediately. Moderate ones must persist across
    // two evaluation windows to avoid oscillating on noisy indicators.
    if (!candidate.severe && _pendingCount < 2) return;

    _lastParameterChange[candidate.parameter] = snapshot.generation;
    _pendingSignal = null;
    _pendingCount = 0;
    onSuggestion?.call(
      candidate.parameter,
      candidate.value,
      'Agente local: ${candidate.reason}',
    );
  }

  _Candidate? _chooseCandidate(
    GenerationSnapshot snapshot,
    Map<String, double> parameters,
  ) {
    final trainRmse = snapshot.bestModelRMSE;
    final validationRmse = snapshot.bestModelValidationRMSE;
    final freeRunRmse = snapshot.freeRunRmse;

    if (_validPositive(trainRmse) && _validPositive(freeRunRmse)) {
      final ratio = freeRunRmse! / math.max(trainRmse, 1e-12);
      final validationReference = _validPositive(validationRmse)
          ? validationRmse!
          : trainRmse;
      final divergent =
          ratio > 4.0 ||
          freeRunRmse > math.max(0.08, validationReference * 3.0);
      if (divergent) {
        final penalty = _value(parameters, 'freeRunPenalty', 0.5);
        if (penalty < 1.6) {
          return _candidate(
            signal: 'free-run-penalty',
            parameter: 'freeRunPenalty',
            current: penalty,
            proposed: math.max(penalty + 0.15, penalty * 1.25),
            min: 0.0,
            max: 2.0,
            severe: ratio > 8.0,
            reason:
                'free-run divergiu do ajuste one-step '
                '(${ratio.toStringAsFixed(1)}x); aumentando sua penalizacao.',
          );
        }

        final horizon = _value(parameters, 'freeRunHorizon', 50);
        final candidate = _candidate(
          signal: 'free-run-horizon',
          parameter: 'freeRunHorizon',
          current: horizon,
          proposed: math.max(horizon + 25, horizon * 1.35),
          min: 10,
          max: 500,
          integer: true,
          severe: ratio > 10.0,
          reason:
              'free-run continua divergente com penalizacao alta; '
              'ampliando o horizonte de simulacao.',
        );
        if (candidate != null) return candidate;
      }
    }

    final inputContribution = snapshot.inputContributionRatio;
    if (snapshot.phase >= 1 &&
        inputContribution != null &&
        inputContribution.isFinite &&
        inputContribution < 0.25) {
      final penalty = _value(parameters, 'noInputPenalty', 0.5);
      final candidate = _candidate(
        signal: 'input-underuse',
        parameter: 'noInputPenalty',
        current: penalty,
        proposed: penalty + 0.2,
        min: 0.0,
        max: 2.0,
        severe: inputContribution < 0.1,
        reason:
            'contribuicao das entradas esta baixa '
            '(${(inputContribution * 100).toStringAsFixed(1)}%).',
      );
      if (candidate != null) return candidate;
    }

    final stagnating = snapshot.stagnationCounter >= math.max(25, cycleLength);
    final lowSuccess = snapshot.successRate < 0.04;
    final collapsed =
        snapshot.phenotypicDiversity < 0.05 ||
        snapshot.populationVariance < 1e-5;
    if (stagnating && lowSuccess && collapsed) {
      final ratio = _value(parameters, 'reinitializationRatio', 0.1);
      final candidate = _candidate(
        signal: 'diversity-collapse',
        parameter: 'reinitializationRatio',
        current: ratio,
        proposed: ratio + 0.05,
        min: 0.0,
        max: 0.35,
        severe: snapshot.stagnationCounter >= cycleLength * 3,
        reason:
            'estagnacao com diversidade colapsada; ampliando a '
            'reinicializacao parcial.',
      );
      if (candidate != null) return candidate;
    }

    if (stagnating && lowSuccess) {
      final mutation = _value(parameters, 'mutationFactor', 0.5);
      if (mutation < 1.2) {
        return _candidate(
          signal: 'stagnation-mutation',
          parameter: 'mutationFactor',
          current: mutation,
          proposed: mutation + 0.1,
          min: 0.1,
          max: 1.2,
          severe: snapshot.stagnationCounter >= cycleLength * 4,
          reason:
              'taxa de sucesso baixa durante estagnacao; aumentando '
              'exploracao por mutacao.',
        );
      }

      final migration = _value(parameters, 'migrationRate', 0.1);
      return _candidate(
        signal: 'stagnation-migration',
        parameter: 'migrationRate',
        current: migration,
        proposed: migration + 0.03,
        min: 0.0,
        max: 0.3,
        severe: false,
        reason:
            'estagnacao persiste apesar da mutacao alta; aumentando a '
            'troca entre ilhas.',
      );
    }

    if (_validPositive(trainRmse) && _validPositive(validationRmse)) {
      final gap = validationRmse! / math.max(trainRmse, 1e-12);
      if (gap > 1.5) {
        final penalty = _value(parameters, 'complexityPenalty', 0.01);
        return _candidate(
          signal: 'overfitting',
          parameter: 'complexityPenalty',
          current: penalty,
          proposed: math.max(penalty + 0.005, penalty * 1.25),
          min: 0.0,
          max: 0.2,
          severe: gap > 2.5,
          reason:
              'erro de validacao esta ${gap.toStringAsFixed(1)}x acima do '
              'treino; reforcando parcimonia.',
        );
      }
    }

    final healthyRefinement =
        snapshot.phase >= 2 &&
        snapshot.successRate > 0.25 &&
        snapshot.stagnationCounter < cycleLength ~/ 2;
    if (healthyRefinement) {
      final mutation = _value(parameters, 'mutationFactor', 0.5);
      if (mutation > 0.4) {
        return _candidate(
          signal: 'healthy-refinement',
          parameter: 'mutationFactor',
          current: mutation,
          proposed: mutation - 0.05,
          min: 0.35,
          max: 1.2,
          severe: false,
          reason:
              'busca esta saudavel em fase tardia; reduzindo a mutacao '
              'para refinamento fino.',
        );
      }
    }

    return null;
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
    );
  }

  double _value(Map<String, double> parameters, String name, double fallback) =>
      parameters[name] ?? fallback;

  bool _validPositive(double? value) =>
      value != null && value.isFinite && value > 0;

  @override
  void dispose() {}
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
