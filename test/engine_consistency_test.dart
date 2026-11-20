// Cross-engine consistency: for the same polynomial chromosome and the same
// (already normalized) data, the Dart fallback engine and the C++ core must
// produce the same least-squares coefficients and one-step error.
// Requires the native core; set AEGIS_CORE_DLL or build cpp/build/aegis_core.dll.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/core/math/matrix.dart';
import 'package:aegis/core/math/power_basis.dart';
import 'package:aegis/core/types/types.dart';
import 'package:aegis/engine/de/regressor_builder.dart';
import 'package:aegis/engine/fitness/least_squares.dart';
import 'package:aegis/ffi/aegis_library_native.dart';

void main() {
  test('power basis matches the C++ hybrid basis', () {
    expect(powerBasis(-2.0, 2.0), 4.0);
    expect(powerBasis(-2.0, 3.0), -8.0);
    expect(powerBasis(-4.0, 0.5), -2.0);
    expect(powerBasis(0.0, 1.5), 0.0);
  });

  final dllPath = Platform.environment['AEGIS_CORE_DLL'] ?? 'cpp/build/aegis_core.dll';
  final haveDll = File(dllPath).existsSync() && AegisLibrary.tryLoad(path: File(dllPath).absolute.path);

  test('Dart and C++ least squares agree on the same chromosome', () {
    const n = 600, train = 480;
    final rng = math.Random(7);
    final raw = List.generate(n, (_) => [0.0, 0.0]);
    var y1 = 0.0, y2 = 0.0, u1 = 0.0, u2 = 0.0;
    for (var k = 0; k < n; k++) {
      final u = math.sin(0.03 * k) + 0.4 * (rng.nextDouble() - 0.5);
      final y = 0.6 * y1 - 0.15 * y2 + 0.5 * u1 + 0.2 * u2 * u2 + 0.02 * (rng.nextDouble() - 0.5);
      raw[k] = [u, y];
      y2 = y1; y1 = y; u2 = u1; u1 = u;
    }
    // Pre-normalize with the training min/max so the core's min-max
    // normalization is (numerically) the identity.
    for (var c = 0; c < 2; c++) {
      var lo = double.infinity, hi = -double.infinity;
      for (var k = 0; k < train; k++) {
        lo = math.min(lo, raw[k][c]);
        hi = math.max(hi, raw[k][c]);
      }
      for (var k = 0; k < n; k++) {
        raw[k][c] = -1 + 2 * (raw[k][c] - lo) / (hi - lo);
      }
    }
    final m = Matrix(train, 2);
    for (var k = 0; k < train; k++) {
      m.set(k, 0, raw[k][0]);
      m.set(k, 1, raw[k][1]);
    }
    final chrom = Chromosome(regressors: [
      Regressor([CompoundTerm(term: const Term(variable: 1, delay: 1), exponent: 1)]),
      Regressor([CompoundTerm(term: const Term(variable: 1, delay: 2), exponent: 1)]),
      Regressor([CompoundTerm(term: const Term(variable: 0, delay: 1), exponent: 1)]),
      Regressor([CompoundTerm(term: const Term(variable: 0, delay: 2), exponent: 2)]),
    ], outputIndex: 1, maxDelay: 2);
    final psi = RegressorBuilder.buildMatrix(chrom, m)!;
    final out = m.column(1).subMatrix(2, train, 0, 1);
    final dart = LeastSquaresFit.fit(psi, out);

    final lib = AegisLibrary.instance!;
    final p = lib.createPipeline();
    final buf = calloc<Double>(n * 2);
    for (var k = 0; k < n; k++) {
      buf[2 * k] = raw[k][0];
      buf[2 * k + 1] = raw[k][1];
    }
    lib.loadData(p, buf, n, 2);
    calloc.free(buf);
    final cfg = '{"trainEndRow":$train,"valEndRow":540,"maxDelay":2,"powerMode":"hybrid"}'.toNativeUtf8();
    lib.configure(p, cfg);
    calloc.free(cfg);
    final model = jsonEncode({
      'powerMode': 'hybrid',
      'regressors': [
        {'terms': [{'variable': 1, 'delay': 1, 'exponent': 1}]},
        {'terms': [{'variable': 1, 'delay': 2, 'exponent': 1}]},
        {'terms': [{'variable': 0, 'delay': 1, 'exponent': 1}]},
        {'terms': [{'variable': 0, 'delay': 2, 'exponent': 2}]},
      ],
    });
    final res = jsonDecode(lib.callStringArg(p, (pp, a) => lib.evaluateModel!(pp, a, 1), model))
        as Map<String, dynamic>;
    lib.destroyPipeline(p);
    final cpp = ((res['model'] as Map)['coefficients'] as List).cast<num>();
    for (var i = 0; i < 4; i++) {
      expect(dart.coefficients[i], closeTo(cpp[i].toDouble(), 1e-8));
    }
    expect(dart.intercept, closeTo(((res['model'] as Map)['intercept'] as num).toDouble(), 1e-8));
    final trainRmseCpp = (((res['metrics'] as Map)['train'] as Map)['rmseOneStep'] as num).toDouble();
    final trainRmseDart = math.sqrt(dart.sse / psi.rows);
    expect(trainRmseDart, closeTo(trainRmseCpp, 1e-6));
  }, skip: haveDll ? false : 'native core not available ($dllPath)');
}
