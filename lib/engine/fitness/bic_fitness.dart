import 'dart:math' as math;

import '../../core/math/matrix.dart';
import '../../core/math/decomposition.dart';
import '../../core/types/chromosome.dart';
import 'fitness_evaluator.dart';
import 'err_calculator.dart';

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
    final k = regressorMatrix.cols;

    // QR decomposition for stable least squares
    final (q, r) = Decomposition.modifiedGramSchmidt(regressorMatrix);
    final qtY = q.transpose().multiply(output);
    final coefficients = Decomposition.backSubstitute(
      r.subMatrix(0, k, 0, k),
      qtY.subMatrix(0, k, 0, 1),
    );

    // Compute residuals and SSE
    final predicted = regressorMatrix.multiply(coefficients);
    final residuals = output - predicted;
    final sse = residuals.sumOfSquares();

    // Compute ERR values
    final errValues = errCalculator.computeERR(
      regressorMatrix,
      output,
      chromosome.regressors,
    );

    final fitness = evaluate(sse, n, k);

    return chromosome.withEvaluation(
      coefficients: List<double>.generate(k, (i) => coefficients.get(i, 0)),
      err: errValues,
      fitness: fitness,
      sse: sse,
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
    final k = regressorMatrix.cols;
    final (q, r) = Decomposition.modifiedGramSchmidt(regressorMatrix);
    final qtY = q.transpose().multiply(output);
    final coefficients = Decomposition.backSubstitute(
      r.subMatrix(0, k, 0, k),
      qtY.subMatrix(0, k, 0, 1),
    );
    final predicted = regressorMatrix.multiply(coefficients);
    final residuals = output - predicted;
    final sse = residuals.sumOfSquares();
    final errValues = errCalculator.computeERR(
      regressorMatrix,
      output,
      chromosome.regressors,
    );
    final fitness = evaluate(sse, n, k);
    return chromosome.withEvaluation(
      coefficients: List<double>.generate(k, (i) => coefficients.get(i, 0)),
      err: errValues,
      fitness: fitness,
      sse: sse,
    );
  }
}
