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
  final double bestModelRMSE;
  final double? bestModelValidationRMSE;
  final double bestModelR2;
  final List<double>? residualAutocorrelation;

  // ── Per-island ──
  final List<IslandSnapshot> islandSnapshots;
  final double? migrationImpact;

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
    required this.bestModelRMSE,
    this.bestModelValidationRMSE,
    required this.bestModelR2,
    this.residualAutocorrelation,
    required this.islandSnapshots,
    this.migrationImpact,
  });

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
