import '../../core/math/matrix.dart';
import '../../core/types/chromosome.dart';

/// Abstract fitness evaluator. Different criteria (BIC, AIC, MDL) implement this.
abstract class FitnessEvaluator {
  /// Computes the fitness of a model given:
  /// - [sse]: sum of squared errors
  /// - [numSamples]: number of data points
  /// - [numParams]: number of model parameters (regressors)
  double evaluate(double sse, int numSamples, int numParams);

  /// Full evaluation pipeline: compute coefficients, SSE, and fitness.
  Chromosome evaluateChromosome(
    Chromosome chromosome,
    Matrix regressorMatrix,
    Matrix output,
  );
}
