import 'dart:math' as math;

import '../../core/math/matrix.dart';
import '../../core/types/chromosome.dart';
import '../de/regressor_builder.dart';

/// Validates identified models on independent data.
class ModelValidator {
  ModelValidator._();

  /// Computes RMSE on a dataset.
  static double rmse(Chromosome model, Matrix data, int outputCol) {
    final regressorMatrix = RegressorBuilder.buildMatrix(model, data);
    if (regressorMatrix == null || model.coefficients == null) {
      return double.infinity;
    }

    final n = regressorMatrix.rows;
    final coeffs = Matrix.columnVector(model.coefficients!);
    final predicted = regressorMatrix.multiply(coeffs);
    final actual = data
        .column(outputCol)
        .subMatrix(model.maxDelay, data.rows, 0, 1);

    var sse = 0.0;
    for (var i = 0; i < n; i++) {
      final e = actual.get(i, 0) - predicted.get(i, 0);
      sse += e * e;
    }
    return math.sqrt(sse / n);
  }

  /// Computes R² (coefficient of determination).
  static double r2(Chromosome model, Matrix data, int outputCol) {
    final regressorMatrix = RegressorBuilder.buildMatrix(model, data);
    if (regressorMatrix == null || model.coefficients == null) {
      return double.negativeInfinity;
    }

    final n = regressorMatrix.rows;
    final coeffs = Matrix.columnVector(model.coefficients!);
    final predicted = regressorMatrix.multiply(coeffs);
    final actual = data
        .column(outputCol)
        .subMatrix(model.maxDelay, data.rows, 0, 1);

    var meanY = 0.0;
    for (var i = 0; i < n; i++) {
      meanY += actual.get(i, 0);
    }
    meanY /= n;

    var ssRes = 0.0;
    var ssTot = 0.0;
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
    final regressorMatrix = RegressorBuilder.buildMatrix(model, data);
    if (regressorMatrix == null || model.coefficients == null) {
      return Matrix(0, 0);
    }

    final coeffs = Matrix.columnVector(model.coefficients!);
    final predicted = regressorMatrix.multiply(coeffs);
    final actual = data
        .column(outputCol)
        .subMatrix(model.maxDelay, data.rows, 0, 1);

    return actual - predicted;
  }
}
