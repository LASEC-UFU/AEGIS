// A1 agent updates: agents read the search configuration (errorMode, veto)
// and the champion's admissibility from the snapshot.
import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/agent/generation_snapshot.dart';
import 'package:aegis/services/fuzzy_policy_agent.dart';
import 'package:aegis/services/local_adaptive_agent.dart';

GenerationSnapshot snap({
  required int generation,
  String errorMode = 'one_step',
  bool? championAdmissible,
  double valRmse = 0.05,
  double freeRunFull = 0.08,
  double trainRmse = 0.05,
  double? freeRunHorizon,
}) {
  return GenerationSnapshot(
    generation: generation,
    elapsed: Duration.zero,
    bestFitness: 1,
    worstFitness: 2,
    meanFitness: 1.5,
    medianFitness: 1.5,
    stdDevFitness: 0.1,
    q1Fitness: 1.2,
    q3Fitness: 1.8,
    improvementAbsolute: 0,
    improvementRelative: 0,
    improvementRate5: 0,
    improvementRate20: 0,
    stagnationCounter: 5,
    uniqueStructures: 60,
    structureEntropy: 3,
    phenotypicDiversity: 0.1,
    regressorFrequency: const {},
    populationVariance: 0.01,
    successRate: 0.2,
    successRateHistory: const [],
    bestModelComplexity: 4,
    bestModelMaxDegree: 2,
    bestModelMaxDelay: 5,
    bestModelERR: const [],
    bestModelRMSE: trainRmse,
    bestModelValidationRMSE: valRmse,
    bestModelR2: 0.95,
    islandSnapshots: const [],
    globalStagnation: 5,
    freeRunRmse: freeRunHorizon,
    freeRunRmseValidationFull: freeRunFull,
    islandStatuses: const [
      IslandStatus(id: 0, populationSize: 50),
      IslandStatus(id: 1, populationSize: 50),
      IslandStatus(id: 2, populationSize: 50),
    ],
    parameters: const {
      'mutationFactor': 0.5,
      'freeRunPenalty': 0.5,
      'stabilityPenalty': 1.0,
    },
    errorMode: errorMode,
    admissibilityVeto: championAdmissible != null,
    championAdmissible: championAdmissible,
  );
}

void main() {
  test('fuzzy: inadmissible champion raises the stability penalty (R9)', () {
    final out = <(String, double)>[];
    final a = FuzzyPolicyAgent()..onSuggestion = (p, v, r) => out.add((p, v));
    a.processSnapshot(snap(generation: 25, championAdmissible: false));
    expect(out.single.$1, 'stabilityPenalty');
    expect(out.single.$2, closeTo(1.5, 1e-9));
  });

  test('fuzzy: free-run rule R7 cannot fire when errorMode is simulation', () {
    final out = <(String, double)>[];
    final a = FuzzyPolicyAgent()..onSuggestion = (p, v, r) => out.add((p, v));
    a.processSnapshot(snap(generation: 25, errorMode: 'simulation', freeRunFull: 0.5));
    expect(out.where((e) => e.$1 == 'freeRunPenalty'), isEmpty);
    expect(fuzzyFeatures(snap(generation: 25, errorMode: 'simulation')).containsKey('sim'), isTrue);
    expect(fuzzyFeatures(snap(generation: 25, errorMode: 'simulation'))['sim']!.isNaN, isTrue);
  });

  test('UCB1: inadmissible champion proposes stabilityPenalty, never θ in simulation mode', () {
    final params = <String, double>{'freeRunPenalty': 0.5, 'stabilityPenalty': 1.0};
    final actions = <String>[];
    final agent = LocalAdaptiveAgent(currentParameters: () => params)
      ..onSuggestion = (p, v, r) { params[p] = v; actions.add(p); };
    agent.processSnapshot(snap(generation: 25, errorMode: 'simulation', championAdmissible: false,
        trainRmse: 0.01, freeRunHorizon: 0.12));
    expect(actions, ['stabilityPenalty']);
    expect(params['stabilityPenalty'], closeTo(1.5, 1e-12));
  });

  test('observation carries the search configuration and admissibility', () {
    final o = snap(generation: 25, errorMode: 'simulation', championAdmissible: true).toObservation();
    expect((o['search'] as Map)['errorMode'], 'simulation');
    expect((o['model'] as Map)['championAdmissible'], isTrue);
  });
}
