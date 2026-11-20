// Phase 0, E3 summary: per cell (maxRegressors x penalties x errorMode) the
// validation free-run RMSE of the ten seeds, and the pre-registered screening
// comparison (zeroed penalties + cap 39 vs default + cap 8, same errorMode).
// E3 runs have no test segment (no test file, explicit split).
//
//   dart run tool/experiments/phase0_e3_summary.dart [results_phase0 dir]
import 'dart:convert';
import 'dart:io';

double _median(List<double> xs) {
  final s = [...xs]..sort();
  if (s.isEmpty) return double.nan;
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : 0.5 * (s[n ~/ 2 - 1] + s[n ~/ 2]);
}

double _q(List<double> xs, double p) {
  final s = [...xs]..sort();
  if (s.isEmpty) return double.nan;
  final pos = p * (s.length - 1);
  final lo = pos.floor(), hi = pos.ceil();
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

String _f(double v, [int d = 4]) => v.isNaN ? '—' : v.toStringAsFixed(d);

void main(List<String> args) {
  final root = args.isNotEmpty ? args[0] : 'experiments/results_phase0';
  final out = StringBuffer('# Phase 0: E3 screening (configuration only, binary 1.1.0)\n\n'
      'Validation free-run RMSE (original units), seeds 21–30. No test segment exists in these runs.\n\n');
  final met = <String, Map<String, bool>>{};
  for (final bench in ['cascaded_tanks', 'wiener_hammerstein', 'silverbox']) {
    final dir = Directory('$root/$bench/e3');
    if (!dir.existsSync()) {
      out.writeln('## $bench\n\nNot run yet.\n');
      continue;
    }
    final medians = <String, double>{};
    out.writeln('## $bench\n');
    out.writeln('| cell | runs | median | IQR | diverged (val) | median K | median evals | median wall s |');
    out.writeln('|---|---|---|---|---|---|---|---|');
    final cells = dir.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final c in cells) {
      final name = c.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final v = <double>[], k = <double>[], ev = <double>[], wall = <double>[];
      var div = 0;
      for (final f in c.listSync().whereType<File>().where((f) => RegExp(r'run_\d+\.json$').hasMatch(f.path))) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final rep = j['report'] as Map<String, dynamic>? ?? {};
        final metrics = rep['metrics'] as Map<String, dynamic>? ?? {};
        if (metrics.containsKey('test')) {
          stderr.writeln('unexpected test segment in ${f.path}; aborting');
          exit(3);
        }
        final val = metrics['validation'] as Map<String, dynamic>? ?? {};
        final r = val['rmseFreeRunOrig'];
        if (r is num) v.add(r.toDouble());
        if (val['freeRunDiverged'] == true) div++;
        final np = rep['numParameters'];
        if (np is num) k.add(np.toDouble());
        final e = rep['evaluations'];
        if (e is num) ev.add(e.toDouble());
        final w = j['wallSeconds'];
        if (w is num) wall.add(w.toDouble());
      }
      medians[name] = _median(v);
      out.writeln('| $name | ${v.length} | ${_f(_median(v))} | [${_f(_q(v, 0.25))}, ${_f(_q(v, 0.75))}] | $div | '
          '${_f(_median(k), 0)} | ${_f(_median(ev), 0)} | ${_f(_median(wall), 0)} |');
    }
    met[bench] = {};
    for (final em in ['one_step', 'simulation']) {
      final a = medians['mr39_zero_$em'], b = medians['mr8_default_$em'];
      final ok = a != null && b != null && !a.isNaN && !b.isNaN && a <= 0.90 * b;
      met[bench]![em] = ok;
      out.writeln('\n- $em: zero+39 / default+8 = ${a == null || b == null ? '—' : _f(a / b, 3)} → '
          '${ok ? 'criterion met' : 'not met'}');
    }
    out.writeln();
  }
  out.writeln('## Screening result\n');
  for (final em in ['one_step', 'simulation']) {
    final n = met.values.where((m) => m[em] == true).length;
    out.writeln('- $em: criterion met in $n of ${met.length} benchmarks run'
        '${met.length < 3 ? ' (incomplete)' : n >= 2 ? ' → decompose parsimony pressure' : ' → no screening support'}.');
  }
  out.writeln('\nThe two errorModes are reported separately; the pre-registration does not combine them.');
  File('$root/SUMMARY_E3.md').writeAsStringSync(out.toString());
  stdout.write(out.toString());
}
