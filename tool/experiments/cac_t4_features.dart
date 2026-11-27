// CAC T4 (docs/architecture/15_PLANO_TREINO_CAC.md §3, T4): which in-run
// signal, observable by the controller at decision time, predicts whether
// raising a complexity weight (β, δ, γ) helps or hurts? Validation only.
//
// For every weight branch (arm@g, seed) of T1/T2/T3 it reads, from the
// CONTROL run of the same seed at generation g (identical to the branch up to
// g, deterministic branching):
//   gapOS  = log(rmseVal / rmseTrain)  one-step, champion
//   gapFR  = log(freeRunValFull / rmseTrain)
//   spp    = trainRows / nReg          samples per regressor
//   nReg
// and the branch effect d = log(end RMSE branch / end RMSE control).
// For each feature it reports, pooled over systems, the best single
// threshold rule "raise only if feature on the helpful side of t" and its
// leave-one-system-out accuracy (threshold chosen on two systems, tested on
// the third), so a rule that only separates systems by accident shows up.
//   dart run tool/experiments/cac_t4_features.dart > experiments/cac/T4_FEATURES.md
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class Hist {
  final Map<int, Map<String, dynamic>> byG = {};
  late double end;
  late int trainRows;
  Map<String, dynamic>? at(int g) {
    Map<String, dynamic>? v;
    for (final e in byG.entries) {
      if (e.key <= g) v = e.value;
    }
    return v;
  }
}

Hist? load(String path) {
  final f = File(path);
  if (!f.existsSync() || f.lengthSync() == 0) return null;
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final h = Hist();
  for (final e in j['history'] as List) {
    h.byG[e['g'] as int] = e as Map<String, dynamic>;
  }
  h.end = ((j['history'] as List).last['freeRunValFull'] as num).toDouble();
  h.trainRows = (j['report']['config']['trainEndRow'] as num).toInt();
  return h;
}

class Row {
  final String system, arm;
  final int g, seed;
  final double d;
  final Map<String, double> feat;
  Row(this.system, this.arm, this.g, this.seed, this.d, this.feat);
}

const features = ['gapOS', 'gapFR', 'spp', 'nReg'];

double num_(dynamic v) => v is num ? v.toDouble() : double.nan;

String f3(double x) => x.isFinite ? x.toStringAsFixed(3) : '—';

