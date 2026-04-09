import '../../../core/types/types.dart';
import '../../../core/random/xorshift128.dart';
import 'mutation_strategy.dart';

/// DE/rand/1 mutation: v = x_r0 + F * (x_r1 - x_r2)
///
/// Operates at the regressor/exponent level.
class DeRand1 implements MutationStrategy {
  const DeRand1();

  @override
  String get name => 'DE/rand/1';

  @override
  Chromosome mutate({
    required int target,
    required List<Chromosome> population,
    required int best,
    required Xorshift128Plus rng,
    required MutationParams params,
  }) {
    // Select 3 distinct individuals different from target
    final indices = _selectDistinct(rng, population.length, 3, exclude: target);
    final x0 = population[indices[0]];
    final x1 = population[indices[1]];
    final x2 = population[indices[2]];

    return _differentialMutate(x0, x1, x2, params.f, rng);
  }

  Chromosome _differentialMutate(
    Chromosome base,
    Chromosome diff1,
    Chromosome diff2,
    double f,
    Xorshift128Plus rng,
  ) {
    final newRegressors = <Regressor>[];

    // Mutate exponents of matching regressors
    for (var i = 0; i < base.regressors.length; i++) {
      final baseReg = base.regressors[i];
      final newComponents = <CompoundTerm>[];

      for (var j = 0; j < baseReg.components.length; j++) {
        final baseComp = baseReg.components[j];
        double exp1 = baseComp.exponent;
        double exp2 = baseComp.exponent;

        // Try to find matching components in diff1 and diff2
        if (i < diff1.regressors.length &&
            j < diff1.regressors[i].components.length) {
          exp1 = diff1.regressors[i].components[j].exponent;
        }
        if (i < diff2.regressors.length &&
            j < diff2.regressors[i].components.length) {
          exp2 = diff2.regressors[i].components[j].exponent;
        }

        var newExp = baseComp.exponent + f * (exp1 - exp2);
        // Clamp exponent to valid range [0.5, 5.0]
        newExp = newExp.clamp(0.5, 5.0);
        // Round to nearest 0.5 for interpretability
        newExp = (newExp * 2).roundToDouble() / 2;

        newComponents.add(baseComp.copyWith(exponent: newExp));
      }

      newRegressors.add(Regressor(newComponents));
    }

    return base.withRegressors(newRegressors);
  }

  static List<int> _selectDistinct(
    Xorshift128Plus rng,
    int max,
    int count, {
    required int exclude,
  }) {
    final selected = <int>[];
    while (selected.length < count) {
      final idx = rng.nextIntRange(max);
      if (idx != exclude && !selected.contains(idx)) {
        selected.add(idx);
      }
    }
    return selected;
  }
}
