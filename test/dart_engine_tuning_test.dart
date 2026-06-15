import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/core/math/matrix.dart';
import 'package:aegis/engine/de/de_engine.dart';

void main() {
  test('Dart fallback applies live agent tuning to the running components', () {
    const rows = 30;
    final values = List<double>.generate(rows * 2, (index) {
      final row = index ~/ 2;
      return index.isEven ? row / rows : (row * row) / (rows * rows);
    });
    final engine = DEEngine(numIslands: 1);
    engine.initialize(
      normalizedData: Matrix.fromRowMajor(rows, 2, values),
      outputCol: 1,
      numVariables: 2,
    );

    engine.applyTuning('mutationFactor', 0.8, reason: 'test');
    engine.applyTuning('migrationRate', 0.2, reason: 'test');

    expect(engine.islands.single.config.mutationFactor, closeTo(0.8, 1e-12));
    expect(engine.migration.rate, closeTo(0.2, 1e-12));
    expect(engine.history.tuningActions, hasLength(2));
  });
}
