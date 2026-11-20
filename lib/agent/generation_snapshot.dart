import '../engine/de/island.dart';

/// Immutable snapshot of one generation's state across all islands.
///
/// This is the primary data structure the agent analyzes.
class GenerationSnapshot {
  final int generation;
  final Duration elapsed;

  // ── Global fitness ──
  final double bestFitness;
  final double worstFitness;
  final double meanFitness;
  final double medianFitness;
  final double stdDevFitness;
  final double q1Fitness;
  final double q3Fitness;

  // ── Improvement ──
  final double improvementAbsolute;
  final double improvementRelative;
  final double improvementRate5;
  final double improvementRate20;
  final int stagnationCounter;

  // ── Diversity ──
  final int uniqueStructures;
  final double structureEntropy;
  final double phenotypicDiversity;
  final Map<int, double> regressorFrequency;

  // ── Convergence ──
  final double populationVariance;
  final double successRate;
  final List<double> successRateHistory;

  // ── Model quality ──
  final int bestModelComplexity;
  final double bestModelMaxDegree;
  final int bestModelMaxDelay;
  final List<double> bestModelERR;
  final List<String> bestModelTermLabels;
  final double bestModelRMSE;
  final double? bestModelValidationRMSE;
  final double bestModelR2;
  final List<double>? residualAutocorrelation;

  // ── Per-island ──
  final List<IslandSnapshot> islandSnapshots;
  final double? migrationImpact;

  // ── AEGIS Curriculum (phased identification) ──
  final int phase;
  final String phaseName;
  final double? freeRunRmse;
  final double? inputContributionRatio;
  final double? residualInputCorr;
  final Map<String, double> fitnessBreakdown;

  // ── Specialized islands / two-layer migration filter ──
  final int bestContextsSurvived;
  final double? bestWorstFitnessSeen;
  final List<String> islandRoles;

  // ── Audit additions (C++ core ≥ 1.1.0; empty/null for older engines) ──
  /// Cumulative objective-function evaluations.
  final int evaluations;
  /// Generations without improvement of the canonical champion.
  final int globalStagnation;
  /// Non-empty once the run stopped (max_generations, stagnation, …).
  final String stopReason;
  /// Real per-island statistics published by the C++ core.
  final List<IslandStatus> islandStatuses;
  /// Current (base) value of every agent-tunable parameter.
  final Map<String, double> parameters;
  /// Fitness weights actually in effect (after curriculum phase rules).
  final Map<String, double> effectiveWeights;
  /// Validation R² of the champion (one-step).
  final double? bestModelValidationR2;
  /// Full-length free-run RMSE / R² of the champion on the validation split.
  final double? freeRunRmseValidationFull;
  final double? freeRunR2ValidationFull;
  /// Stability diagnostics of the champion.
  final bool? isStable;
  final bool freeRunDiverged;
  final double? minAbsDenominator;
  final double? linearSpectralRadius;
  /// 95 % band for the residual autocorrelation and whiteness verdict.
  final double? residualAcfBound;
  final bool? residualWhite;
  final bool overfitting;
  final bool underfitting;
  final String alerts;
  /// Mean number of regressors in the populations.
  final double? meanNumRegressors;
  final double? meanMuF;
  final double? meanMuCR;
  /// Agent bookkeeping reported by the core (accepted/rejected/pending).
  final Map<String, dynamic> agentInfo;

  const GenerationSnapshot({
    required this.generation,
    required this.elapsed,
    required this.bestFitness,
    required this.worstFitness,
    required this.meanFitness,
    required this.medianFitness,
    required this.stdDevFitness,
    required this.q1Fitness,
    required this.q3Fitness,
    required this.improvementAbsolute,
    required this.improvementRelative,
    required this.improvementRate5,
    required this.improvementRate20,
    required this.stagnationCounter,
    required this.uniqueStructures,
    required this.structureEntropy,
    required this.phenotypicDiversity,
    required this.regressorFrequency,
    required this.populationVariance,
    required this.successRate,
    required this.successRateHistory,
    required this.bestModelComplexity,
    required this.bestModelMaxDegree,
    required this.bestModelMaxDelay,
    required this.bestModelERR,
    this.bestModelTermLabels = const [],
    required this.bestModelRMSE,
    this.bestModelValidationRMSE,
    required this.bestModelR2,
    this.residualAutocorrelation,
    required this.islandSnapshots,
    this.migrationImpact,
    this.phase = 0,
    this.phaseName = '',
    this.freeRunRmse,
    this.inputContributionRatio,
    this.residualInputCorr,
    this.fitnessBreakdown = const {},
    this.bestContextsSurvived = 0,
    this.bestWorstFitnessSeen,
    this.islandRoles = const [],
    this.evaluations = 0,
    this.globalStagnation = 0,
    this.stopReason = '',
    this.islandStatuses = const [],
    this.parameters = const {},
    this.effectiveWeights = const {},
    this.bestModelValidationR2,
    this.freeRunRmseValidationFull,
    this.freeRunR2ValidationFull,
    this.isStable,
    this.freeRunDiverged = false,
    this.minAbsDenominator,
    this.linearSpectralRadius,
    this.residualAcfBound,
    this.residualWhite,
    this.overfitting = false,
    this.underfitting = false,
    this.alerts = '',
    this.meanNumRegressors,
    this.meanMuF,
    this.meanMuCR,
    this.agentInfo = const {},
  });

