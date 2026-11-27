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

  group('CAC v4 (measured impact map)', () {
    const wSchema = {
      'schema': 'aegis.actions/1',
      'allowBudgetActions': false,
      'parameters': [
        {'name': 'mutationFactor', 'kind': 'de', 'min': 0.05, 'max': 1.0, 'maxStep': 0.3, 'integer': false},
        {'name': 'complexityPenalty', 'kind': 'weight', 'min': 0.0, 'max': 1.0, 'maxStep': 0.1, 'integer': false},
        {'name': 'noInputPenalty', 'kind': 'weight', 'min': 0.0, 'max': 5.0, 'maxStep': 1.0, 'integer': false},
        {'name': 'denominatorPenalty', 'kind': 'weight', 'min': 0.0, 'max': 2.0, 'maxStep': 0.5, 'integer': false},
        {'name': 'exponentPenalty', 'kind': 'weight', 'min': 0.0, 'max': 1.0, 'maxStep': 0.2, 'integer': false},
        {'name': 'alpha', 'kind': 'weight', 'min': 0.0, 'max': 2.0, 'maxStep': 0.5, 'integer': false},
        {'name': 'triggerRestart', 'kind': 'event', 'min': 0.05, 'max': 1.0, 'maxStep': 1.0, 'integer': false},
      ],
    };
    const wParams = {
      'mutationFactor': 0.5, 'complexityPenalty': 0.0, 'noInputPenalty': 0.5,
      'denominatorPenalty': 0.0, 'exponentPenalty': 0.0, 'alpha': 0.0,
    };
    AdaptiveConvergenceController v4() => AdaptiveConvergenceController(
        actionSchema: () => wSchema, currentParameters: () => Map.of(wParams), version: 4);
    GenerationSnapshot s(int g, double train, double val) => GenerationSnapshot(
          generation: g, elapsed: Duration.zero,
          bestFitness: 1, worstFitness: 2, meanFitness: 1.5, medianFitness: 1.5, stdDevFitness: 0.1,
          q1Fitness: 1.2, q3Fitness: 1.8,
          improvementAbsolute: 0, improvementRelative: 0, improvementRate5: 0, improvementRate20: 0,
          stagnationCounter: 0, uniqueStructures: 60, structureEntropy: 3, phenotypicDiversity: 0.1,
          regressorFrequency: const {}, populationVariance: 0.01, successRate: 0.2, successRateHistory: const [],
          bestModelComplexity: 30, bestModelMaxDegree: 2, bestModelMaxDelay: 5, bestModelERR: const [],
          bestModelRMSE: train, bestModelValidationRMSE: val, bestModelR2: 0.95, islandSnapshots: const [],
          phase: 2, freeRunRmseValidationFull: 0.1,
          islandStatuses: const [IslandStatus(id: 0, populationSize: 50)],
          parameters: wParams, errorMode: 'simulation');

    test('without overfitting (WH/SB-like gap) no complexity weight can be raised', () {
      final c = v4();
      for (var g = 1; g <= 12; g++) { c.processSnapshot(s(g, 0.05, 0.051)); }
      expect(c.gateOpen, isFalse);
      final m = c.candidateMoves(s(13, 0.05, 0.051));
      expect(m.keys, isNot(contains('denominatorPenalty:+')));
      expect(m.keys, isNot(contains('exponentPenalty:+')));
      expect(m.keys, isNot(contains('complexityPenalty:+')));
      expect(m.keys.where((k) => k.startsWith('noInputPenalty')), isEmpty, reason: 'measured inert');
      expect(m.keys, containsAll(['none', 'alpha:+', 'mutationFactor:+', 'triggerRestart:partial']));
    });

    test('with overfitting (CT-like gap) β↑ opens; δ↑ and γ↑ stay blocked', () {
      final c = v4();
      for (var g = 1; g <= 12; g++) { c.processSnapshot(s(g, 0.05, 0.075)); } // gap log 1.5 = 0.405
      expect(c.gateOpen, isTrue);
      final m = c.candidateMoves(s(13, 0.05, 0.075));
      expect(m['denominatorPenalty:+'], closeTo(0.05, 1e-12)); // tenth of maxStep = T2 dose
      expect(m.keys, isNot(contains('exponentPenalty:+')));
      expect(m.keys, isNot(contains('complexityPenalty:+')));
    });

    test('a weight action is judged only after the measured transient (≥ 200 generations)', () {
      final c = v4();
      final hs = <String, int>{};
      c.onDecision = (d) {
        if (d.status == 'action') hs[d.actions.first.param] = d.diagnosis!['h'] as int;
      };
      c.onSuggestion = (p, v, r) {};
      for (var g = 1; g <= 4000; g++) {
        c.processSnapshot(s(g, 0.05, 0.075));
        c.onActionResult({'accepted': true});
      }
      expect(hs.keys.where((k) => const {'denominatorPenalty', 'alpha'}.contains(k)), isNotEmpty);
      for (final e in hs.entries.where((e) => const {'denominatorPenalty', 'alpha'}.contains(e.key))) {
        expect(e.value, greaterThanOrEqualTo(200), reason: e.key);
      }
    });

    test('v3 behaviour unchanged by default', () {
      final c = AdaptiveConvergenceController(actionSchema: () => wSchema, currentParameters: () => Map.of(wParams));
      expect(c.id, 'cac');
      expect(c.candidateMoves(s(1, 0.05, 0.051)).keys, contains('complexityPenalty:+'));
    });
  });
}
