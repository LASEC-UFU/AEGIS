import 'dart:typed_data';

import 'matrix.dart';

/// Immutable view into a [Matrix] sub-region.
///
/// Unlike the original C++ JMathVar that mutated view params on the source
/// object (causing thread-safety bugs), this is a **separate, immutable
/// proxy** that holds its own range parameters and a read-only reference
/// to the source data.
///
/// All arithmetic operations on MatrixView produce a new [Matrix].
class MatrixView {
  final Matrix source;
  final int rowStart;
  final int rowEnd;
  final int rowStep;
  final int colStart;
  final int colEnd;
  final int colStep;
  final bool transpose;

  const MatrixView({
    required this.source,
    required this.rowStart,
    required this.rowEnd,
    this.rowStep = 1,
    required this.colStart,
    required this.colEnd,
    this.colStep = 1,
    this.transpose = false,
  });

  int get viewRows {
    final raw = ((rowEnd - rowStart) + rowStep - 1) ~/ rowStep;
    return transpose ? _viewCols : raw;
  }

  int get _viewCols {
    return ((colEnd - colStart) + colStep - 1) ~/ colStep;
  }

  int get viewCols =>
      transpose ? ((rowEnd - rowStart) + rowStep - 1) ~/ rowStep : _viewCols;

  /// Read a single element from the view.
  double get(int row, int col) {
    final int r, c;
    if (transpose) {
      r = rowStart + col * rowStep;
      c = colStart + row * colStep;
    } else {
      r = rowStart + row * rowStep;
      c = colStart + col * colStep;
    }
    return source.get(r, c);
  }

  /// Materializes this view into a new [Matrix].
  Matrix toMatrix() {
    final nr = viewRows;
    final nc = viewCols;
    final d = Float64List(nr * nc);
    for (var c = 0; c < nc; c++) {
      for (var r = 0; r < nr; r++) {
        d[c * nr + r] = get(r, c);
      }
    }
    return Matrix.fromColumnMajor(nr, nc, d);
  }

  /// Convenience multiplication: materializes then multiplies.
  Matrix multiply(Matrix other) => toMatrix().multiply(other);

  /// Convenience: element-wise multiply with scalar.
  Matrix operator *(double scalar) => toMatrix() * scalar;

  /// Convenience: add.
  Matrix operator +(MatrixView other) => toMatrix() + other.toMatrix();

  /// Convenience: subtract.
  Matrix operator -(MatrixView other) => toMatrix() - other.toMatrix();
}
