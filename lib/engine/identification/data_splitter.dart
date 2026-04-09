import '../../core/math/matrix.dart';

/// Splits data into training/validation/test sets.
///
/// Missing from the original C++ code — adds proper model validation.
class DataSplitter {
  DataSplitter._();

  /// Splits data sequentially (no shuffling, preserves time-series order).
  static DataSplit split(
    Matrix data, {
    double trainRatio = 0.7,
    double validationRatio = 0.15,
    double testRatio = 0.15,
  }) {
    final n = data.rows;
    final trainEnd = (n * trainRatio).floor();
    final valEnd = trainEnd + (n * validationRatio).floor();

    return DataSplit(
      training: data.subMatrix(0, trainEnd, 0, data.cols),
      validation: validationRatio > 0
          ? data.subMatrix(trainEnd, valEnd, 0, data.cols)
          : null,
      test: testRatio > 0 ? data.subMatrix(valEnd, n, 0, data.cols) : null,
      trainSize: trainEnd,
      validationSize: valEnd - trainEnd,
      testSize: n - valEnd,
    );
  }
}

class DataSplit {
  final Matrix training;
  final Matrix? validation;
  final Matrix? test;
  final int trainSize;
  final int validationSize;
  final int testSize;

  const DataSplit({
    required this.training,
    this.validation,
    this.test,
    required this.trainSize,
    required this.validationSize,
    required this.testSize,
  });
}
