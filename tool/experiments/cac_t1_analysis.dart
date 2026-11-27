// CAC training T1 analysis (docs/architecture/15_PLANO_TREINO_CAC.md §3, §7).
// Validation only. For every arm@g and seed, the effect is the log ratio of
// the champion's validation free-run RMSE (normalized, history freeRunValFull)
// between the branch and the seed's control:
//   end of search (primary), g+25/50/100/200, and the final reported
//   validation after post-processing (secondary).
// The placebo arms give the chaos noise band.
//   dart run tool/experiments/cac_t1_analysis.dart [results_dir] > experiments/cac/T1_RESULTS.md
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class Run {
  final Map<int, double> fr = {};
  final Map<int, int> k = {};
  late double end, endK, finalVal;
  Map<String, dynamic>? decision;
  bool accepted = true;
}

Run? load(String dir, int seed) {
  final f = File('$dir/run_$seed.json');
  if (!f.existsSync()) return null;
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final r = Run();
  for (final h in j['history'] as List) {
    final g = h['g'] as int;
    final v = h['freeRunValFull'];
    if (v is num) r.fr[g] = v.toDouble();
    if (h['nReg'] is num) r.k[g] = (h['nReg'] as num).toInt();
  }
  final last = (j['history'] as List).last;
  r.end = (last['freeRunValFull'] as num?)?.toDouble() ?? double.nan;
  r.endK = (last['nReg'] as num?)?.toDouble() ?? double.nan;
  r.finalVal = (j['report']?['metrics']?['validation']?['rmseFreeRun'] as num?)?.toDouble() ?? double.nan;
  final dec = File('$dir/decisions_$seed.jsonl');
  if (dec.existsSync()) {
    for (final l in dec.readAsLinesSync()) {
      final d = jsonDecode(l) as Map<String, dynamic>;
      if (d['schema'] == 'aegis.decision/1') r.decision = d;
      if (d['schema'] == 'aegis.action_result/1' && d['accepted'] != true) r.accepted = false;
    }
  }
  return r;
}

double at(Run r, int g) {
  // value at the last recorded generation <= g
  double v = double.nan;
  for (final e in r.fr.entries) {
    if (e.key <= g) v = e.value;
  }
  return v;
}

double median(List<double> v) {
  final s = v.where((x) => x.isFinite).toList()..sort();
  if (s.isEmpty) return double.nan;
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

double quantile(List<double> v, double q) {
  final s = v.where((x) => x.isFinite).toList()..sort();
  if (s.isEmpty) return double.nan;
  return s[((s.length - 1) * q).round()];
}

/// Two-sided exact sign test p-value.
double signTest(List<double> d) {
  final x = d.where((v) => v.isFinite && v != 0).toList();
  final n = x.length;
  if (n == 0) return 1.0;
  final neg = x.where((v) => v < 0).length;
  final k = math.min(neg, n - neg);
  double c(int n, int k) { var r = 1.0; for (var i = 1; i <= k; i++) { r = r * (n - k + i) / i; } return r; }
  var p = 0.0;
  for (var i = 0; i <= k; i++) { p += c(n, i); }
  return math.min(1.0, 2 * p / math.pow(2, n));
}

String f(double x, [int d = 3]) => x.isFinite ? x.toStringAsFixed(d) : '—';

void main(List<String> args) {
  final root = args.isNotEmpty ? args[0] : 'experiments/results_cac/t1';
  final seeds = Directory('$root/control').listSync().whereType<File>()
      .map((f) => RegExp(r'run_(\d+)\.json$').firstMatch(f.path)).whereType<RegExpMatch>()
      .map((m) => int.parse(m[1]!)).toList()..sort();
  final ctrl = {for (final s in seeds) s: load('$root/control', s)};
  final arms = Directory(root).listSync().whereType<Directory>()
      .map((d) => d.path.split(Platform.pathSeparator).last.split('/').last)
      .where((n) => n.contains('@')).toList()..sort();
  const lags = [25, 50, 100, 200];
  final rows = <String, Map<String, dynamic>>{};
  final placebo = <double>[];
  for (final a in arms) {
    final g = int.parse(a.split('@').last);
    final dEnd = <double>[], dFinal = <double>[], dK = <double>[];
    final dLag = {for (final l in lags) l: <double>[]};
    var n = 0, rejected = 0;
    for (final s in seeds) {
      final c = ctrl[s], r = load('$root/$a', s);
      if (c == null || r == null) continue;
      n++;
      if (!r.accepted) rejected++;
      dEnd.add(math.log(r.end / c.end));
      dFinal.add(math.log(r.finalVal / c.finalVal));
      dK.add(r.endK - c.endK);
      for (final l in lags) {
        dLag[l]!.add(math.log(at(r, g + l) / at(c, g + l)));
      }
    }
    if (a.startsWith('PLACEBO')) placebo.addAll(dEnd);
    rows[a] = {'g': g, 'n': n, 'rejected': rejected, 'dEnd': dEnd, 'dFinal': dFinal, 'dK': dK, 'dLag': dLag};
  }
  final lo = quantile(placebo, 0.05), hi = quantile(placebo, 0.95);
  final bench = root.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).last;
  final out = StringBuffer('# CAC: mapa de impacto ($bench, validação)\n\n'
      'Efeito = log(RMSE ramo / RMSE controle) do campeão; negativo = melhor. Medida principal: fim da busca.\n\n'
      '**Faixa de ruído (placebos, fim da busca):** p5 = ${f(lo)}, p95 = ${f(hi)}, mediana |d| = ${f(median(placebo.map((x) => x.abs()).toList()))}, n = ${placebo.length}.\n\n'
      '| braço@g | n | rejeitadas | mediana d fim | melhores | sign p | fora da faixa placebo (melhor/pior) | '
      'd +25 | d +50 | d +100 | d +200 | mediana d final pós-proc. | mediana ΔK fim |\n'
      '|---|---|---|---|---|---|---|---|---|---|---|---|---|\n');
  for (final e in rows.entries) {
    final v = e.value;
    final dEnd = (v['dEnd'] as List<double>);
    final better = dEnd.where((x) => x < 0).length;
    final outB = dEnd.where((x) => x < lo).length, outW = dEnd.where((x) => x > hi).length;
    final dl = v['dLag'] as Map<int, List<double>>;
    out.writeln('| ${e.key} | ${v['n']} | ${v['rejected']} | ${f(median(dEnd))} | $better | ${f(signTest(dEnd))} | '
        '$outB / $outW | ${lags.map((l) => f(median(dl[l]!))).join(' | ')} | ${f(median(v['dFinal'] as List<double>))} | '
        '${f(median(v['dK'] as List<double>), 1)} |');
  }
  stdout.write(out);
}
