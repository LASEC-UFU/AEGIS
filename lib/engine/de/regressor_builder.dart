import 'dart:math' as math;

import '../../core/math/matrix.dart';
import '../../core/types/types.dart';

/// Builds regressor matrices from chromosome structure and data.
///
/// Given a chromosome's regressors and the data matrix, constructs
/// the Ψ matrix where each column is a regressor evaluated at all time steps.
class RegressorBuilder {
  RegressorBuilder._();

  /// Builds the regressor matrix for a chromosome.
  ///
  /// [chromosome]: defines the model structure.
  /// [data]: normalized data matrix (samples × variables), column-major.
  ///
  /// Returns a matrix of size (nSamples - maxDelay) × nRegressors,
  /// or null if the chromosome is invalid.
  static Matrix? buildMatrix(Chromosome chromosome, Matrix data) {
    final nSamples = data.rows;
    final maxDelay = chromosome.maxDelay;
    if (maxDelay >= nSamples) return null;

    final effectiveSamples = nSamples - maxDelay;
    final nRegs = chromosome.regressors.length;
    if (nRegs == 0) return null;

    final result = Matrix(effectiveSamples, nRegs);

    for (var j = 0; j < nRegs; j++) {
      final reg = chromosome.regressors[j];

      for (var t = 0; t < effectiveSamples; t++) {
        final k = t + maxDelay; // absolute time index
        var value = 1.0;

        for (final comp in reg.components) {
          final varIdx = comp.term.variable;
          final delay = comp.term.delay;

          if (varIdx < 0 || varIdx >= data.cols) return null;
          if (k - delay < 0) return null;

          final x = data.get(k - delay, varIdx);
          value *= math.pow(x, comp.exponent);

          if (value.isNaN || value.isInfinite) {
            value = 0.0;
            break;
          }
        }

        result.set(t, j, value);
      }
    }

    return result;
  }
}
