import 'dart:math' as math;

import 'matrix.dart';

/// QR decomposition and orthogonalization routines for ERR calculation.
class Decomposition {
  Decomposition._();

  /// Modified Gram-Schmidt orthogonalization.
  ///
  /// Given matrix A (n×m), returns (Q, R) where Q is orthogonal and R upper-triangular.
  /// Used for ERR-based regressor ordering.
  static (Matrix q, Matrix r) modifiedGramSchmidt(Matrix a) {
    final n = a.rows;
    final m = a.cols;
    final q = a.clone();
    final r = Matrix(m, m);

    for (var j = 0; j < m; j++) {
      // r(j,j) = ||q(:,j)||
      var norm = 0.0;
      final jOff = j * n;
      for (var i = 0; i < n; i++) {
        norm += q.data[jOff + i] * q.data[jOff + i];
      }
      norm = math.sqrt(norm);
      r.set(j, j, norm);

      if (norm < 1e-14) continue;

      final invNorm = 1.0 / norm;
      for (var i = 0; i < n; i++) {
        q.data[jOff + i] *= invNorm;
      }

      // Orthogonalize remaining columns
      for (var k = j + 1; k < m; k++) {
        var dot = 0.0;
        final kOff = k * n;
        for (var i = 0; i < n; i++) {
          dot += q.data[jOff + i] * q.data[kOff + i];
        }
        r.set(j, k, dot);
        for (var i = 0; i < n; i++) {
          q.data[kOff + i] -= dot * q.data[jOff + i];
        }
      }
    }
    return (q, r);
  }

  /// Householder QR decomposition.
  ///
  /// More numerically stable than modified Gram-Schmidt.
  /// Returns (Q, R).
  static (Matrix q, Matrix r) householder(Matrix a) {
    final m = a.rows;
    final n = a.cols;
    final q = Matrix.identity(m);
    final r = a.clone();

    final k = math.min(m, n);
    for (var j = 0; j < k; j++) {
      // Compute Householder vector
      var norm = 0.0;
      final jOff = j * m;
      for (var i = j; i < m; i++) {
        norm += r.data[jOff + i] * r.data[jOff + i];
      }
      norm = math.sqrt(norm);

      if (norm < 1e-14) continue;

      if (r.data[jOff + j] > 0) norm = -norm;

      // v = r(j:m, j), v[0] -= norm
      final v = List<double>.filled(m - j, 0.0);
      for (var i = 0; i < v.length; i++) {
        v[i] = r.data[jOff + j + i];
      }
      v[0] -= norm;

      // Normalize v
      var vNorm = 0.0;
      for (var i = 0; i < v.length; i++) {
        vNorm += v[i] * v[i];
      }
      if (vNorm < 1e-28) continue;
      final invVNorm = 1.0 / vNorm;

      // Apply H = I - 2*v*v'/||v||^2 to R
      for (var c = j; c < n; c++) {
        var dot = 0.0;
        final cOff = c * m;
        for (var i = 0; i < v.length; i++) {
          dot += v[i] * r.data[cOff + j + i];
        }
        dot *= 2.0 * invVNorm;
        for (var i = 0; i < v.length; i++) {
          r.data[cOff + j + i] -= dot * v[i];
        }
      }

      // Apply H to Q
      for (var c = 0; c < m; c++) {
        var dot = 0.0;
        final cOff = c * m;
        for (var i = 0; i < v.length; i++) {
          dot += v[i] * q.data[cOff + j + i];
        }
        dot *= 2.0 * invVNorm;
        for (var i = 0; i < v.length; i++) {
          q.data[cOff + j + i] -= dot * v[i];
        }
      }
    }
    // Q was built transposed, so transpose it
    return (q.transpose(), r);
  }

  /// Solves an upper-triangular system R * x = b via back substitution.
  static Matrix backSubstitute(Matrix r, Matrix b) {
    assert(r.rows == r.cols && r.rows == b.rows && b.cols == 1);
    final n = r.rows;
    final x = Matrix(n, 1);
    for (var i = n - 1; i >= 0; i--) {
      var sum = b.get(i, 0);
      for (var j = i + 1; j < n; j++) {
        sum -= r.get(i, j) * x.get(j, 0);
      }
      final rii = r.get(i, i);
      x.set(i, 0, rii.abs() < 1e-14 ? 0.0 : sum / rii);
    }
    return x;
  }
}
