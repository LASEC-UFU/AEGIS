import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/agent/generation_snapshot.dart';
import 'package:aegis/services/convergence_controller.dart';

const _schema = {
  'schema': 'aegis.actions/1',
  'allowBudgetActions': false,
  'parameters': [
    {'name': 'mutationFactor', 'kind': 'de', 'min': 0.05, 'max': 1.0, 'maxStep': 0.3, 'integer': false, 'budget': false},
    {'name': 'migrationInterval', 'kind': 'de', 'min': 5, 'max': 200, 'maxStep': 50, 'integer': true, 'budget': false},
    {'name': 'stagnationLimit', 'kind': 'de', 'min': 50, 'max': 5000, 'maxStep': 1000, 'integer': true, 'budget': true},
    {'name': 'freeRunPenalty', 'kind': 'weight', 'min': 0.0, 'max': 5.0, 'maxStep': 1.0, 'integer': false, 'budget': false},
    {'name': 'freeRunHorizon', 'kind': 'weight', 'min': 10, 'max': 500, 'maxStep': 200, 'integer': true, 'budget': false},
    {'name': 'stabilityPenalty', 'kind': 'weight', 'min': 0.0, 'max': 5.0, 'maxStep': 1.0, 'integer': false, 'budget': false},
    {'name': 'triggerRestart', 'kind': 'event', 'min': 0.05, 'max': 1.0, 'maxStep': 1.0, 'integer': false, 'budget': false},
  ],
};

const _params = {
  'mutationFactor': 0.5,
  'migrationInterval': 20.0,
  'stagnationLimit': 500.0,
  'freeRunPenalty': 0.5,
  'freeRunHorizon': 50.0,
  'stabilityPenalty': 1.0,
};

GenerationSnapshot snap(int g, double valFreeRun, {String errorMode = 'one_step', int phase = 0, bool? adm}) =>
    GenerationSnapshot(
      generation: g,
      elapsed: Duration.zero,
      bestFitness: 1, worstFitness: 2, meanFitness: 1.5, medianFitness: 1.5, stdDevFitness: 0.1,
      q1Fitness: 1.2, q3Fitness: 1.8,
      improvementAbsolute: 0, improvementRelative: 0, improvementRate5: 0, improvementRate20: 0,
      stagnationCounter: 0, uniqueStructures: 60, structureEntropy: 3, phenotypicDiversity: 0.1,
      regressorFrequency: const {}, populationVariance: 0.01, successRate: 0.2, successRateHistory: const [],
      bestModelComplexity: 4, bestModelMaxDegree: 2, bestModelMaxDelay: 5, bestModelERR: const [],
      bestModelRMSE: 0.05, bestModelValidationRMSE: 0.05, bestModelR2: 0.95, islandSnapshots: const [],
      phase: phase,
      freeRunRmseValidationFull: valFreeRun,
      islandStatuses: const [IslandStatus(id: 0, populationSize: 50)],
      parameters: _params,
      errorMode: errorMode,
      admissibilityVeto: adm != null,
      championAdmissible: adm,
    );

AdaptiveConvergenceController make() => AdaptiveConvergenceController(
      actionSchema: () => _schema,
      currentParameters: () => Map.of(_params),
    );

void main() {
  test('arms cover every schema parameter, both directions, plus no action', () {
    final m = make().candidateMoves(snap(10, 0.1));
    expect(m.keys, containsAll(['none', 'mutationFactor:+', 'mutationFactor:-', 'migrationInterval:+',
      'migrationInterval:-', 'freeRunPenalty:+', 'freeRunHorizon:+', 'stabilityPenalty:+', 'triggerRestart:partial']));
    expect(m['migrationInterval:+'], 45); // integer, half the max step (25)
    expect(m.keys.where((k) => k.startsWith('stagnationLimit')), isEmpty, reason: 'budget-locked');
    expect(m.keys.where((k) => k.contains('cataclysm')), isEmpty, reason: 'only on premature convergence');
  });

  test('inert parameters are masked in simulation mode; cataclysm offered on premature convergence', () {
    final m = make().candidateMoves(snap(10, 0.1, errorMode: 'simulation'), premature: true);
    expect(m.keys.where((k) => k.startsWith('freeRun')), isEmpty);
    expect(m['triggerRestart:cataclysm'], 1.0);
  });

  test('horizon: plateau acts soon, fast convergence waits', () {
    final c = make();
    expect(c.horizon(0.0, 0.0), c.hMin);
    expect(c.horizon(0.01, 0.001), greaterThanOrEqualTo(c.hMax ~/ 2));
    expect(c.horizon(1e-4, 0.002), inInclusiveRange(c.hMin, c.hMax));
  });

  test('decisions follow the estimated horizon and record a forecast', () {
    final c = make();
    final decisions = <int>[];
    final hs = <int>[];
    c.onDecision = (d) {
      decisions.add(d.generation);
      if (d.diagnosis?['h'] != null) hs.add(d.diagnosis!['h'] as int);
    };
    c.onSuggestion = (p, v, r) {};
    for (var g = 1; g <= 120; g++) {
      c.processSnapshot(snap(g, 0.1 * (1 + 1 / g))); // slowly converging
    }
    expect(decisions, isNotEmpty);
    expect(hs, isNotEmpty);
    // After the first full decision, the next one is not before g + h.
    final first = decisions.firstWhere((g) => g >= 5);
    final next = decisions.where((g) => g > first);
    if (next.isNotEmpty) expect(next.first - first, greaterThanOrEqualTo(hs.first));
  });

  test('inadmissible champion is an event that brings the decision forward', () {
    final c = make();
    final at = <int>[];
    c.onDecision = (d) => at.add(d.generation);
    for (var g = 1; g <= 30; g++) {
      c.processSnapshot(snap(g, 0.1, adm: g == 30 ? false : true));
    }
    expect(at.last, 30);
  });

  test('arm table survives a JSON round trip', () {
    final c = make();
    for (var g = 1; g <= 300; g++) {
      c.processSnapshot(snap(g, 0.1 * (1 + 1 / g)));
      c.onActionResult({'accepted': true});
    }
    final t = c.tableJson();
    final d = AdaptiveConvergenceController(actionSchema: () => _schema, currentParameters: () => _params, table: t);
    expect(d.tableJson(), t);
  });
}
