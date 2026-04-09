import 'dart:typed_data';
import '../core/math/matrix.dart';

/// Loads data from CSV/TSV text content.
class DataLoader {
  DataLoader._();

  /// Parse CSV text into a Matrix.
  ///
  /// [content]: raw text of the file.
  /// [separator]: column separator (auto-detected if null).
  /// [hasHeader]: whether the first line is a header.
  /// [skipRows]: number of initial rows to skip (after header).
  static DataLoadResult parse(
    String content, {
    String? separator,
    bool hasHeader = false,
    int skipRows = 0,
    List<int>? selectedColumns,
  }) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return DataLoadResult(
        data: Matrix(0, 0),
        headers: [],
        numRows: 0,
        numCols: 0,
      );
    }

    // Auto-detect separator
    final sep = separator ?? _detectSeparator(lines.first);

    // Parse header
    List<String> headers = [];
    var dataStart = 0;
    if (hasHeader) {
      headers = lines[0].split(sep).map((s) => s.trim()).toList();
      dataStart = 1;
    }
    dataStart += skipRows;

    if (dataStart >= lines.length) {
      return DataLoadResult(
        data: Matrix(0, 0),
        headers: headers,
        numRows: 0,
        numCols: 0,
      );
    }

    // Parse data lines
    final dataLines = lines.sublist(dataStart);
    final numRows = dataLines.length;
    final allCols = dataLines[0].split(sep).length;
    final cols = selectedColumns ?? List.generate(allCols, (i) => i);
    final numCols = cols.length;

    if (headers.isEmpty) {
      headers = List.generate(numCols, (i) => 'Var ${cols[i]}');
    } else if (selectedColumns != null) {
      headers = selectedColumns
          .map((i) => i < headers.length ? headers[i] : 'Var $i')
          .toList();
    }

    // Column-major storage
    final data = Float64List(numRows * numCols);
    for (var r = 0; r < numRows; r++) {
      final parts = dataLines[r].split(sep);
      for (var c = 0; c < numCols; c++) {
        final colIdx = cols[c];
        if (colIdx < parts.length) {
          data[c * numRows + r] = double.tryParse(parts[colIdx].trim()) ?? 0.0;
        }
      }
    }

    return DataLoadResult(
      data: Matrix.fromColumnMajor(numRows, numCols, data),
      headers: headers,
      numRows: numRows,
      numCols: numCols,
    );
  }

  static String _detectSeparator(String line) {
    if (line.contains('\t')) return '\t';
    if (line.contains(';')) return ';';
    if (line.contains(',')) return ',';
    return RegExp(r'\s+').pattern;
  }
}

class DataLoadResult {
  final Matrix data;
  final List<String> headers;
  final int numRows;
  final int numCols;

  const DataLoadResult({
    required this.data,
    required this.headers,
    required this.numRows,
    required this.numCols,
  });
}
