import 'dart:math' as math;
import 'dart:typed_data';

import 'matrix_view.dart';

/// Column-major dense matrix backed by Float64List for WASM performance.
///
/// All data is stored contiguously in column-major order:
///   element(row, col) = _data[col * _rows + row]
///
/// This class is the owner of the data buffer. For sub-matrix access
/// without mutation, use [MatrixView] via [view].
class Matrix {
  final int _rows;
  final int _cols;
  final Float64List _data;

  Matrix(this._rows, this._cols) : _data = Float64List(_rows * _cols);

  Matrix._(this._rows, this._cols, this._data);

  /// Creates a matrix from a flat list in row-major order (user-friendly).
  factory Matrix.fromRowMajor(int rows, int cols, List<double> data) {
    assert(data.length == rows * cols);
    final d = Float64List(rows * cols);
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        d[c * rows + r] = data[r * cols + c];
      }
    }
    return Matrix._(rows, cols, d);
  }

  /// Creates a matrix from column-major Float64List (zero-copy when possible).
  factory Matrix.fromColumnMajor(int rows, int cols, Float64List data) {
    assert(data.length == rows * cols);
    return Matrix._(rows, cols, data);
  }

  /// Creates an identity matrix.
  factory Matrix.identity(int size) {
    final m = Matrix(size, size);
    for (var i = 0; i < size; i++) {
      m.set(i, i, 1.0);
    }
    return m;
  }

  /// Creates a matrix filled with a single value.
  factory Matrix.filled(int rows, int cols, double value) {
    final d = Float64List(rows * cols);
    for (var i = 0; i < d.length; i++) {
      d[i] = value;
    }
    return Matrix._(rows, cols, d);
  }

  /// Creates a column vector from a list.
  factory Matrix.columnVector(List<double> values) {
    return Matrix.fromColumnMajor(
      values.length,
      1,
      Float64List.fromList(values),
    );
  }

  /// Creates a row vector from a list.
  factory Matrix.rowVector(List<double> values) {
    return Matrix.fromColumnMajor(
      1,
      values.length,
      Float64List.fromList(values),
    );
  }

  /// Deep copy.
  Matrix clone() => Matrix._(rows, cols, Float64List.fromList(_data));

  int get rows => _rows;
  int get cols => _cols;
  int get length => _data.length;
  Float64List get data => _data;

  // ─── Element access ─────────────────────────────────────────

  double get(int row, int col) => _data[col * _rows + row];

  void set(int row, int col, double value) {
    _data[col * _rows + row] = value;
  }

  double operator [](int index) => _data[index];
  void operator []=(int index, double value) => _data[index] = value;

  // ─── View (immutable sub-matrix proxy) ──────────────────────

  /// Returns an immutable view of a sub-matrix.
  /// All parameters are inclusive ranges: [rowStart..rowEnd], [colStart..colEnd].
  MatrixView view({
    int rowStart = 0,
    int? rowEnd,
    int rowStep = 1,
    int colStart = 0,
    int? colEnd,
    int colStep = 1,
    bool transpose = false,
  }) {
    return MatrixView(
      source: this,
      rowStart: rowStart,
      rowEnd: rowEnd ?? _rows,
      rowStep: rowStep,
      colStart: colStart,
      colEnd: colEnd ?? _cols,
      colStep: colStep,
      transpose: transpose,
    );
  }

  /// Returns a full view (all rows/cols, no transpose).
  MatrixView get fullView => view();

  // ─── Column / Row extraction ────────────────────────────────

  /// Extracts column [col] as a new column-vector Matrix.
  Matrix column(int col) {
    final d = Float64List(_rows);
    final offset = col * _rows;
    for (var r = 0; r < _rows; r++) {
      d[r] = _data[offset + r];
    }
    return Matrix._(_rows, 1, d);
  }

  /// Extracts row [row] as a new row-vector Matrix.
  Matrix row(int row) {
    final d = Float64List(_cols);
    for (var c = 0; c < _cols; c++) {
      d[c] = _data[c * _rows + row];
    }
    return Matrix._(1, _cols, d);
  }

  /// Sets column [col] from a list of values.
  void setColumn(int col, List<double> values) {
    assert(values.length == _rows);
    final offset = col * _rows;
    for (var r = 0; r < _rows; r++) {
      _data[offset + r] = values[r];
    }
  }

  /// Sets column [col] from another single-column matrix.
  void setColumnFromMatrix(int col, Matrix src, {int srcCol = 0}) {
    assert(src.rows == _rows);
    final dstOff = col * _rows;
    final srcOff = srcCol * src._rows;
    for (var r = 0; r < _rows; r++) {
      _data[dstOff + r] = src._data[srcOff + r];
    }
  }

  // ─── Arithmetic ─────────────────────────────────────────────

  /// Matrix multiplication: this * other.
  Matrix multiply(Matrix other) {
    assert(
      _cols == other._rows,
      'Incompatible dimensions: $_rows×$_cols * ${other._rows}×${other._cols}',
    );
    final result = Matrix(_rows, other._cols);
    for (var j = 0; j < other._cols; j++) {
      for (var k = 0; k < _cols; k++) {
        final bkj = other._data[j * other._rows + k];
        if (bkj == 0.0) continue;
        final aOff = k * _rows;
        final rOff = j * _rows;
        for (var i = 0; i < _rows; i++) {
          result._data[rOff + i] += _data[aOff + i] * bkj;
        }
      }
    }
    return result;
  }

  /// Element-wise multiplication (Hadamard product).
  Matrix hadamard(Matrix other) {
    assert(_rows == other._rows && _cols == other._cols);
    final d = Float64List(length);
    for (var i = 0; i < length; i++) {
      d[i] = _data[i] * other._data[i];
    }
    return Matrix._(_rows, _cols, d);
  }

  /// Element-wise addition.
  Matrix operator +(Matrix other) {
    assert(_rows == other._rows && _cols == other._cols);
    final d = Float64List(length);
    for (var i = 0; i < length; i++) {
      d[i] = _data[i] + other._data[i];
    }
    return Matrix._(_rows, _cols, d);
  }

  /// Element-wise subtraction.
  Matrix operator -(Matrix other) {
    assert(_rows == other._rows && _cols == other._cols);
    final d = Float64List(length);
    for (var i = 0; i < length; i++) {
      d[i] = _data[i] - other._data[i];
    }
    return Matrix._(_rows, _cols, d);
  }

  /// Scalar multiplication.
  Matrix operator *(double scalar) {
    final d = Float64List(length);
    for (var i = 0; i < length; i++) {
      d[i] = _data[i] * scalar;
    }
    return Matrix._(_rows, _cols, d);
  }

  /// Scalar negation.
  Matrix operator -() {
    return this * -1.0;
  }

  /// Transpose (creates new matrix).
  Matrix transpose() {
    final d = Float64List(length);
    for (var c = 0; c < _cols; c++) {
      for (var r = 0; r < _rows; r++) {
        d[r * _cols + c] = _data[c * _rows + r];
      }
    }
    return Matrix._(_cols, _rows, d);
  }

  /// Element-wise power.
  Matrix pow(double exponent) {
    final d = Float64List(length);
    for (var i = 0; i < length; i++) {
      d[i] = math.pow(_data[i], exponent).toDouble();
    }
    return Matrix._(_rows, _cols, d);
  }

  // ─── Reductions ─────────────────────────────────────────────

  /// Sum of all elements.
  double sum() {
    var s = 0.0;
    for (var i = 0; i < length; i++) {
      s += _data[i];
    }
    return s;
  }

  /// Sum of squares of all elements.
  double sumOfSquares() {
    var s = 0.0;
    for (var i = 0; i < length; i++) {
      s += _data[i] * _data[i];
    }
    return s;
  }

  /// Mean of all elements.
  double mean() => sum() / length;

  /// Variance of all elements.
  double variance() {
    final m = mean();
    var s = 0.0;
    for (var i = 0; i < length; i++) {
      final d = _data[i] - m;
      s += d * d;
    }
    return s / length;
  }

  /// Dot product (for column vectors).
  double dot(Matrix other) {
    assert((_cols == 1 && other._cols == 1) && _rows == other._rows);
    var s = 0.0;
    for (var i = 0; i < _rows; i++) {
      s += _data[i] * other._data[i];
    }
    return s;
  }

  /// Euclidean norm (for vectors).
  double norm() => math.sqrt(sumOfSquares());

  /// Column-wise sum, returns a row vector.
  Matrix columnSums() {
    final d = Float64List(_cols);
    for (var c = 0; c < _cols; c++) {
      var s = 0.0;
      final off = c * _rows;
      for (var r = 0; r < _rows; r++) {
        s += _data[off + r];
      }
      d[c] = s;
    }
    return Matrix._(1, _cols, d);
  }

  // ─── In-place operations (performance hot paths) ────────────

  /// Adds [scalar] * column [srcCol] of [src] to column [dstCol] of this.
  void addScaledColumn(int dstCol, Matrix src, int srcCol, double scalar) {
    final dOff = dstCol * _rows;
    final sOff = srcCol * src._rows;
    for (var r = 0; r < _rows; r++) {
      _data[dOff + r] += scalar * src._data[sOff + r];
    }
  }

  /// Scales column [col] by [scalar] in-place.
  void scaleColumn(int col, double scalar) {
    final off = col * _rows;
    for (var r = 0; r < _rows; r++) {
      _data[off + r] *= scalar;
    }
  }

  // ─── Utility ────────────────────────────────────────────────

  /// Returns a sub-matrix (copies data).
  Matrix subMatrix(int rowStart, int rowEnd, int colStart, int colEnd) {
    final nr = rowEnd - rowStart;
    final nc = colEnd - colStart;
    final d = Float64List(nr * nc);
    for (var c = 0; c < nc; c++) {
      final srcOff = (colStart + c) * _rows + rowStart;
      final dstOff = c * nr;
      for (var r = 0; r < nr; r++) {
        d[dstOff + r] = _data[srcOff + r];
      }
    }
    return Matrix._(nr, nc, d);
  }

  /// Autocorrelation of a column vector for lags 0..maxLag.
  List<double> autocorrelation(int maxLag) {
    assert(_cols == 1);
    final m = mean();
    var denom = 0.0;
    for (var i = 0; i < _rows; i++) {
      final d = _data[i] - m;
      denom += d * d;
    }
    if (denom == 0.0) return List.filled(maxLag + 1, 0.0);

    final result = List<double>.filled(maxLag + 1, 0.0);
    result[0] = 1.0;
    for (var lag = 1; lag <= maxLag; lag++) {
      var num = 0.0;
      for (var i = 0; i < _rows - lag; i++) {
        num += (_data[i] - m) * (_data[i + lag] - m);
      }
      result[lag] = num / denom;
    }
    return result;
  }

  @override
  String toString() {
    final sb = StringBuffer('Matrix(${_rows}x$_cols):\n');
    for (var r = 0; r < _rows && r < 10; r++) {
      sb.write('  [');
      for (var c = 0; c < _cols && c < 10; c++) {
        if (c > 0) sb.write(', ');
        sb.write(get(r, c).toStringAsFixed(6));
      }
      if (_cols > 10) sb.write(', ...');
      sb.writeln(']');
    }
    if (_rows > 10) sb.writeln('  ...');
    return sb.toString();
  }
}
