import 'dart:math' as math;

import '../../../core/types/types.dart';
import '../../../core/random/xorshift128.dart';
import 'mutation_strategy.dart';

/// JADE (Adaptive Differential Evolution with Optional External Archive).
///
/// Adapts F and CR per-individual using Cauchy(μ_F, 0.1) and Normal(μ_CR, 0.1).
/// μ_F and μ_CR are updated via Lehmer mean and arithmetic mean of successful values.
///
/// This fixes the original code's problem of using F ~ U(-2, 2) which is
/// non-standard and leads to poor convergence.
class JadeMutation implements MutationStrategy {
  /// Adaptation rate for μ_F and μ_CR.
  final double c;

  /// Current location parameter for F (updated externally by the island).
  double muF;

  /// Current location parameter for CR (updated externally by the island).
  double muCR;

  /// History of successful F values for adaptation.
  final List<double> _successfulF = [];

  /// History of successful CR values for adaptation.
  final List<double> _successfulCR = [];

  JadeMutation({this.c = 0.1, this.muF = 0.5, this.muCR = 0.5});

  @override
  String get name => 'JADE';

  /// Generate adaptive F for this individual.
  double generateF(Xorshift128Plus rng) {
    double f;
    do {
      f = rng.nextCauchy(location: muF, scale: 0.1);
    } while (f <= 0);
    return f.clamp(0.0, 1.0);
  }

  /// Generate adaptive CR for this individual.
  double generateCR(Xorshift128Plus rng) {
    return rng.nextGaussian(mean: muCR, stdDev: 0.1).clamp(0.0, 1.0);
  }

  /// Record a successful F value.
  void recordSuccess(double f, double cr) {
    _successfulF.add(f);
    _successfulCR.add(cr);
  }

  /// Update μ_F and μ_CR at end of generation.
  void endGeneration() {
    if (_successfulF.isNotEmpty) {
      // Lehmer mean for F (favors large successful F values)
      final sumF2 = _successfulF.fold(0.0, (s, f) => s + f * f);
      final sumF = _successfulF.fold(0.0, (s, f) => s + f);
      if (sumF > 0) {
        muF = (1 - c) * muF + c * (sumF2 / sumF);
      }

      // Arithmetic mean for CR
      final meanCR =
          _successfulCR.fold(0.0, (s, cr) => s + cr) / _successfulCR.length;
      muCR = (1 - c) * muCR + c * meanCR;
    }

    _successfulF.clear();
    _successfulCR.clear();
  }

  @override
  Chromosome mutate({
    required int target,
    required List<Chromosome> population,
    required int best,
    required Xorshift128Plus rng,
    required MutationParams params,
  }) {
    // DE/current-to-pbest/1: v = x_i + F*(x_pbest - x_i) + F*(x_r1 - x_r2)
    final f = params.f;
    final xi = population[target];

    // p-best: random among top p% (p = max(2, 0.05*N))
    final p = math.max(2, (0.05 * population.length).ceil());
    final pbestIdx = rng.nextIntRange(p);
    final sortedByFitness = List<int>.generate(population.length, (i) => i)
      ..sort((a, b) => population[a].fitness.compareTo(population[b].fitness));
    final xpbest = population[sortedByFitness[pbestIdx]];

    // Two distinct random individuals
    int r1, r2;
    do {
      r1 = rng.nextIntRange(population.length);
    } while (r1 == target);
    do {
      r2 = rng.nextIntRange(population.length);
    } while (r2 == target || r2 == r1);
    final xr1 = population[r1];
    final xr2 = population[r2];

    // Build mutant: exponent-level mutation
    final newRegressors = <Regressor>[];
    final baseLen = xi.regressors.length;

    for (var i = 0; i < baseLen; i++) {
      final baseReg = xi.regressors[i];
      final newComponents = <CompoundTerm>[];

      for (var j = 0; j < baseReg.components.length; j++) {
        final b = baseReg.components[j];
        double ePbest = b.exponent;
        double eR1 = b.exponent;
        double eR2 = b.exponent;

        if (i < xpbest.regressors.length &&
            j < xpbest.regressors[i].components.length) {
          ePbest = xpbest.regressors[i].components[j].exponent;
        }
        if (i < xr1.regressors.length &&
            j < xr1.regressors[i].components.length) {
          eR1 = xr1.regressors[i].components[j].exponent;
        }
        if (i < xr2.regressors.length &&
            j < xr2.regressors[i].components.length) {
          eR2 = xr2.regressors[i].components[j].exponent;
        }

        var newExp = b.exponent + f * (ePbest - b.exponent) + f * (eR1 - eR2);
        newExp = newExp.clamp(0.5, 5.0);
        newExp = (newExp * 2).roundToDouble() / 2;

        newComponents.add(b.copyWith(exponent: newExp));
      }

      newRegressors.add(Regressor(newComponents));
    }

    return xi.withRegressors(newRegressors);
  }
}
