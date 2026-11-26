// Shared conversion between the C++ core JSON (schema aegis.snapshot/2, see
// docs/AGENT_INTERFACE.md) and the Dart GenerationSnapshot. Used by both the
// native (dart:ffi) and the WASM services so the agent sees identical data.

import 'dart:convert';

import '../agent/generation_history.dart';
import '../agent/generation_snapshot.dart';
import '../agent/tunable_parameter.dart';

double? _optd(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  return null;
}

GenerationSnapshot snapshotFromCoreJson(
  Map<String, dynamic> j, {
  required GenerationHistory history,
  required Duration elapsed,
}) {
  double d(String k, [double def = 0.0]) => _optd(j, k) ?? def;
  int n(String k, [int def = 0]) => (j[k] as num?)?.toInt() ?? def;
  List<double> arr(String k) {
    final raw = j[k];
    if (raw is List) {
      return raw.map((e) => e is num ? e.toDouble() : double.nan).toList();
    }
    return const [];
  }

  List<String> strs(String k) {
    final raw = j[k];
    return raw is List ? raw.map((e) => e.toString()).toList() : const [];
  }

  Map<String, double> numMap(String k) {
    final raw = j[k];
    if (raw is Map) {
      return {
        for (final e in raw.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
      };
    }
    return const {};
  }

  final gen = n('generation');
  final bestFitness = d('best_fitness', double.infinity);

  // Improvement metrics from previously recorded (distinct) generations.
  final fitHistory = history.fitnessHistory;
  double impAbs = 0, impRel = 0;
  if (fitHistory.isNotEmpty) {
    final prev = fitHistory.last;
    impAbs = prev - bestFitness;
    impRel = prev.abs() > 1e-30 ? impAbs / prev.abs() : 0;
  }
  double improvementRate(int window) {
    if (fitHistory.length < window) return 0;
    final old = fitHistory[fitHistory.length - window];
    if (old.abs() < 1e-30) return 0;
    return (old - bestFitness) / old.abs();
  }

  final islands = <IslandStatus>[];
  final rawIslands = j['islands'];
  if (rawIslands is List) {
    for (final e in rawIslands) {
      if (e is Map<String, dynamic>) islands.add(IslandStatus.fromJson(e));
    }
  }
  final stability = j['stability'] is Map<String, dynamic>
      ? j['stability'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final search = j['search'] is Map<String, dynamic>
      ? j['search'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final worst = islands.map((s) => s.worstFitness).whereType<double>();
  final q = islands.map((s) => s.medianFitness).whereType<double>().toList()..sort();
  final err = arr('err');
  final acf = arr('residual_autocorr');

  return GenerationSnapshot(
    generation: gen,
    elapsed: elapsed,
    bestFitness: bestFitness,
    worstFitness: worst.isEmpty ? double.infinity : worst.reduce((a, b) => a > b ? a : b),
    meanFitness: d('fitness_mean', double.nan),
    medianFitness: d('fitness_median', double.nan),
    stdDevFitness: d('population_diversity'),
    q1Fitness: q.isEmpty ? double.nan : q.first,
    q3Fitness: q.isEmpty ? double.nan : q.last,
    improvementAbsolute: impAbs,
    improvementRelative: impRel,
    improvementRate5: improvementRate(5),
    improvementRate20: improvementRate(20),
    stagnationCounter: n('global_stagnation', n('stagnation')),
    uniqueStructures: n('unique_structures'),
    structureEntropy: d('structure_entropy'),
    phenotypicDiversity: d('population_diversity'),
    regressorFrequency: const {},
    populationVariance: d('population_variance'),
    successRate: d('success_rate'),
    successRateHistory: history.successRateHistory(),
    bestModelComplexity: n('num_terms'),
    bestModelMaxDegree: d('max_exponent'),
    bestModelMaxDelay: n('max_delay'),
    // ERR now arrives in its own field; older cores reused the ACF slot.
    bestModelERR: err.isNotEmpty || j.containsKey('err') ? err : acf,
    bestModelTermLabels: strs('term_labels'),
    bestModelRMSE: d('rmse_train', double.nan),
    bestModelValidationRMSE: _optd(j, 'rmse_validation'),
    bestModelR2: d('r2_train', double.nan),
    residualAutocorrelation: j.containsKey('err') && acf.isNotEmpty ? acf : null,
    islandSnapshots: const [],
    migrationImpact: null,
    phase: n('phase'),
    phaseName: (j['phase_name'] as String?) ?? '',
    freeRunRmse: _optd(j, 'free_run_rmse'),
    inputContributionRatio: _optd(j, 'input_contribution_ratio'),
    residualInputCorr: _optd(j, 'residual_input_corr'),
    fitnessBreakdown: numMap('fitness_breakdown'),
    bestContextsSurvived: n('best_contexts_survived'),
    bestWorstFitnessSeen: _optd(j, 'best_worst_fitness_seen'),
    islandRoles: strs('island_roles'),
    evaluations: n('evaluations'),
    globalStagnation: n('global_stagnation'),
    stopReason: (j['stop_reason'] as String?) ?? '',
    islandStatuses: islands,
    parameters: numMap('parameters'),
    effectiveWeights: numMap('effective_weights'),
    bestModelValidationR2: _optd(j, 'r2_validation'),
    freeRunRmseValidationFull: _optd(j, 'free_run_rmse_val_full'),
    freeRunR2ValidationFull: _optd(j, 'free_run_r2_val_full'),
    isStable: j['is_stable'] as bool?,
    freeRunDiverged: (stability['free_run_diverged'] as bool? ?? false) ||
        (stability['free_run_val_diverged'] as bool? ?? false),
    minAbsDenominator: _optd(stability, 'min_abs_denominator'),
    linearSpectralRadius: _optd(stability, 'linear_spectral_radius'),
    residualAcfBound: _optd(j, 'residual_acf_bound'),
    residualWhite: j['residual_white'] as bool?,
    overfitting: j['overfitting'] as bool? ?? false,
    underfitting: j['underfitting'] as bool? ?? false,
    alerts: (j['alerts'] as String?) ?? '',
    meanNumRegressors: _optd(j, 'mean_num_regressors'),
    meanMuF: _optd(j, 'mu_f'),
    meanMuCR: _optd(j, 'mu_cr'),
    agentInfo: j['agent'] is Map<String, dynamic> ? j['agent'] as Map<String, dynamic> : const {},
    errorMode: (search['error_mode'] as String?) ?? '',
    fitMethod: (search['fit_method'] as String?) ?? '',
    admissibilityVeto: search['admissibility_veto'] as bool? ?? false,
    finalRefine: (search['final_refine'] as String?) ?? '',
    championAdmissible: j['champion_admissible'] as bool?,
  );
}

/// Engine configuration built from the parameter registry plus overrides.
/// The keys are those of docs/CONFIGURATION.md.
String buildCoreConfigJson(
  ParameterRegistry parameters, {
  required int outputCol,
  required int numIslands,
  int webSocketPort = 8765,
  Map<String, Object?> overrides = const {},
}) {
  double p(String k) => parameters.get(k)?.currentValue ?? 0.0;
  int i(String k) => p(k).round();
  return jsonEncode({
    'normalizerType': 'minmax',
    'outputCol': outputCol,
    'numIslands': numIslands,
    'populationSize': i('populationSize'),
    'mutationFactor': p('mutationFactor'),
    'crossoverRate': p('crossoverRate'),
    'elitismCount': i('elitismCount'),
    'migrationInterval': i('migrationInterval'),
    'migrationRate': p('migrationRate'),
    'maxRegressors': i('maxRegressors'),
    'maxDelay': i('maxDelay'),
    'pmin': 0.5,
    'pmax': p('maxExponent'),
    'exponentStep': 0.5,
    'powerMode': 'hybrid',
    'stagnationLimit': i('stagnationLimit'),
    'complexityPenalty': p('complexityPenalty'),
    'noInputPenalty': p('noInputPenalty'),
    'freeRunPenalty': p('freeRunPenalty'),
    'freeRunHorizon': i('freeRunHorizon'),
    'inputContributionMin': p('inputContributionMin'),
    'gammaAnnealStart': p('gammaAnnealStart'),
    'gammaAnnealEnd': p('gammaAnnealEnd'),
    'phaseStagnationLimit': i('phaseStagnationLimit'),
    'reinitializationRatio': p('reinitializationRatio'),
    'webSocketPort': webSocketPort,
    ...overrides,
  });
}
