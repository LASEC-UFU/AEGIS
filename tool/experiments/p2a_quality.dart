// P2'a quality (experiments/perf/P2A_PREREG.md §3): fitMethod=normal runs vs
// the E3 runs of cell mr39_zero_simulation, seeds 21-30. Validation only.
import 'dart:convert';
import 'dart:io';

double med(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

Map<String, dynamic> load(String dir) {
  final v = <double>[], w = <double>[], k = <double>[];
  var div = 0, n = 0;
  for (final f in Directory(dir).listSync().whereType<File>().where((f) => RegExp(r'run_\d+\.json$').hasMatch(f.path))) {
    final j = jsonDecode(f.readAsStringSync());
    final rep = j['report'];
    if (rep['metrics'].containsKey('test')) { stderr.writeln('unexpected test segment'); exit(3); }
    final val = rep['metrics']['validation'];
    v.add((val['rmseFreeRunOrig'] as num).toDouble());
    if (val['freeRunDiverged'] == true) div++;
    w.add((j['wallSeconds'] ?? rep['wallSeconds'] as num).toDouble());
    k.add((rep['numParameters'] as num).toDouble());
    n++;
  }
  return {'n': n, 'med': med(v), 'div': div, 'wall': med(w), 'k': med(k)};
}

void main() {
  var ok = true;
  print('| benchmark | runs P2′a / E3 | median val RMSE P2′a / E3 | ratio | divergences P2′a / E3 | median K | median wall s P2′a / E3 | speed-up |');
  print('|---|---|---|---|---|---|---|---|');
  for (final b in ['cascaded_tanks', 'wiener_hammerstein', 'silverbox']) {
    final p = load('experiments/results_perf/p2a_quality/$b');
    final e = load('experiments/results_phase0/$b/e3/mr39_zero_simulation');
    final r = p['med'] / e['med'];
    final eq = r >= 0.90 && r <= 1.10 && p['div'] <= e['div'] + 1;
    ok = ok && eq && p['n'] == 10;
    print('| $b | ${p['n']} / ${e['n']} | ${p['med'].toStringAsPrecision(4)} / ${e['med'].toStringAsPrecision(4)} | '
        '${r.toStringAsFixed(3)} ${eq ? '✓' : '✗'} | ${p['div']} / ${e['div']} | ${p['k']} / ${e['k']} | '
        '${p['wall'].toStringAsFixed(0)} / ${e['wall'].toStringAsFixed(0)} | ${(e['wall'] / p['wall']).toStringAsFixed(1)}× |');
  }
  print('\nEquivalence criterion (all benchmarks, 10 runs each): ${ok ? 'MET' : 'NOT MET'}');
}
