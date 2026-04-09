import '../../core/types/types.dart';
import '../../core/random/xorshift128.dart';

/// Generates random chromosomes for initial population.
///
/// Fixes original bug where chromosomes were hardcoded with fixed regressors.
/// Now generates truly random model structures within configurable bounds.
class ChromosomeFactory {
  /// Maximum number of regressors per chromosome.
  final int maxRegressors;

  /// Minimum number of regressors.
  final int minRegressors;

  /// Maximum number of terms (factors) per regressor.
  final int maxTermsPerRegressor;

  /// Maximum exponent value.
  final double maxExponent;

  /// Minimum exponent value.
  final double minExponent;

  /// Maximum delay (k - maxDelay).
  final int maxDelay;

  /// Number of input+output variables available.
  final int numVariables;

  /// Number of output variables (last N variables are outputs).
  final int numOutputs;

  /// Whether to allow rational (denominator) terms.
  final bool allowRational;

  const ChromosomeFactory({
    required this.numVariables,
    this.numOutputs = 1,
    this.maxRegressors = 8,
    this.minRegressors = 2,
    this.maxTermsPerRegressor = 3,
    this.maxExponent = 3.0,
    this.minExponent = 1.0,
    this.maxDelay = 20,
    this.allowRational = false,
  });

  /// Creates a single random chromosome.
  Chromosome create(Xorshift128Plus rng, {int outputIndex = 0}) {
    final numRegs = rng.nextIntBetween(minRegressors, maxRegressors);
    final regressors = <Regressor>[];

    for (var i = 0; i < numRegs; i++) {
      final numTerms = rng.nextIntBetween(1, maxTermsPerRegressor);
      final components = <CompoundTerm>[];
      final usedTerms = <int>{}; // Avoid duplicate terms in same regressor

      for (var j = 0; j < numTerms; j++) {
        final variable = rng.nextIntRange(numVariables);
        final delay = rng.nextIntBetween(1, maxDelay);
        final encoded = variable * 1000 + delay;

        if (usedTerms.contains(encoded)) continue;
        usedTerms.add(encoded);

        // Exponent: integer or half-integer steps
        final expSteps = ((maxExponent - minExponent) * 2).toInt() + 1;
        final expIdx = rng.nextIntRange(expSteps);
        final exponent = minExponent + expIdx * 0.5;

        final isDenom = allowRational && rng.nextDouble() < 0.2;

        components.add(
          CompoundTerm(
            term: Term(
              variable: variable,
              delay: delay,
              isDenominator: isDenom,
            ),
            exponent: exponent,
          ),
        );
      }

      if (components.isNotEmpty) {
        regressors.add(Regressor(components));
      }
    }

    if (regressors.isEmpty) {
      // Fallback: at least one simple regressor
      regressors.add(
        Regressor([
          CompoundTerm(
            term: Term(variable: numVariables - numOutputs, delay: 1),
            exponent: 1.0,
          ),
        ]),
      );
    }

    final maxDly = regressors
        .map((r) => r.maxDelay)
        .reduce((a, b) => a > b ? a : b);

    return Chromosome(
      regressors: regressors,
      outputIndex: outputIndex,
      maxDelay: maxDly,
    );
  }

  /// Creates an initial population of [size] random chromosomes.
  List<Chromosome> createPopulation(
    int size,
    Xorshift128Plus rng, {
    int outputIndex = 0,
  }) {
    return List.generate(size, (_) => create(rng, outputIndex: outputIndex));
  }
}
