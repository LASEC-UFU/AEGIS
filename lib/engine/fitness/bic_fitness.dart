import 'dart:math' as math;

import '../../core/math/matrix.dart';
import '../../core/types/chromosome.dart';
import 'fitness_evaluator.dart';
import 'err_calculator.dart';
import 'least_squares.dart';

/// BIC (Bayesian Information Criterion) fitness evaluator.
///
/// BIC = n * ln(SSE/n) + k * ln(n)
/// where n = number of samples, k = number of parameters.
///
/// Lower BIC = better model (balances fit vs complexity).
class BicFitness implements FitnessEvaluator {
  final ERRCalculator errCalculator;

  const BicFitness({this.errCalculator = const ERRCalculator()});

  @override
  double evaluate(double sse, int numSamples, int numParams) {
    if (sse <= 0 || numSamples <= 0 || numParams <= 0) return double.infinity;
    return numSamples * math.log(sse / numSamples) +
        numParams * math.log(numSamples);
  }

  @override
  Chromosome evaluateChromosome(
    Chromosome chromosome,
    Matrix regressorMatrix,
    Matrix output,
  ) {
    final n = regressorMatrix.rows;
    final k = regressorMatrix.cols + 1; // regressors + intercept
    final fit = LeastSquaresFit.fit(regressorMatrix, output);
    final errValues = errCalculator.computeERR(
      regressorMatrix,
      output,
      chromosome.regressors,
    );
    final fitness = evaluate(fit.sse, n, k);
    return chromosome.withEvaluation(
      coefficients: fit.coefficients,
      intercept: fit.intercept,
      err: errValues,
      fitness: fitness,
      sse: fit.sse,
    );
  }
}

/// AIC (Akaike Information Criterion) fitness evaluator.
///
/// AIC = n * ln(SSE/n) + 2k
class AicFitness implements FitnessEvaluator {
  final ERRCalculator errCalculator;

  const AicFitness({this.errCalculator = const ERRCalculator()});

  @override
  double evaluate(double sse, int numSamples, int numParams) {
    if (sse <= 0 || numSamples <= 0 || numParams <= 0) return double.infinity;
    return numSamples * math.log(sse / numSamples) + 2 * numParams;
  }

  @override
  Chromosome evaluateChromosome(
    Chromosome chromosome,
    Matrix regressorMatrix,
    Matrix output,
  ) {
    final n = regressorMatrix.rows;
    final k = regressorMatrix.cols + 1; // regressors + intercept
    final fit = LeastSquaresFit.fit(regressorMatrix, output);
    final errValues = errCalculator.computeERR(
      regressorMatrix,
      output,
      chromosome.regressors,
    );
    final fitness = evaluate(fit.sse, n, k);
    return chromosome.withEvaluation(
      coefficients: fit.coefficients,
      intercept: fit.intercept,
      err: errValues,
      fitness: fitness,
      sse: fit.sse,
    );
  }
}
