import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/agent/generation_snapshot.dart';
import 'package:aegis/services/fuzzy_policy_agent.dart';
import 'package:aegis/services/optimization_agent.dart';

GenerationSnapshot snap({
  required int generation,
  int globalStagnation = 0,
  double successRate = 0.2,
  int uniqueStructures = 60,
  double trainRmse = 0.05,
  double? valRmse = 0.055,
  double? freeRunFull = 0.08,
  Map<String, double> parameters = const {
    'mutationFactor': 0.5,
    'crossoverRate': 0.9,
    'reinitializationRatio': 0.1,
    'structuralMutationRate': 0.1,
    'complexityPenalty': 0.01,
    'freeRunPenalty': 0.5,
    'migrationRate': 0.1,
  },
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
    stagnationCounter: globalStagnation,
    uniqueStructures: uniqueStructures,
    structureEntropy: 3,
    phenotypicDiversity: 0.1,
    regressorFrequency: const {},
    populationVariance: 0.01,
    successRate: successRate,
    successRateHistory: const [],
    bestModelComplexity: 4,
    bestModelMaxDegree: 2,
    bestModelMaxDelay: 5,
    bestModelERR: const [],
    bestModelRMSE: trainRmse,
    bestModelValidationRMSE: valRmse,
    bestModelR2: 0.95,
    islandSnapshots: const [],
    globalStagnation: globalStagnation,
    freeRunRmseValidationFull: freeRunFull,
    islandStatuses: const [
      IslandStatus(id: 0, populationSize: 50),
      IslandStatus(id: 1, populationSize: 50),
      IslandStatus(id: 2, populationSize: 50),
    ],
    parameters: parameters,
  );
}

void main() {
  test('healthy search: no action, decision recorded', () {
    final decisions = <AgentDecision>[];
    final actions = <String>[];
    final a = FuzzyPolicyAgent()
      ..onDecision = decisions.add
      ..onSuggestion = (p, v, r) => actions.add(p);
    a.processSnapshot(snap(generation: 25, globalStagnation: 10, successRate: 0.2));
    expect(actions, isEmpty);
    expect(decisions.single.status, anyOf('no_action', 'insufficient_evidence'));
    expect(decisions.single.diagnosis!['features'], isNotNull);
  });

  test('long stagnation with failing trials raises the mutation factor within bounds', () {
    final out = <(String, double)>[];
    final a = FuzzyPolicyAgent()..onSuggestion = (p, v, r) => out.add((p, v));
    a.processSnapshot(snap(generation: 25, globalStagnation: 150, successRate: 0.01, uniqueStructures: 60));
    expect(out, hasLength(1));
    expect(out.single.$1, 'mutationFactor');
    expect(out.single.$2, closeTo(0.6, 1e-9));
  });

  test('structural collapse triggers immigrants or structural mutation', () {
    final out = <String>[];
    final a = FuzzyPolicyAgent()..onSuggestion = (p, v, r) => out.add(p);
    a.processSnapshot(snap(generation: 25, globalStagnation: 150, successRate: 0.2, uniqueStructures: 6));
    expect(out.single, anyOf('reinitializationRatio', 'structuralMutationRate'));
  });

  test('simulation much worse than one-step raises the free-run penalty', () {
    final out = <(String, double)>[];
    final a = FuzzyPolicyAgent()..onSuggestion = (p, v, r) => out.add((p, v));
    a.processSnapshot(snap(generation: 25, globalStagnation: 5, valRmse: 0.05, freeRunFull: 0.5));
    expect(out.single.$1, 'freeRunPenalty');
    expect(out.single.$2, closeTo(0.75, 1e-9));
  });

  test('cooldown and rejection handling', () {
    final out = <String>[];
    final a = FuzzyPolicyAgent()..onSuggestion = (p, v, r) => out.add(p);
    a.processSnapshot(snap(generation: 25, globalStagnation: 150, successRate: 0.01));
    a.processSnapshot(snap(generation: 50, globalStagnation: 175, successRate: 0.01));
    // mutationFactor is in cooldown (2 cycles); another parameter may be chosen.
    expect(out.where((p) => p == 'mutationFactor'), hasLength(1));
    // A rejection (other than cooldown) frees the parameter again.
    final b = FuzzyPolicyAgent()..onSuggestion = (p, v, r) => out.add('b:$p');
    b.processSnapshot(snap(generation: 25, globalStagnation: 150, successRate: 0.01));
    b.onActionResult({'accepted': false, 'code': 'out_of_range'});
    b.processSnapshot(snap(generation: 50, globalStagnation: 175, successRate: 0.01));
    expect(out.where((p) => p == 'b:mutationFactor'), hasLength(2));
  });

  test('rule base JSON round trip preserves behaviour', () {
    final rb = FuzzyRuleBase.expert();
    final copy = FuzzyRuleBase.fromJson(jsonDecode(rb.encode()) as Map<String, dynamic>);
    final f = fuzzyFeatures(snap(generation: 25, globalStagnation: 120, successRate: 0.02));
    expect(FuzzyPolicyAgent(ruleBase: copy).firing(f), FuzzyPolicyAgent(ruleBase: rb).firing(f));
  });
}
