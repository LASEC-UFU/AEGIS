import 'regressor.dart';

/// Immutable chromosome representing a NARX model candidate.
///
/// Contains the model structure (list of regressors), coefficients,
/// ERR values, fitness score, and prediction error.
class Chromosome {
  /// Ordered list of regressors defining the model structure.
  final List<Regressor> regressors;

  /// Computed coefficients (one per regressor). Null before evaluation.
  final List<double>? coefficients;

  /// ERR (Error Reduction Ratio) per regressor. Null before evaluation.
  final List<double>? err;

  /// Fitness value (BIC, AIC, etc.). Lower is better. NaN if not evaluated.
  final double fitness;

  /// Sum of squared errors on training data.
  final double sse;

  /// Output index this chromosome targets (for MIMO systems).
  final int outputIndex;

  /// Maximum delay across all regressors.
  final int maxDelay;

  const Chromosome({
    required this.regressors,
    this.coefficients,
    this.err,
    this.fitness = double.nan,
    this.sse = double.nan,
    this.outputIndex = 0,
    this.maxDelay = 0,
  });

  /// Number of regressors (model complexity).
  int get numRegressors => regressors.length;

  /// Whether this chromosome has been evaluated.
  bool get isEvaluated => !fitness.isNaN;

  /// Maximum degree (exponent) used in any regressor.
  double get maxDegree {
    if (regressors.isEmpty) return 0;
    return regressors.map((r) => r.maxExponent).reduce((a, b) => a > b ? a : b);
  }

  /// Whether the model is rational (has denominator terms).
  bool get isRational => regressors.any((r) => r.isDenominator);

  /// Structural hash for diversity calculation.
  int get structuralHash {
    var h = 0;
    for (final r in regressors) {
      h = h * 37 + r.structuralHash;
    }
    return h;
  }

  /// Creates a new chromosome with updated evaluation results.
  Chromosome withEvaluation({
    required List<double> coefficients,
    required List<double> err,
    required double fitness,
    required double sse,
  }) {
    return Chromosome(
      regressors: regressors,
      coefficients: coefficients,
      err: err,
      fitness: fitness,
      sse: sse,
      outputIndex: outputIndex,
      maxDelay: maxDelay,
    );
  }

  /// Creates a copy with modified regressors (for mutation).
  Chromosome withRegressors(List<Regressor> newRegressors) {
    return Chromosome(
      regressors: newRegressors,
      outputIndex: outputIndex,
      maxDelay: newRegressors.isEmpty
          ? 0
          : newRegressors
                .map((r) => r.maxDelay)
                .reduce((a, b) => a > b ? a : b),
    );
  }

  Chromosome copyWith({
    List<Regressor>? regressors,
    List<double>? coefficients,
    List<double>? err,
    double? fitness,
    double? sse,
    int? outputIndex,
    int? maxDelay,
  }) {
    return Chromosome(
      regressors: regressors ?? this.regressors,
      coefficients: coefficients ?? this.coefficients,
      err: err ?? this.err,
      fitness: fitness ?? this.fitness,
      sse: sse ?? this.sse,
      outputIndex: outputIndex ?? this.outputIndex,
      maxDelay: maxDelay ?? this.maxDelay,
    );
  }

  @override
  String toString() =>
      'Chromosome(${regressors.length} regressors, fitness=${fitness.toStringAsFixed(6)})';
}
