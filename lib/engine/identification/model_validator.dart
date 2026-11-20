import 'dart:math' as math;

import '../../core/math/matrix.dart';
import '../../core/types/chromosome.dart';
import '../de/regressor_builder.dart';

/// Validates identified models on independent data (one-step-ahead
/// prediction with the fitted coefficients and intercept).
class ModelValidator {
  ModelValidator._();

  /// One-step predictions and the matching measured outputs, or null.
  static (Matrix predicted, Matrix actual)? _predict(Chromosome model, Matrix data, int outputCol) {
    final regressorMatrix = RegressorBuilder.buildMatrix(model, data);
    if (regressorMatrix == null || model.coefficients == null) return null;
    final predicted = regressorMatrix.multiply(Matrix.columnVector(model.coefficients!));
    for (var i = 0; i < predicted.rows; i++) {
      predicted.set(i, 0, predicted.get(i, 0) + model.intercept);
    }
    final actual = data.column(outputCol).subMatrix(model.maxDelay, data.rows, 0, 1);
    return (predicted, actual);
  }

  /// Computes RMSE on a dataset.
  static double rmse(Chromosome model, Matrix data, int outputCol) {
    final p = _predict(model, data, outputCol);
    if (p == null) return double.infinity;
    final (predicted, actual) = p;
    var sse = 0.0;
    for (var i = 0; i < predicted.rows; i++) {
      final e = actual.get(i, 0) - predicted.get(i, 0);
      sse += e * e;
    }
    return math.sqrt(sse / predicted.rows);
  }

  /// Computes R² (coefficient of determination).
  static double r2(Chromosome model, Matrix data, int outputCol) {
    final p = _predict(model, data, outputCol);
    if (p == null) return double.negativeInfinity;
    final (predicted, actual) = p;
    final n = predicted.rows;
    var meanY = 0.0;
    for (var i = 0; i < n; i++) {
      meanY += actual.get(i, 0);
    }
    meanY /= n;
    var ssRes = 0.0, ssTot = 0.0;
    for (var i = 0; i < n; i++) {
      final y = actual.get(i, 0);
      final yHat = predicted.get(i, 0);
      ssRes += (y - yHat) * (y - yHat);
      ssTot += (y - meanY) * (y - meanY);
    }
    if (ssTot < 1e-30) return 0.0;
    return 1.0 - ssRes / ssTot;
  }

  /// Computes prediction residuals.
  static Matrix residuals(Chromosome model, Matrix data, int outputCol) {
    final p = _predict(model, data, outputCol);
    if (p == null) return Matrix(0, 0);
    final (predicted, actual) = p;
    return actual - predicted;
  }
}
