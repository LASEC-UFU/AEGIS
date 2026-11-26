// P6 summary (experiments/p6/P6_PREREG.md §5): per benchmark and cell, the
// V_B ratio refined/original and the pre-registered criterion on the cell
// mr39_zero_simulation. Reads experiments/results_p6/<b>.jsonl (validation only).
import 'dart:convert';
import 'dart:io';

double med(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}
String f(double x, [int d = 3]) => x.isNaN ? '—' : x.toStringAsFixed(d);

void main() {
  const benches = ['cascaded_tanks', 'wiener_hammerstein', 'silverbox'];
  const cells = ['mr39_zero_simulation', 'mr39_zero_one_step', 'mr8_zero_simulation', 'mr8_zero_one_step',
      'mr39_default_simulation', 'mr39_default_one_step', 'mr8_default_simulation', 'mr8_default_one_step'];
  final out = StringBuffer('# P6: summary (validation only)\n\n'
      'r = RMSE_V_B(refined) / RMSE_V_B(original), free-run, original units. '
      'Iterate chosen on V_A among admissible LM iterates (0 = no change).\n');
  var met = 0;
  for (final b in benches) {
    final file = File('experiments/results_p6/$b.jsonl');
    if (!file.existsSync()) continue;
    final rows = file.readAsLinesSync().where((l) => l.isNotEmpty).map((l) => jsonDecode(l) as Map).toList();
    out.writeln('\n## $b\n');
    out.writeln('| cell | models | used | skipped | median r | r<0.95 | r>1.10 | iterate 0 | median V_B orig → ref | median s |');
    out.writeln('|---|---|---|---|---|---|---|---|---|---|');
    for (final c in cells) {
      final rs = rows.where((r) => r['cell'] == c).toList();
      final used = rs.where((r) => r['ratioVB'] is num).toList();
      final ratios = used.map((r) => (r['ratioVB'] as num).toDouble()).toList();
      final vbo = used.map((r) => (r['original']['vB'] as num).toDouble()).toList();
      final vbr = used.map((r) => (r['refined']['vB'] as num).toDouble()).toList();
      final secs = used.map((r) => (r['lm']['seconds'] as num).toDouble()).toList();
      final it0 = used.where((r) => r['chosenIterate'] == 0).length;
      final m = med(ratios);
      final hi = ratios.where((x) => x > 1.10).length;
      out.writeln('| $c | ${rs.length} | ${used.length} | ${rs.length - used.length} | ${f(m)} | '
          '${ratios.where((x) => x < 0.95).length} | $hi | $it0 | ${f(med(vbo), 5)} → ${f(med(vbr), 5)} | ${f(med(secs), 2)} |');
      if (c == 'mr39_zero_simulation') {
        final ok = m <= 0.95 && hi <= 2;
        if (ok) met++;
        out.writeln('\n**Criterion cell:** median r = ${f(m)}, models with r > 1.10 = $hi → ${ok ? 'met' : 'not met'}\n');
        out.writeln('| cell | models | used | skipped | median r | r<0.95 | r>1.10 | iterate 0 | median V_B orig → ref | median s |');
        out.writeln('|---|---|---|---|---|---|---|---|---|---|');
      }
    }
  }
  out.writeln('\n## Pre-registered result\n\nCriterion met in $met of 3 benchmarks (needs ≥ 2): '
      '${met >= 2 ? 'MET' : 'NOT MET'}.');
  File('experiments/results_p6/SUMMARY_P6.md').writeAsStringSync(out.toString());
  stdout.write(out);
}
