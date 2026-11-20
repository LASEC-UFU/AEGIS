import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/agent/generation_history.dart';
import 'package:aegis/ffi/snapshot_parser.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/snapshot_v2.json').readAsStringSync())
      as Map<String, dynamic>;

  test('real core snapshot maps to GenerationSnapshot without placeholder values', () {
    final s = snapshotFromCoreJson(fixture, history: GenerationHistory(), elapsed: Duration.zero);
    expect(s.generation, 10);
    expect(s.evaluations, greaterThan(0));
    // The old FFI layer set meanFitness = bestFitness and islands = [].
    expect(s.meanFitness.isFinite, isTrue);
    expect(s.meanFitness, isNot(equals(s.bestFitness)));
    expect(s.islandStatuses, hasLength(2));
    expect(s.islandStatuses.first.populationSize, 10);
    expect(s.parameters['mutationFactor'], isNotNull);
    expect(s.effectiveWeights['gamma'], isNotNull);
    // ERR and residual ACF are separate fields (the ACF slot used to hold ERR).
    expect(s.bestModelERR.length, s.bestModelComplexity);
    expect(s.residualAutocorrelation, isNotNull);
    expect(s.residualAutocorrelation!.first, closeTo(1.0, 1e-12));
    expect(s.residualAcfBound, isNotNull);
  });

  test('observation never contains test-set information', () {
    final s = snapshotFromCoreJson(fixture, history: GenerationHistory(), elapsed: Duration.zero);
    final text = jsonEncode(s.toObservation());
    expect(text.toLowerCase().contains('test'), isFalse);
    expect(s.toObservation()['schema'], 'aegis.observation/1');
  });

  test('history receives one entry per distinct generation in the service', () {
    final h = GenerationHistory();
    final s = snapshotFromCoreJson(fixture, history: h, elapsed: Duration.zero);
    h.addSnapshot(s);
    final again = snapshotFromCoreJson(fixture, history: h, elapsed: Duration.zero);
    expect(again.improvementAbsolute, 0.0);
  });
}
