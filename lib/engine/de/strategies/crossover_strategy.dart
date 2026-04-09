import '../../../core/types/types.dart';
import '../../../core/random/xorshift128.dart';

/// Abstract crossover strategy.
abstract class CrossoverStrategy {
  /// Produces a trial vector by crossing [target] with [mutant].
  /// [cr] is the crossover rate.
  Chromosome crossover({
    required Chromosome target,
    required Chromosome mutant,
    required double cr,
    required Xorshift128Plus rng,
  });

  String get name;
}

/// Binomial (uniform) crossover: each regressor is independently
/// taken from mutant with probability CR.
class BinomialCrossover implements CrossoverStrategy {
  const BinomialCrossover();

  @override
  String get name => 'Binomial';

  @override
  Chromosome crossover({
    required Chromosome target,
    required Chromosome mutant,
    required double cr,
    required Xorshift128Plus rng,
  }) {
    final len = target.regressors.length;
    final jrand = rng.nextIntRange(len); // Ensure at least one from mutant
    final newRegressors = <Regressor>[];

    for (var i = 0; i < len; i++) {
      if (i == jrand || rng.nextDouble() < cr) {
        // Take from mutant (if available, else keep target)
        newRegressors.add(
          i < mutant.regressors.length
              ? mutant.regressors[i]
              : target.regressors[i],
        );
      } else {
        newRegressors.add(target.regressors[i]);
      }
    }

    return target.withRegressors(newRegressors);
  }
}

/// Exponential crossover: a contiguous segment is taken from mutant.
class ExponentialCrossover implements CrossoverStrategy {
  const ExponentialCrossover();

  @override
  String get name => 'Exponential';

  @override
  Chromosome crossover({
    required Chromosome target,
    required Chromosome mutant,
    required double cr,
    required Xorshift128Plus rng,
  }) {
    final len = target.regressors.length;
    final newRegressors = List<Regressor>.from(target.regressors);

    var start = rng.nextIntRange(len);
    var i = start;
    do {
      newRegressors[i] = i < mutant.regressors.length
          ? mutant.regressors[i]
          : target.regressors[i];
      i = (i + 1) % len;
    } while (rng.nextDouble() < cr && i != start);

    return target.withRegressors(newRegressors);
  }
}