  /// Compact, documented observation used by agents and trajectory logs
  /// (schema `aegis.observation/1`, see docs/AGENT_INTERFACE.md). Test-set
  /// metrics are never part of an observation.
  Map<String, dynamic> toObservation() => {
    'schema': 'aegis.observation/1',
    'generation': generation,
    'evaluations': evaluations,
    'phase': phase,
    'phaseName': phaseName,
    'bestFitness': _fin(bestFitness),
    'meanFitness': _fin(meanFitness),
    'stdDevFitness': _fin(stdDevFitness),
    'stagnation': stagnationCounter,
    'globalStagnation': globalStagnation,
    'successRate': _fin(successRate),
    'uniqueStructures': uniqueStructures,
    'structureEntropy': _fin(structureEntropy),
    'phenotypicDiversity': _fin(phenotypicDiversity),
    'meanNumRegressors': meanNumRegressors,
    'meanMuF': meanMuF,
    'meanMuCR': meanMuCR,
    'model': {
      'numRegressors': bestModelComplexity,
      'maxDelay': bestModelMaxDelay,
      'terms': bestModelTermLabels,
      'rmseTrain': _fin(bestModelRMSE),
      'rmseValidation': bestModelValidationRMSE,
      'r2Train': _fin(bestModelR2),
      'r2Validation': bestModelValidationR2,
      'freeRunRmseHorizon': freeRunRmse,
      'freeRunRmseValidationFull': freeRunRmseValidationFull,
      'freeRunR2ValidationFull': freeRunR2ValidationFull,
      'inputContributionRatio': inputContributionRatio,
      'residualInputCorr': residualInputCorr,
      'residualWhite': residualWhite,
      'isStable': isStable,
      'freeRunDiverged': freeRunDiverged,
      'minAbsDenominator': minAbsDenominator,
      'linearSpectralRadius': linearSpectralRadius,
      'overfitting': overfitting,
      'underfitting': underfitting,
      'fitnessBreakdown': fitnessBreakdown,
    },
    'islands': islandStatuses.map((s) => s.toMap()).toList(),
    'parameters': parameters,
    'effectiveWeights': effectiveWeights,
    'alerts': alerts,
    'stopReason': stopReason,
  };

  static double? _fin(double v) => v.isFinite ? v : null;

  /// Serializes to a map for JSON/message passing.
  Map<String, dynamic> toMap() => {
    'generation': generation,
    'elapsed_ms': elapsed.inMilliseconds,
    'bestFitness': bestFitness,
    'worstFitness': worstFitness,
    'meanFitness': meanFitness,
    'medianFitness': medianFitness,
    'stdDevFitness': stdDevFitness,
    'improvementAbsolute': improvementAbsolute,
    'improvementRelative': improvementRelative,
    'stagnationCounter': stagnationCounter,
    'uniqueStructures': uniqueStructures,
    'structureEntropy': structureEntropy,
    'successRate': successRate,
    'bestModelComplexity': bestModelComplexity,
    'bestModelRMSE': bestModelRMSE,
    'bestModelR2': bestModelR2,
    'phase': phase,
    'phaseName': phaseName,
    'freeRunRmse': freeRunRmse,
    'inputContributionRatio': inputContributionRatio,
    'residualInputCorr': residualInputCorr,
    'fitnessBreakdown': fitnessBreakdown,
    'bestContextsSurvived': bestContextsSurvived,
    'bestWorstFitnessSeen': bestWorstFitnessSeen,
    'islandRoles': islandRoles,
    'islands': islandSnapshots
        .map(
          (s) => {
            'id': s.islandId,
            'bestFitness': s.stats.bestFitness,
            'stagnation': s.stagnationCounter,
            'successRate': s.successRate,
            'muF': s.muF,
            'muCR': s.muCR,
          },
        )
        .toList(),
  };
}

/// Per-island statistics reported by the C++ core (fitness values are on
/// each island's own objective scale: roles and validation regimes differ).
class IslandStatus {
  final int id;
  final String role;
  final double? bestFitness;
  final double? meanFitness;
  final double? medianFitness;
  final double? stdFitness;
  final double? worstFitness;
  final int stagnation;
  final double successRate;
  final double muF;
  final double muCR;
  final int uniqueStructures;
  final int populationSize;
  final double? meanNumRegressors;
  final double? bestRmseVal;

  const IslandStatus({
    required this.id,
    this.role = 'balanced',
    this.bestFitness,
    this.meanFitness,
    this.medianFitness,
    this.stdFitness,
    this.worstFitness,
    this.stagnation = 0,
    this.successRate = 0,
    this.muF = 0,
    this.muCR = 0,
    this.uniqueStructures = 0,
    this.populationSize = 0,
    this.meanNumRegressors,
    this.bestRmseVal,
  });

  factory IslandStatus.fromJson(Map<String, dynamic> j) {
    double? d(String k) {
      final v = j[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return IslandStatus(
      id: i('id'),
      role: (j['role'] as String?) ?? 'balanced',
      bestFitness: d('best_fitness'),
      meanFitness: d('mean_fitness'),
      medianFitness: d('median_fitness'),
      stdFitness: d('std_fitness'),
      worstFitness: d('worst_fitness'),
      stagnation: i('stagnation'),
      successRate: d('success_rate') ?? 0,
      muF: d('mu_f') ?? 0,
      muCR: d('mu_cr') ?? 0,
      uniqueStructures: i('unique_structures'),
      populationSize: i('population_size'),
      meanNumRegressors: d('mean_num_regressors'),
      bestRmseVal: d('best_rmse_val'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'role': role,
    'bestFitness': bestFitness,
    'meanFitness': meanFitness,
    'medianFitness': medianFitness,
    'stdFitness': stdFitness,
    'worstFitness': worstFitness,
    'stagnation': stagnation,
    'successRate': successRate,
    'muF': muF,
    'muCR': muCR,
    'uniqueStructures': uniqueStructures,
    'populationSize': populationSize,
    'meanNumRegressors': meanNumRegressors,
    'bestRmseVal': bestRmseVal,
  };
}
