// A1 analysis (experiments/a1/A1_PREREG.md §4–§5). Run ONCE, after all A1
// runs are finished and the manifest is committed. Compares A1 with the
// 1.1.0 aegis_full runs, paired by seed, on the test free-run RMSE.
//
//   dart run tool/experiments/a1_analysis.dart > experiments/a1/A1_RESULTS.md
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const benches = ['wiener_hammerstein', 'silverbox', 'cascaded_tanks'];

Map<int, Map<String, dynamic>> load(String dir) {
  final out = <int, Map<String, dynamic>>{};
  final d = Directory(dir);
  if (!d.existsSync()) return out;
  for (final f in d.listSync().whereType<File>()) {
    final m = RegExp(r'run_(\d+)\.json$').firstMatch(f.path);
    if (m == null) continue;
    out[int.parse(m[1]!)] = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  }
  return out;
}

double testRmse(Map<String, dynamic> run) {
  final t = run['report']?['metrics']?['test'];
  if (t == null) return double.nan;
  if (t['freeRunDiverged'] == true) return double.infinity;
  final v = t['rmseFreeRunOrig'];
  return v is num ? v.toDouble() : double.nan;
}

double valRmse(Map<String, dynamic> run) {
  final v = run['report']?['metrics']?['validation']?['rmseFreeRunOrig'];
  return v is num ? v.toDouble() : double.nan;
}

double median(List<double> v) {
  final s = [...v]..sort();
  if (s.isEmpty) return double.nan;
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

/// Exact one-sided Wilcoxon signed-rank p-value for H1: differences < 0.
double wilcoxonLess(List<double> d) {
  final x = d.where((v) => v != 0 && !v.isNaN).toList();
  final n = x.length;
  if (n == 0) return 1.0;
  final idx = List.generate(n, (i) => i)..sort((a, b) => x[a].abs().compareTo(x[b].abs()));
  final ranks = List<double>.filled(n, 0);
  var i = 0;
  while (i < n) {
    var j = i;
    while (j + 1 < n && x[idx[j + 1]].abs() == x[idx[i]].abs()) j++;
    for (var k = i; k <= j; k++) ranks[idx[k]] = (i + j) / 2 + 1;
    i = j + 1;
  }
  var wPlus = 0.0;
  for (var k = 0; k < n; k++) if (x[k] > 0) wPlus += ranks[k];
  // P(W+ <= observed) under H0, by enumeration of the 2^n sign patterns.
  var count = 0;
  final total = 1 << n;
  for (var mask = 0; mask < total; mask++) {
    var w = 0.0;
    for (var k = 0; k < n; k++) if (mask & (1 << k) != 0) w += ranks[k];
    if (w <= wPlus + 1e-9) count++;
  }
  return count / total;
}

void main() {
  final out = StringBuffer('# A1: resultados (teste aberto uma vez)\n\n'
      'Gerado por `tool/experiments/a1_analysis.dart` (A1_PREREG.md §4–§5).\n\n');
  final pvals = <String, double>{}, ratios = <String, double>{};
  out.writeln('| benchmark | pares | mediana teste A1 | mediana teste 1.1.0 | razão | p (Wilcoxon, unilateral) | '
      'divergências teste A1 / 1.1.0 | mediana validação A1 / 1.1.0 | K mediano A1 / 1.1.0 | refino aplicado | wall mediano s A1 / 1.1.0 |');
  out.writeln('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final b in benches) {
    final a1 = load('experiments/results_a1/$b');
    final ref = load('experiments/results/$b/aegis_full');
    final seeds = a1.keys.where(ref.containsKey).toList()..sort();
    final ta = [for (final s in seeds) testRmse(a1[s]!)], tr = [for (final s in seeds) testRmse(ref[s]!)];
    final diffs = <double>[];
    for (var k = 0; k < seeds.length; k++) {
      final x = ta[k], y = tr[k];
      if (x.isInfinite && y.isInfinite) { diffs.add(0); continue; }
      if (x.isInfinite) { diffs.add(1e9); continue; }
      if (y.isInfinite) { diffs.add(-1e9); continue; }
      diffs.add(math.log(x) - math.log(y));
    }
    final ma = median(ta), mr = median(tr);
    final p = wilcoxonLess(diffs);
    pvals[b] = p;
    ratios[b] = ma / mr;
    double med(Iterable<double> v) => median(v.toList());
    final applied = seeds.where((s) => a1[s]!['report']?['postProcessing']?['simulationRefine']?['applied'] == true).length;
    out.writeln('| $b | ${seeds.length} | ${ma.toStringAsPrecision(4)} | ${mr.toStringAsPrecision(4)} | '
        '${(ma / mr).toStringAsFixed(3)} | ${p.toStringAsFixed(4)} | '
        '${ta.where((v) => v.isInfinite).length} / ${tr.where((v) => v.isInfinite).length} | '
        '${med(seeds.map((s) => valRmse(a1[s]!))).toStringAsPrecision(4)} / ${med(seeds.map((s) => valRmse(ref[s]!))).toStringAsPrecision(4)} | '
        '${med(seeds.map((s) => (a1[s]!['report']['numParameters'] as num).toDouble()))} / '
        '${med(seeds.map((s) => (ref[s]!['report']['numParameters'] as num).toDouble()))} | $applied/${seeds.length} | '
        '${med(seeds.map((s) => (a1[s]!['wallSeconds'] as num).toDouble())).toStringAsFixed(0)} / '
        '${med(seeds.map((s) => (ref[s]!['wallSeconds'] as num).toDouble())).toStringAsFixed(0)} |');
  }
  // Holm over the two primary comparisons (WH, SB).
  final prim = ['wiener_hammerstein', 'silverbox']..sort((a, b) => pvals[a]!.compareTo(pvals[b]!));
  final holm = <String, double>{};
  for (var k = 0; k < prim.length; k++) {
    holm[prim[k]] = math.min(1.0, pvals[prim[k]]! * (prim.length - k));
    if (k > 0) holm[prim[k]] = math.max(holm[prim[k]]!, holm[prim[k - 1]]!);
  }
  out.writeln('\n## Critério primário (WH e SB)\n');
  var met = true;
  for (final b in ['wiener_hammerstein', 'silverbox']) {
    final ok = ratios[b]! <= 0.90 && holm[b]! < 0.05;
    met = met && ok;
    out.writeln('- $b: razão ${ratios[b]!.toStringAsFixed(3)}, p Holm ${holm[b]!.toStringAsFixed(4)} → ${ok ? 'atingido' : 'não atingido'}');
  }
  out.writeln('\n**Gate primário: ${met ? 'ATINGIDO' : 'NÃO ATINGIDO'}.**');
  stdout.write(out);
}
