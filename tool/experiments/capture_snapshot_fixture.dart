// Captures a real aegis.snapshot/2 JSON from the C++ core for parser tests.
//   dart run tool/experiments/capture_snapshot_fixture.dart cpp/build/aegis_core.dll test/fixtures/snapshot_v2.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:aegis/core/math/matrix.dart';
import 'package:aegis/ffi/aegis_ffi_service_native.dart';
import 'package:aegis/ffi/aegis_library_native.dart';

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

void main(List<String> args) {
  if (!AegisLibrary.tryLoad(path: File(args[0]).absolute.path)) exit(1);
  final svc = AegisFfiService(AegisLibrary.instance!);
  const n = 400;
  final m = Matrix(n, 2);
  var y1 = 0.0, u1 = 0.0;
  final rng = math.Random(3);
  for (var k = 0; k < n; k++) {
    final u = math.sin(0.05 * k) + 0.3 * (rng.nextDouble() - 0.5);
    final y = 0.7 * y1 + 0.4 * _tanh(u1);
    m.set(k, 0, u);
    m.set(k, 1, y);
    y1 = y;
    u1 = u;
  }
  svc.initialize(
    normalizedData: m,
    outputCol: 1,
    numVariables: 2,
    configJson: '{"numIslands":2,"populationSize":10,"maxDelay":5,"maxGenerations":12,'
        '"syncMode":true,"randomSeed":5,"webSocketPort":0,"numThreads":1}',
  );
  svc.start();
  svc.step(10);
  File(args[1]).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(svc.rawSnapshot()));
  svc.dispose();
}
