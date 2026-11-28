// CAC T8 analysis (docs/architecture/16_REGULADORES_COMPLETOS.md §9), frozen
// before the runs. Validation only. Paired by seed, per system:
//   primary   : final reported validation RMSE after post-processing
//               (report.metrics.validation.rmseFreeRun);
//   secondary : champion validation free-run RMSE at the end of the search.
// Effect d = log(arm / none). Comparisons: cac5 vs none (criterion) and, on
// WH/SB, STATIC_pop25 vs none (reference: the v5 dose from the start).
//   dart run tool/experiments/cac_t8_analysis.dart > experiments/cac/T8_RESULTS.md
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

({double end, double fin, int actions, int k})? load(String path) {
  final f = File(path);
  if (!f.existsSync() || f.lengthSync() == 0) return null;
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final last = (j['history'] as List).last as Map<String, dynamic>;
  return (
    end: (last['freeRunValFull'] as num).toDouble(),
    fin: (j['report']?['metrics']?['validation']?['rmseFreeRun'] as num?)?.toDouble() ?? double.nan,
    actions: (j['agent']?['actionsAccepted'] as num?)?.toInt() ?? 0,
    k: (last['nReg'] as num?)?.toInt() ?? -1,
  );
}

double median(List<double> v) {
  final s = v.where((x) => x.isFinite).toList()..sort();
  if (s.isEmpty) return double.nan;
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

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
  final root = args.isNotEmpty ? args[0] : 'experiments/results_cac/t8';
  final out = StringBuffer('# CAC T8: CAC v5 (mapa medido do conjunto completo) contra o pacote A1 (validação)\n\n'
      'd = log(RMSE agente / RMSE referência), pareado por semente; negativo = melhor. '
      'Principal: validação final reportada. Secundária: campeão no fim da busca.\n\n');
  out.writeln('| sistema | comparação | n | mediana d fim | melhores / piores | sign p | mediana d final | melhores / piores (final) | ações aceitas (mediana) |');
  out.writeln('|---|---|---|---|---|---|---|---|---|');
  for (final b in ['cascaded_tanks', 'wiener_hammerstein', 'silverbox']) {
    final dir = Directory('$root/$b/none');
    if (!dir.existsSync()) continue;
    final seeds = dir.listSync().whereType<File>()
        .map((x) => RegExp(r'run_(\d+)\.json$').firstMatch(x.path)).whereType<RegExpMatch>()
        .map((m) => int.parse(m[1]!)).toList()..sort();
    for (final (a, ref) in [('cac5', 'none'), ('STATIC_pop25', 'none')]) {
      final dEnd = <double>[], dFin = <double>[], acts = <double>[];
      for (final s in seeds) {
        final x = load('$root/$b/$a/run_$s.json'), r = load('$root/$b/$ref/run_$s.json');
        if (x == null || r == null) continue;
        dEnd.add(math.log(x.end / r.end));
        dFin.add(math.log(x.fin / r.fin));
        acts.add(x.actions.toDouble());
      }
      String bw(List<double> d) => '${d.where((v) => v < 0).length} / ${d.where((v) => v > 0).length}';
      out.writeln('| $b | $a vs $ref | ${dEnd.length} | ${f(median(dEnd))} | ${bw(dEnd)} | ${f(signTest(dEnd))} | '
          '${f(median(dFin))} | ${bw(dFin)} | ${f(median(acts), 0)} |');
    }
  }
  stdout.write(out);
}
