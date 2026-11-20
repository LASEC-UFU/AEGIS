import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/core/math/matrix.dart';
import 'package:aegis/engine/de/migration.dart';
import 'package:aegis/engine/identification/data_normalizer.dart';

void main() {
  test(
    'Dart fallback normalization is fitted on training rows and never clips held-out values',
    () {
      final data = Matrix.fromRowMajor(4, 1, [-2, 0, 2, 100]);
      final result = DataNormalizer.normalize(data, fitRows: 3);

      expect(result.data.get(0, 0), closeTo(-1, 1e-12));
      expect(result.data.get(1, 0), closeTo(0, 1e-12));
      expect(result.data.get(2, 0), closeTo(1, 1e-12));
      // 100 lies outside the training range [-2, 2]: mapped linearly (audit P0-3).
      expect(result.data.get(3, 0), closeTo(50, 1e-12));
    },
  );

  test('zero migration rate disables migration', () {
    final migration = Migration(rate: 0);
    expect(migration.shouldMigrate(20), isFalse);
  });
}
