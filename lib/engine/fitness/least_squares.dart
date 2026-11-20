import '../../core/math/decomposition.dart';
import '../../core/math/matrix.dart';

/// Least-squares fit with an intercept column, as in the C++ core:
///   y ≈ Ψ·θ + c
/// Returns the regressor coefficients, the intercept, predictions and SSE.
class LeastSquaresFit {
  final List<double> coefficients;
  final double intercept;
  final Matrix predicted;
  final double sse;

  const LeastSquaresFit(this.coefficients, this.intercept, this.predicted, this.sse);

  static LeastSquaresFit fit(Matrix regressors, Matrix output) {
    final n = regressors.rows;
    final k = regressors.cols;
    final aug = Matrix(n, k + 1);
    for (var j = 0; j < k; j++) {
      for (var i = 0; i < n; i++) {
        aug.set(i, j, regressors.get(i, j));
      }
    }
    for (var i = 0; i < n; i++) {
      aug.set(i, k, 1.0);
    }
    final (q, r) = Decomposition.modifiedGramSchmidt(aug);
    final qtY = q.transpose().multiply(output);
    final theta = Decomposition.backSubstitute(
      r.subMatrix(0, k + 1, 0, k + 1),
      qtY.subMatrix(0, k + 1, 0, 1),
    );
    final predicted = aug.multiply(theta);
    final residuals = output - predicted;
    return LeastSquaresFit(
      List<double>.generate(k, (i) => theta.get(i, 0)),
      theta.get(k, 0),
      predicted,
      residuals.sumOfSquares(),
    );
  }
}
