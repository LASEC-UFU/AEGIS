import 'dart:typed_data';

import '../../core/math/matrix.dart';

/// Data normalization using direct arithmetic (no string conversion).
///
/// Fixes the original catastrophic performance bug where normalization
/// went through QString("%1").arg(...).toDouble().
class DataNormalizer {
  DataNormalizer._();

  /// Normalizes data to [lowerBound, upperBound] per column.
  ///
  /// Returns the normalized matrix and the min/max values used.
  static NormalizationResult normalize(
    Matrix data, {
    double lowerBound = 0.01,
    double upperBound = 1.0,
  }) {
    final rows = data.rows;
    final cols = data.cols;
    final normalized = Matrix(rows, cols);
    final minValues = Float64List(cols);
    final maxValues = Float64List(cols);

    final range = upperBound - lowerBound;

    for (var c = 0; c < cols; c++) {
      // Find min and max for this column
      var min = double.infinity;
      var max = double.negativeInfinity;
      final off = c * rows;
      for (var r = 0; r < rows; r++) {
        final v = data.data[off + r];
        if (v < min) min = v;
        if (v > max) max = v;
      }

      minValues[c] = min;
      maxValues[c] = max;

      final span = max - min;
      final nOff = c * rows;

      if (span < 1e-30) {
        // Constant column — set to midpoint
        final mid = (lowerBound + upperBound) / 2;
        for (var r = 0; r < rows; r++) {
          normalized.data[nOff + r] = mid;
        }
      } else {
        final invSpan = 1.0 / span;
        for (var r = 0; r < rows; r++) {
          final v = data.data[off + r];
          normalized.data[nOff + r] = (range * (v - min) * invSpan + lowerBound)
              .clamp(lowerBound, upperBound);
        }
      }
    }

    return NormalizationResult(
      data: normalized,
      minValues: minValues,
      maxValues: maxValues,
      lowerBound: lowerBound,
      upperBound: upperBound,
    );
  }

  /// Denormalizes a value from normalized space back to original.
  static double denormalize(
    double normalized,
    double min,
    double max, {
    double lowerBound = 0.01,
    double upperBound = 1.0,
  }) {
    final range = upperBound - lowerBound;
    if (range < 1e-30) return min;
    return (normalized - lowerBound) / range * (max - min) + min;
  }
}

class NormalizationResult {
  final Matrix data;
  final Float64List minValues;
  final Float64List maxValues;
  final double lowerBound;
  final double upperBound;

  const NormalizationResult({
    required this.data,
    required this.minValues,
    required this.maxValues,
    required this.lowerBound,
    required this.upperBound,
  });
}