void main(List<String> args) {
  final sets = {
    'cascaded_tanks(T1)': 'experiments/results_cac/t1',
    'cascaded_tanks': 'experiments/results_cac/t2/cascaded_tanks',
    'wiener_hammerstein': 'experiments/results_cac/t2/wiener_hammerstein',
    'silverbox': 'experiments/results_cac/t2/silverbox',
  };
  final rows = <Row>[];
  final ctrlFeat = <String, List<Map<String, double>>>{};
  for (final e in sets.entries) {
    final root = e.value;
    final arms = Directory(root).listSync().whereType<Directory>()
        .map((d) => d.path.replaceAll('\\', '/').split('/').last)
        .where((n) => RegExp(r'^(beta|delta|gamma)\+').hasMatch(n)).toList()..sort();
    final ctrls = <int, Hist>{};
    for (final f in Directory('$root/control').listSync().whereType<File>()) {
      final m = RegExp(r'run_(\d+)\.json$').firstMatch(f.path);
      if (m == null) continue;
      final h = load(f.path);
      if (h != null) ctrls[int.parse(m[1]!)] = h;
    }
    Map<String, double> feat(Hist c, int g) {
      final s = c.at(g)!;
      final tr = num_(s['rmseTrain']), va = num_(s['rmseVal']), fr = num_(s['freeRunValFull']);
      final k = num_(s['nReg']);
      return {'gapOS': math.log(va / tr), 'gapFR': math.log(fr / tr), 'spp': c.trainRows / k, 'nReg': k};
    }
    final sys = e.key.replaceAll('(T1)', '');
    for (final a in arms) {
      final g = int.parse(a.split('@').last);
      for (final s in ctrls.keys) {
        final b = load('$root/$a/run_$s.json');
        if (b == null) continue;
        final c = ctrls[s]!;
        rows.add(Row(sys, a.split('@').first, g, s, math.log(b.end / c.end), feat(c, g)));
      }
    }
    for (final c in ctrls.values) {
      for (final g in c.byG.keys.where((g) => g % 25 == 0)) {
        ctrlFeat.putIfAbsent(sys, () => []).add(feat(c, g));
      }
    }
  }

  final out = StringBuffer('# CAC T4: sinal de sobreajuste para os pesos β, δ, γ (validação)\n\n'
      'Ramos de peso (β, δ, γ ↑) do T1 e do T2/T3: ${rows.length}. Rótulo: ajuda se d < 0 '
      '(log RMSE fim ramo / controle). Atributos lidos no controle da mesma semente na geração da ação.\n\n');

  out.writeln('## Distribuição dos atributos nos controles (a cada 25 gerações)\n');
  out.writeln('| sistema | n | ${features.map((f) => '$f p10 / p50 / p90').join(' | ')} |');
  out.writeln('|---|---|${features.map((_) => '---').join('|')}|');
  for (final e in ctrlFeat.entries) {
    String q(String f) {
      final v = e.value.map((m) => m[f]!).where((x) => x.isFinite).toList()..sort();
      double p(double t) => v[((v.length - 1) * t).round()];
      return '${f3(p(0.1))} / ${f3(p(0.5))} / ${f3(p(0.9))}';
    }
    out.writeln('| ${e.key} | ${e.value.length} | ${features.map(q).join(' | ')} |');
  }

  out.writeln('\n## Efeito por sistema\n');
  out.writeln('| sistema | ramos | ajuda (d<0) | mediana d |');
  out.writeln('|---|---|---|---|');
  for (final s in rows.map((r) => r.system).toSet()) {
    final d = rows.where((r) => r.system == s).map((r) => r.d).toList()..sort();
    out.writeln('| $s | ${d.length} | ${d.where((x) => x < 0).length} | ${f3(d[d.length ~/ 2])} |');
  }

  // Best threshold rule per feature: raise iff (dir * feature) > dir * t.
  // Score = mean of −d over the branches where the rule says "raise"
  // (expected log gain), i.e. what the controller would have earned.
  ({double t, int dir, double gain, int n}) fit(List<Row> rs, String f) {
    var best = (t: double.nan, dir: 1, gain: 0.0, n: 0);
    final vals = rs.map((r) => r.feat[f]!).where((x) => x.isFinite).toSet().toList()..sort();
    for (final t in vals) {
      for (final dir in const [1, -1]) {
        final sel = rs.where((r) => dir * r.feat[f]! >= dir * t).toList();
        if (sel.length < 5) continue;
        final gain = sel.fold(0.0, (a, r) => a - r.d);
        if (gain > best.gain) best = (t: t, dir: dir, gain: gain, n: sel.length);
      }
    }
    return best;
  }

  out.writeln('\n## Regra de limiar por atributo ("subir só se atributo ≥ t" ou "≤ t")\n');
  out.writeln('Ganho = soma de −d nos ramos em que a regra autoriza subir (o que o controlador teria ganho; '
      'nunca subir = 0). Validação cruzada deixando um sistema de fora: limiar escolhido em dois sistemas, '
      'aplicado no terceiro.\n');
  out.writeln('| atributo | regra (todos) | ramos autorizados | ganho total | ganho fora: CT | WH | SB | autorizados fora CT / WH / SB |');
  out.writeln('|---|---|---|---|---|---|---|---|');
  final systems = ['cascaded_tanks', 'wiener_hammerstein', 'silverbox'];
  for (final f in features) {
    final all = fit(rows, f);
    final outGain = <String>[], outN = <String>[];
    for (final s in systems) {
      final tr = rows.where((r) => r.system != s).toList();
      final te = rows.where((r) => r.system == s).toList();
      final m = fit(tr, f);
      if (!m.t.isFinite) { outGain.add('—'); outN.add('—'); continue; }
      final sel = te.where((r) => m.dir * r.feat[f]! >= m.dir * m.t).toList();
      outGain.add(f3(sel.fold(0.0, (a, r) => a - r.d)));
      outN.add('${sel.length}/${te.length}');
    }
    out.writeln('| $f | ${all.dir > 0 ? '≥' : '≤'} ${f3(all.t)} | ${all.n}/${rows.length} | ${f3(all.gain)} | '
        '${outGain.join(' | ')} | ${outN.join(' / ')} |');
  }
  // Within CT: does the gap still order the effect (tercile of gapOS), per weight?
  out.writeln('\n## Dentro do CT: efeito por tercil de gapOS e por peso\n');
  out.writeln('| peso | tercil gapOS (faixa) | ramos | ajuda | mediana d |');
  out.writeln('|---|---|---|---|---|');
  final ct = rows.where((r) => r.system == 'cascaded_tanks').toList();
  final gs = ct.map((r) => r.feat['gapOS']!).toList()..sort();
  final c1 = gs[gs.length ~/ 3], c2 = gs[2 * gs.length ~/ 3];
  for (final w in ['beta', 'delta', 'gamma']) {
    for (final (lo, hi) in [(-1e9, c1), (c1, c2), (c2, 1e9)]) {
      final d = ct.where((r) => r.arm.startsWith(w) && r.feat['gapOS']! >= lo && r.feat['gapOS']! < hi)
          .map((r) => r.d).toList()..sort();
      if (d.isEmpty) continue;
      out.writeln('| $w | ${f3(math.max(lo, gs.first))}–${f3(math.min(hi, gs.last))} | ${d.length} | '
          '${d.where((x) => x < 0).length} | ${f3(d[d.length ~/ 2])} |');
    }
  }
  stdout.write(out);
}
