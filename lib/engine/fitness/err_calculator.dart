import '../../core/math/matrix.dart';
import '../../core/math/decomposition.dart';
import '../../core/types/regressor.dart';

/// Error Reduction Ratio (ERR) calculator with correct pseudo-linearization
/// for rational NARX models (fix for the acknowledged bug in the original C++ code).
///
/// For polynomial models: standard Gram-Schmidt ERR.
/// For rational models: denominator regressors are multiplied by -y(k)
/// before orthogonalization (pseudo-linearization).
class ERRCalculator {
  const ERRCalculator();

  /// Computes ERR values for each regressor column in [regressorMatrix].
  ///
  /// Returns a list of ERR values (one per regressor), normalized so they
  /// sum to approximately the total variance explained.
  ///
  /// [output] is the target y(k) column vector.
  /// [regressors] provides metadata to identify denominator terms.
  List<double> computeERR(
    Matrix regressorMatrix,
    Matrix output,
    List<Regressor> regressors,
  ) {
    final n = regressorMatrix.rows;
    final m = regressorMatrix.cols;

    // Apply pseudo-linearization for rational models:
    // Denominator regressors φ_d(k) → -y(k) * φ_d(k)
    final psiMatrix = _applyPseudoLinearization(
      regressorMatrix,
      output,
      regressors,
    );

    // Modified Gram-Schmidt to compute orthogonal basis
    final (q, _) = Decomposition.modifiedGramSchmidt(psiMatrix);

    // Total output energy
    var yEnergy = 0.0;
    for (var i = 0; i < n; i++) {
      yEnergy += output.get(i, 0) * output.get(i, 0);
    }
    if (yEnergy < 1e-30) return List.filled(m, 0.0);

    // ERR for each orthogonalized column
    final errValues = List<double>.filled(m, 0.0);
    for (var j = 0; j < m; j++) {
      // g_j = <q_j, y> / <q_j, q_j>
      var qjY = 0.0;
      var qjQj = 0.0;
      final jOff = j * n;
      for (var i = 0; i < n; i++) {
        final qji = q.data[jOff + i];
        qjY += qji * output.get(i, 0);
        qjQj += qji * qji;
      }
      if (qjQj < 1e-30) continue;
      errValues[j] = (qjY * qjY) / (qjQj * yEnergy);
    }

    return errValues;
  }

  /// Applies pseudo-linearization for rational models.
  ///
  /// For denominador regressors: ψ_j(k) = -y(k) * φ_j(k)
  /// For numerator regressors: ψ_j(k) = φ_j(k) (unchanged)
  Matrix _applyPseudoLinearization(
    Matrix regressorMatrix,
    Matrix output,
    List<Regressor> regressors,
  ) {
    final n = regressorMatrix.rows;
    final m = regressorMatrix.cols;

    var hasRational = false;
    for (final r in regressors) {
      if (r.isDenominator) {
        hasRational = true;
        break;
      }
    }
    if (!hasRational) return regressorMatrix;

    final psi = regressorMatrix.clone();
    for (var j = 0; j < m && j < regressors.length; j++) {
      if (regressors[j].isDenominator) {
        final jOff = j * n;
        for (var i = 0; i < n; i++) {
          psi.data[jOff + i] =
              -output.get(i, 0) * regressorMatrix.data[jOff + i];
        }
      }
    }
    return psi;
  }

  /// Forward selection ERR ordering: greedily selects regressors
  /// by maximum ERR contribution.
  ///
  /// Returns the ordering (list of indices) sorted by ERR contribution.
  List<int> forwardSelectionOrder(
    Matrix regressorMatrix,
    Matrix output,
    List<Regressor> regressors,
  ) {
    final n = regressorMatrix.rows;
    final m = regressorMatrix.cols;

    final psiMatrix = _applyPseudoLinearization(
      regressorMatrix,
      output,
      regressors,
    );

    var yEnergy = 0.0;
    for (var i = 0; i < n; i++) {
      yEnergy += output.get(i, 0) * output.get(i, 0);
    }
    if (yEnergy < 1e-30) return List.generate(m, (i) => i);

    // Work with copies for in-place orthogonalization
    final w = psiMatrix.clone();
    final selected = <int>[];
    final remaining = List.generate(m, (i) => i);

    for (var step = 0; step < m; step++) {
      var bestErr = -1.0;
      var bestIdx = -1;
      var bestRemIdx = -1;

      for (var ri = 0; ri < remaining.length; ri++) {
        final j = remaining[ri];
        var wjY = 0.0;
        var wjWj = 0.0;
        final jOff = j * n;
        for (var i = 0; i < n; i++) {
          final wji = w.data[jOff + i];
          wjY += wji * output.get(i, 0);
          wjWj += wji * wji;
        }
        if (wjWj < 1e-30) continue;
        final err = (wjY * wjY) / (wjWj * yEnergy);
        if (err > bestErr) {
          bestErr = err;
          bestIdx = j;
          bestRemIdx = ri;
        }
      }

      if (bestIdx < 0) break;
      selected.add(bestIdx);
      remaining.removeAt(bestRemIdx);

      // Orthogonalize remaining columns against the selected one
      final sOff = bestIdx * n;
      var sNorm = 0.0;
      for (var i = 0; i < n; i++) {
        sNorm += w.data[sOff + i] * w.data[sOff + i];
      }
      if (sNorm < 1e-30) continue;

      for (final j in remaining) {
        var dot = 0.0;
        final jOff = j * n;
        for (var i = 0; i < n; i++) {
          dot += w.data[sOff + i] * w.data[jOff + i];
        }
        final scale = dot / sNorm;
        for (var i = 0; i < n; i++) {
          w.data[jOff + i] -= scale * w.data[sOff + i];
        }
      }
    }

    return selected;
  }
}
