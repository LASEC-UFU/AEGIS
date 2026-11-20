import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/experiments/analyze.dart' as analysis;

void main() {
  test('alternate evaluation keeps seed and divergence without primary fallback', () {
    final root = Directory.systemTemp.createTempSync('aegis_analysis_');
    addTearDown(() => root.deleteSync(recursive: true));
    final condition = Directory('${root.path}/aegis_full')..createSync();
    File('${condition.path}/evaluations.jsonl').writeAsStringSync('{}');
    expect(analysis.loadCondition(condition, evaluations: 'arrow.jsonl'), isEmpty);
    Map<String, dynamic> row(String kind) => {
      'input': '${root.path}/missing.json',
      'seed': 12,
      'kind': kind,
      'result': {
        'numParameters': 4,
        'metrics': {
          'test': {'rmseFreeRunOrig': 2.5, 'freeRunDiverged': true},
        },
      },
    };
    final alternate = File('${condition.path}/arrow.jsonl');
    alternate.writeAsStringSync(
      '${jsonEncode(row('frols_valsim'))}\n${jsonEncode(row('frols_bic'))}\n',
    );
    final runs = analysis.loadCondition(condition, evaluations: 'arrow.jsonl');
    expect(runs, hasLength(1));
    expect(runs.single.seed, 12);
    expect(runs.single.m['testFR'], 2.5);
    expect(runs.single.diverged, isTrue);
    alternate.writeAsStringSync('${jsonEncode(row('aegis'))}\n', mode: FileMode.append);
    expect(() => analysis.loadCondition(condition, evaluations: 'arrow.jsonl'),
        throwsFormatException);
  });
}
