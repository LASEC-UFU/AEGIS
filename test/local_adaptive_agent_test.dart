import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/agent/generation_snapshot.dart';
import 'package:aegis/services/local_adaptive_agent.dart';

void main() {
  test('acts immediately on severe free-run divergence', () {
    final parameters = <String, double>{'freeRunPenalty': 0.5};
    final actions = <_Action>[];
    final agent = LocalAdaptiveAgent(currentParameters: () => parameters)
      ..onSuggestion = (parameter, value, reason) {
        parameters[parameter] = value;
        actions.add(_Action(parameter, value, reason));
      };

    agent.processSnapshot(
      _snapshot(generation: 25, trainRmse: 0.01, freeRunRmse: 0.12),
    );

    expect(actions, hasLength(1));
    expect(actions.single.parameter, 'freeRunPenalty');
    expect(actions.single.value, greaterThan(0.5));
    expect(actions.single.reason, startsWith('Agente local UCB1:'));
  });

  test('requires persistence before acting on a moderate signal', () {
    final parameters = <String, double>{'freeRunPenalty': 0.5};
    final actions = <_Action>[];
    final agent = LocalAdaptiveAgent(currentParameters: () => parameters)
      ..onSuggestion = (parameter, value, reason) {
        parameters[parameter] = value;
        actions.add(_Action(parameter, value, reason));
      };

    agent.processSnapshot(
      _snapshot(generation: 25, trainRmse: 0.02, freeRunRmse: 0.1),
    );
    expect(actions, isEmpty);

    agent.processSnapshot(
      _snapshot(generation: 50, trainRmse: 0.02, freeRunRmse: 0.1),
    );
    expect(actions.single.parameter, 'freeRunPenalty');
  });

  test('recovers severe diversity collapse with partial reinitialization', () {
    final parameters = <String, double>{'reinitializationRatio': 0.1};
    final actions = <_Action>[];
    final agent = LocalAdaptiveAgent(currentParameters: () => parameters)
      ..onSuggestion = (parameter, value, reason) {
        actions.add(_Action(parameter, value, reason));
      };

    agent.processSnapshot(
      _snapshot(
        generation: 100,
        stagnation: 100,
        successRate: 0.01,
        diversity: 0.001,
      ),
    );

    expect(actions.single.parameter, 'reinitializationRatio');
    expect(actions.single.value, closeTo(0.15, 1e-12));
  });

  test('parameter cooldown prevents repeated changes every window', () {
    final parameters = <String, double>{'freeRunPenalty': 0.5};
    final actions = <_Action>[];
    final agent = LocalAdaptiveAgent(currentParameters: () => parameters)
      ..onSuggestion = (parameter, value, reason) {
        parameters[parameter] = value;
        actions.add(_Action(parameter, value, reason));
      };

    for (final generation in [25, 50, 75]) {
      agent.processSnapshot(
        _snapshot(generation: generation, trainRmse: 0.01, freeRunRmse: 0.12),
      );
    }

    expect(actions, hasLength(2));
    expect(actions.last.value, lessThanOrEqualTo(2.0));
  });

  test('healthy late search is refined only after confirmation', () {
    final parameters = <String, double>{'mutationFactor': 0.7};
    final actions = <_Action>[];
    final agent = LocalAdaptiveAgent(currentParameters: () => parameters)
      ..onSuggestion = (parameter, value, reason) {
        actions.add(_Action(parameter, value, reason));
      };

    agent.processSnapshot(
      _snapshot(generation: 25, phase: 2, successRate: 0.3),
    );
    expect(actions, isEmpty);

    agent.processSnapshot(
      _snapshot(generation: 50, phase: 2, successRate: 0.3),
    );
    expect(actions.single.parameter, 'mutationFactor');
    expect(actions.single.value, closeTo(0.65, 1e-12));
  });
}

GenerationSnapshot _snapshot({
  required int generation,
  int phase = 0,
  int stagnation = 0,
  double successRate = 0.1,
  double diversity = 0.2,
  double trainRmse = 0.02,
  double? validationRmse,
  double? freeRunRmse,
  double? inputContribution,
}) {
  return GenerationSnapshot(
    generation: generation,
    elapsed: Duration.zero,
    bestFitness: 1,
    worstFitness: 2,
    meanFitness: 1.5,
    medianFitness: 1.5,
    stdDevFitness: diversity,
    q1Fitness: 1.2,
    q3Fitness: 1.8,
    improvementAbsolute: 0,
    improvementRelative: 0,
    improvementRate5: 0,
    improvementRate20: 0,
    stagnationCounter: stagnation,
    uniqueStructures: 10,
    structureEntropy: 1,
    phenotypicDiversity: diversity,
    regressorFrequency: const {},
    populationVariance: diversity * diversity,
    successRate: successRate,
    successRateHistory: const [],
    bestModelComplexity: 5,
    bestModelMaxDegree: 2,
    bestModelMaxDelay: 5,
    bestModelERR: const [],
    bestModelRMSE: trainRmse,
    bestModelValidationRMSE: validationRmse,
    bestModelR2: 0.95,
    islandSnapshots: const [],
    phase: phase,
    phaseName: 'test',
    freeRunRmse: freeRunRmse,
    inputContributionRatio: inputContribution,
  );
}

class _Action {
  final String parameter;
  final double value;
  final String reason;

  const _Action(this.parameter, this.value, this.reason);
}
