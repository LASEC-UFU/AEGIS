// Statistical analysis of AEGIS experiment results (pure Dart, no deps).
//
//   dart run tool/experiments/analyze.dart --results experiments/results/<benchmark>
//        [--reference aegis_full] [--out <dir>] [--title "Cascaded Tanks"]
//        [--evaluations evaluations_arrow.jsonl --out <separate-dir>]
//
// Every sub-directory of --results is a condition. Supported layouts:
//   <cond>/run_<seed>.json         aegis_batch / agent runner records
//   legacy_head/evaluations.jsonl  original code (9e4b1d8) re-evaluated
//   frols/selected.json            FROLS baseline (deterministic, n = 1)
// Outputs: SUMMARY.md, runs.csv, stats.json, boxplot_test_freerun.svg,
// convergence.svg. The primary metric is the free-run (simulation) RMSE on
// the test set in the original output units, with the benchmark's
// initialisation window excluded. Test data are never used for selection.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class Run {
  final String condition;
  final int seed;
  final Map<String, double> m = {};
  bool diverged = false;
  List<(double, double)> curve = const []; // (evaluations, validation free-run RMSE)
  Map<String, dynamic> agent = const {};
  Run(this.condition, this.seed);
}

const metrics = <String, (String, bool)>{
  // key: (label, lowerIsBetter)
  'testFR': ('Test free-run RMSE (orig. units)', true),
  'testOS': ('Test one-step RMSE (orig. units)', true),
  'testFit': ('Test free-run FIT (%)', false),
  'valFR': ('Validation free-run RMSE (orig. units)', true),
  'trainFR': ('Train free-run RMSE (orig. units)', true),
  'nParams': ('Number of parameters', true),
  'evals': ('Objective evaluations', true),
  'gens': ('Generations', true),
  'wall': ('Wall time (s)', true),
};

double? _d(dynamic v) => v is num && v.isFinite ? v.toDouble() : null;

void _segments(Run r, Map<String, dynamic>? metricsMap) {
  if (metricsMap == null) return;
  final te = metricsMap['test'] as Map<String, dynamic>?;
  final va = metricsMap['validation'] as Map<String, dynamic>?;
  final tr = metricsMap['train'] as Map<String, dynamic>?;
  void put(String k, double? v) {
    if (v != null) r.m[k] = v;
  }

  put('testFR', _d(te?['rmseFreeRunOrig']));
  put('testOS', _d(te?['rmseOneStepOrig']));
  put('testFit', _d(te?['fitFreeRun']));
  put('valFR', _d(va?['rmseFreeRunOrig']));
  put('trainFR', _d(tr?['rmseFreeRunOrig']));
  r.diverged = (te?['freeRunDiverged'] as bool?) ?? false;
}

List<Run> loadCondition(Directory dir, {String? evaluations}) {
  final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
  final runs = <Run>[];
  final evalFile = File('${dir.path}/${evaluations ?? 'evaluations.jsonl'}');
  if (evaluations != null && !evalFile.existsSync()) return runs;
  if (evalFile.existsSync()) {
    // Re-evaluated frozen models; exclude the alternative BIC-selected FROLS
    // model so each condition has exactly one record per seed.
    for (final line in evalFile.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, dynamic>;
      if (j['kind'] == 'frols_bic') continue;
      final input = j['input'] as String;
      final seedMatch = RegExp(r'run_(\d+)\.json').firstMatch(input);
      final r = Run(name, (j['seed'] as num?)?.toInt() ?? int.parse(seedMatch?.group(1) ?? '0'));
      final res = j['result'] as Map<String, dynamic>?;
      if (res == null || res.containsKey('error')) continue;
      _segments(r, res['metrics'] as Map<String, dynamic>?);
      r.m['nParams'] = ((res['numParameters'] as num?) ?? 0).toDouble();
      final runFile = File(input);
      if (runFile.existsSync()) {
        final rj = jsonDecode(runFile.readAsStringSync()) as Map<String, dynamic>;
        r.m['wall'] = _d(rj['wallSeconds']) ?? double.nan;
        final report = rj['report'] as Map?;
        r.m['gens'] = _d(report?['generations']) ??
            _d((rj['finalStatus'] as Map?)?['generation']) ?? double.nan;
        if (_d(report?['evaluations']) case final double n) r.m['evals'] = n;
        r.agent = (rj['agent'] as Map<String, dynamic>?) ?? const {};
      }
      if (runs.any((previous) => previous.seed == r.seed)) {
        throw FormatException('duplicate seed ${r.seed} in ${evalFile.path}');
      }
      runs.add(r);
    }
    return runs;
  }
  final selected = File('${dir.path}/selected.json');
  if (selected.existsSync()) {
    final j = jsonDecode(selected.readAsStringSync()) as Map<String, dynamic>;
    final res = j['result'] as Map<String, dynamic>;
    final r = Run(name, 0);
    _segments(r, res['metrics'] as Map<String, dynamic>?);
    r.m['nParams'] = ((res['numParameters'] as num?) ?? 0).toDouble();
    r.m['wall'] = _d(j['totalSeconds']) ?? double.nan;
    runs.add(r);
    return runs;
  }
  for (final f in dir.listSync().whereType<File>()) {
    final mt = RegExp(r'run_(\d+)\.json$').firstMatch(f.path);
    if (mt == null) continue;
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final rep = j['report'] as Map<String, dynamic>?;
    if (rep == null || rep['model'] == null) continue;
    final r = Run(name, int.parse(mt.group(1)!));
    _segments(r, rep['metrics'] as Map<String, dynamic>?);
    r.m['nParams'] = ((rep['numParameters'] as num?) ?? 0).toDouble();
    r.m['evals'] = ((rep['evaluations'] as num?) ?? 0).toDouble();
    r.m['gens'] = ((rep['generations'] as num?) ?? 0).toDouble();
    r.m['wall'] = _d(j['wallSeconds']) ?? double.nan;
    r.agent = (j['agent'] as Map<String, dynamic>?) ?? const {};
    final hist = (j['history'] as List?) ?? const [];
    r.curve = [
      for (final h in hist)
        if (h is Map && _d(h['evals']) != null && _d(h['freeRunValFull']) != null)
          (_d(h['evals'])!, _d(h['freeRunValFull'])!),
    ];
    runs.add(r);
  }
  runs.sort((a, b) => a.seed.compareTo(b.seed));
  return runs;
}

// ── Statistics ──────────────────────────────────────────────────────────────

double mean(List<double> x) => x.isEmpty ? double.nan : x.reduce((a, b) => a + b) / x.length;

double sd(List<double> x) {
  if (x.length < 2) return double.nan;
  final m = mean(x);
  return math.sqrt(x.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / (x.length - 1));
}

double quantile(List<double> x, double q) {
  if (x.isEmpty) return double.nan;
  final s = [...x]..sort();
  final h = (s.length - 1) * q;
  final lo = h.floor(), hi = h.ceil();
  return s[lo] + (s[hi] - s[lo]) * (h - lo);
}

/// Percentile bootstrap 95% CI of the mean (fixed RNG seed → reproducible).
(double, double) bootstrapCi(List<double> x, {int b = 10000, int seed = 12345}) {
  if (x.length < 2) return (double.nan, double.nan);
  final rng = math.Random(seed);
  final means = List<double>.generate(b, (_) {
    var s = 0.0;
    for (var i = 0; i < x.length; i++) {
      s += x[rng.nextInt(x.length)];
    }
    return s / x.length;
  })..sort();
  return (means[(0.025 * b).floor()], means[(0.975 * b).floor() - 1]);
}

/// Midranks of |values|, doubled so they are integers.
List<int> _doubledRanks(List<double> v) {
  final idx = List<int>.generate(v.length, (i) => i)..sort((a, b) => v[a].compareTo(v[b]));
  final ranks = List<int>.filled(v.length, 0);
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
      j++;
    }
    final r2 = (i + 1) + (j + 1); // 2 × average rank
    for (var k = i; k <= j; k++) {
      ranks[idx[k]] = r2;
    }
    i = j + 1;
  }
  return ranks;
}

/// Exact two-sided Wilcoxon signed-rank test (zero differences dropped).
(double, int) wilcoxon(List<double> diffs) {
  final d = diffs.where((x) => x != 0 && x.isFinite).toList();
  final n = d.length;
  if (n == 0) return (1.0, 0);
  final ranks = _doubledRanks(d.map((x) => x.abs()).toList());
  final total = ranks.reduce((a, b) => a + b);
  var wPlus = 0;
  for (var i = 0; i < n; i++) {
    if (d[i] > 0) wPlus += ranks[i];
  }
  // Distribution of the sum of a random subset of ranks (each sign ±).
  final counts = List<double>.filled(total + 1, 0)..[0] = 1;
  for (final r in ranks) {
    for (var s = total; s >= r; s--) {
      counts[s] += counts[s - r];
    }
  }
  final all = math.pow(2, n).toDouble();
  final wMin = math.min(wPlus, total - wPlus);
  var tail = 0.0;
  for (var s = 0; s <= wMin; s++) {
    tail += counts[s];
  }
  return (math.min(1.0, 2 * tail / all), n);
}

/// Exact two-sided Mann–Whitney U test (permutation distribution via DP on
/// doubled midranks) and the Vargha–Delaney A12 effect size P(X<Y)+0.5P(X=Y).
(double, double) mannWhitney(List<double> x, List<double> y) {
  final n = x.length, m = y.length;
  if (n == 0 || m == 0) return (double.nan, double.nan);
  final ranks = _doubledRanks([...x, ...y]);
  final total = ranks.reduce((a, b) => a + b);
  // counts[k][s]: number of k-subsets with doubled rank sum s
  final counts = List.generate(n + 1, (_) => List<double>.filled(total + 1, 0));
  counts[0][0] = 1;
  for (final r in ranks) {
    for (var k = n; k >= 1; k--) {
      for (var s = total; s >= r; s--) {
        counts[k][s] += counts[k - 1][s - r];
      }
    }
  }
  var observed = 0;
  for (var i = 0; i < n; i++) {
    observed += ranks[i];
  }
  final expected = n * (n + m + 1); // doubled mean rank sum
  final dev = (observed - expected).abs();
  var extreme = 0.0, all = 0.0;
  for (var s = 0; s <= total; s++) {
    all += counts[n][s];
    if ((s - expected).abs() >= dev) extreme += counts[n][s];
  }
  var a12 = 0.0;
  for (final xi in x) {
    for (final yj in y) {
      a12 += xi < yj ? 1 : (xi == yj ? 0.5 : 0);
    }
  }
  return (extreme / all, a12 / (n * m));
}

List<double> holm(List<double> p) {
  final idx = List<int>.generate(p.length, (i) => i)..sort((a, b) => p[a].compareTo(p[b]));
  final adj = List<double>.filled(p.length, double.nan);
  var running = 0.0;
  for (var k = 0; k < idx.length; k++) {
    final v = math.min(1.0, (p.length - k) * p[idx[k]]);
    running = math.max(running, v);
    adj[idx[k]] = running;
  }
  return adj;
}

String f(double v, [int digits = 4]) {
  if (v.isNaN) return '—';
  if (v.abs() >= 1000) return v.toStringAsFixed(0);
  return v.toStringAsPrecision(digits);
}

// ── SVG helpers (print-safe, light surface; palette validated) ────────────
const surface = '#ffffff';
const ink = '#0b0b0b', ink2 = '#52514e', muted = '#898781', grid = '#e1e0d9', baseline = '#c3c2b7';
const series = ['#2a78d6', '#eb6834', '#1baf7a', '#6250d6'];

String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

List<double> niceTicks(double lo, double hi, int n) {
  final span = hi - lo;
  if (span <= 0) return [lo];
  final raw = span / n;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1.0, 2.0, 2.5, 5.0, 10.0].map((s) => s * mag).firstWhere((s) => s >= raw);
  final start = (lo / step).ceil() * step;
  return [for (var v = start; v <= hi + 1e-12; v += step) v];
}

String boxplotSvg(String title, List<String> conds, Map<String, List<double>> values, String reference,
    String axisLabel) {
  const left = 190.0, right = 30.0, top = 48.0, rowH = 30.0;
  final width = 760.0;
  final height = top + rowH * conds.length + 52;
  final all = values.values.expand((v) => v).where((v) => v.isFinite).toList();
  var lo = all.reduce(math.min), hi = all.reduce(math.max);
  final pad = (hi - lo) * 0.06 + 1e-12;
  lo -= pad;
  hi += pad;
  double x(double v) => left + (v - lo) / (hi - lo) * (width - left - right);
  final sb = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" '
        'viewBox="0 0 $width $height" font-family="Helvetica, Arial, sans-serif" role="img">')
    ..writeln('<title>${esc(title)}</title>')
    ..writeln('<rect width="100%" height="100%" fill="$surface"/>')
    ..writeln('<text x="12" y="24" font-size="15" font-weight="600" fill="$ink">${esc(title)}</text>');
  for (final t in niceTicks(lo, hi, 6)) {
    sb.writeln('<line x1="${x(t)}" y1="$top" x2="${x(t)}" y2="${top + rowH * conds.length}" '
        'stroke="$grid" stroke-width="1"/>');
    sb.writeln('<text x="${x(t)}" y="${top + rowH * conds.length + 16}" font-size="11" fill="$muted" '
        'text-anchor="middle">${f(t, 3)}</text>');
  }
  sb.writeln('<text x="${(left + width - right) / 2}" y="${height - 10}" font-size="12" fill="$ink2" '
      'text-anchor="middle">${esc(axisLabel)}</text>');
  for (var i = 0; i < conds.length; i++) {
    final c = conds[i];
    final v = values[c]!.where((e) => e.isFinite).toList();
    final cy = top + rowH * i + rowH / 2;
    final isRef = c == reference;
    final color = isRef ? series[0] : '#6b6a64';
    sb.writeln('<text x="${left - 10}" y="${cy + 4}" font-size="12" fill="${isRef ? ink : ink2}" '
        'text-anchor="end"${isRef ? ' font-weight="600"' : ''}>${esc(c)} (n=${v.length})</text>');
    if (v.isEmpty) continue;
    final q1 = quantile(v, 0.25), q2 = quantile(v, 0.5), q3 = quantile(v, 0.75);
    final iqr = q3 - q1;
    final wlo = v.where((e) => e >= q1 - 1.5 * iqr).reduce(math.min);
    final whi = v.where((e) => e <= q3 + 1.5 * iqr).reduce(math.max);
    sb.writeln('<line x1="${x(wlo)}" y1="$cy" x2="${x(whi)}" y2="$cy" stroke="$color" stroke-width="1.5"/>');
    if (v.length > 1) {
      sb.writeln('<rect x="${x(q1)}" y="${cy - 8}" width="${math.max(1.0, x(q3) - x(q1))}" height="16" rx="4" '
          'fill="$color" fill-opacity="0.18" stroke="$color" stroke-width="1.5"/>');
    }
    sb.writeln('<line x1="${x(q2)}" y1="${cy - 9}" x2="${x(q2)}" y2="${cy + 9}" stroke="$color" stroke-width="2.5"/>');
    for (var k = 0; k < v.length; k++) {
      final jitter = ((k * 37) % 11 - 5) * 0.9;
      sb.writeln('<circle cx="${x(v[k])}" cy="${cy + jitter}" r="3" fill="$color" fill-opacity="0.75" '
          'stroke="$surface" stroke-width="1"><title>${esc(c)}: ${f(v[k], 5)}</title></circle>');
    }
  }
  sb.writeln('</svg>');
  return sb.toString();
}

String convergenceSvg(String title, Map<String, List<Run>> byCond, List<String> conds, String yLabel) {
  const left = 70.0, right = 150.0, top = 48.0, bottom = 50.0;
  const width = 760.0, height = 420.0;
  // Common evaluation grid; step-wise (last value at or before x).
  double maxE = 0;
  for (final c in conds) {
    for (final r in byCond[c]!) {
      if (r.curve.isNotEmpty) maxE = math.max(maxE, r.curve.last.$1);
    }
  }
  if (maxE == 0) return '';
  final grid = [for (var i = 1; i <= 60; i++) maxE * i / 60];
  double at(List<(double, double)> c, double e) {
    double v = double.nan;
    for (final p in c) {
      if (p.$1 <= e) v = p.$2;
    }
    return v;
  }

  final bands = <String, List<(double, double, double)>>{};
  var ylo = double.infinity, yhi = 0.0;
  for (final c in conds) {
    final pts = <(double, double, double)>[];
    for (final e in grid) {
      final vals = byCond[c]!.map((r) => at(r.curve, e)).where((v) => v.isFinite).toList();
      if (vals.length < 2) {
        pts.add((double.nan, double.nan, double.nan));
        continue;
      }
      final t = (quantile(vals, 0.25), quantile(vals, 0.5), quantile(vals, 0.75));
      pts.add(t);
      ylo = math.min(ylo, t.$1);
      yhi = math.max(yhi, t.$3);
    }
    bands[c] = pts;
  }
  if (!ylo.isFinite || yhi <= 0) return '';
  // Log scale on y (errors span orders of magnitude early in the run).
  final ly0 = math.log(math.max(ylo, 1e-12)) / math.ln10, ly1 = math.log(yhi) / math.ln10;
  double x(double e) => left + e / maxE * (width - left - right);
  double y(double v) => top + (ly1 - math.log(v) / math.ln10) / (ly1 - ly0 + 1e-12) * (height - top - bottom);
  final sb = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" '
        'viewBox="0 0 $width $height" font-family="Helvetica, Arial, sans-serif" role="img">')
    ..writeln('<title>${esc(title)}</title>')
    ..writeln('<rect width="100%" height="100%" fill="$surface"/>')
    ..writeln('<text x="12" y="24" font-size="15" font-weight="600" fill="$ink">${esc(title)}</text>');
  for (var p = ly0.floor(); p <= ly1.ceil(); p++) {
    for (final mlt in [1, 2, 5]) {
      final v = mlt * math.pow(10, p).toDouble();
      final lv = math.log(v) / math.ln10;
      if (lv < ly0 - 1e-9 || lv > ly1 + 1e-9) continue;
      sb.writeln('<line x1="$left" y1="${y(v)}" x2="${width - right}" y2="${y(v)}" stroke="$grid"/>');
      sb.writeln('<text x="${left - 6}" y="${y(v) + 4}" font-size="11" fill="$muted" text-anchor="end">${f(v, 2)}</text>');
    }
  }
  for (final t in niceTicks(0, maxE, 6)) {
    sb.writeln('<text x="${x(t)}" y="${height - bottom + 16}" font-size="11" fill="$muted" text-anchor="middle">'
        '${t >= 1000 ? '${(t / 1000).toStringAsFixed(0)}k' : f(t, 3)}</text>');
  }
  sb
    ..writeln('<line x1="$left" y1="${height - bottom}" x2="${width - right}" y2="${height - bottom}" stroke="$baseline"/>')
    ..writeln('<text x="${(left + width - right) / 2}" y="${height - 12}" font-size="12" fill="$ink2" '
        'text-anchor="middle">Objective-function evaluations</text>')
    ..writeln('<text transform="translate(16 ${(top + height - bottom) / 2}) rotate(-90)" font-size="12" '
        'fill="$ink2" text-anchor="middle">${esc(yLabel)}</text>');
  for (var ci = 0; ci < conds.length; ci++) {
    final c = conds[ci];
    final col = series[ci % series.length];
    final pts = bands[c]!;
    final up = <String>[], dn = <String>[], mid = <String>[];
    for (var i = 0; i < grid.length; i++) {
      final (q1, q2, q3) = pts[i];
      if (!q2.isFinite) continue;
      up.add('${x(grid[i])},${y(q3)}');
      dn.add('${x(grid[i])},${y(q1)}');
      mid.add('${x(grid[i])},${y(q2)}');
    }
    if (mid.isEmpty) continue;
    sb.writeln('<polygon points="${[...up, ...dn.reversed].join(' ')}" fill="$col" fill-opacity="0.12" stroke="none"/>');
    sb.writeln('<polyline points="${mid.join(' ')}" fill="none" stroke="$col" stroke-width="2" '
        'stroke-linejoin="round"><title>${esc(c)} (median, IQR band)</title></polyline>');
    final last = mid.last.split(',');
    sb.writeln('<text x="${double.parse(last[0]) + 6}" y="${double.parse(last[1]) + 4 + ci * 2}" font-size="12" '
        'fill="$ink">${esc(c)}</text>');
  }
  sb.writeln('</svg>');
  return sb.toString();
}

void main(List<String> args) {
  String opt(String k, String def) {
    final i = args.indexOf('--$k');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
  }

  final resultsDir = Directory(opt('results', ''));
  final reference = opt('reference', 'aegis_full');
  final out = Directory(opt('out', '${resultsDir.path}/analysis'))..createSync(recursive: true);
  final title = opt('title', resultsDir.uri.pathSegments.where((s) => s.isNotEmpty).last);
  final convConds = opt('convergence', '').split(',').where((s) => s.isNotEmpty).toList();
  final evaluations = opt('evaluations', '');
  if (evaluations.isNotEmpty &&
      (evaluations.contains('/') || evaluations.contains('\\') || evaluations == '..')) {
    throw ArgumentError('--evaluations must be a filename inside each condition');
  }
  if (evaluations.isNotEmpty && !args.contains('--out')) {
    throw ArgumentError('--evaluations requires --out to preserve the primary analysis');
  }

  final byCond = <String, List<Run>>{};
  for (final d in resultsDir.listSync().whereType<Directory>()) {
    if (d.path.endsWith('analysis')) continue;
    final runs = loadCondition(d, evaluations: evaluations.isEmpty ? null : evaluations);
    if (runs.isNotEmpty) byCond[runs.first.condition] = runs;
  }
  if (byCond.isEmpty) {
    stderr.writeln('no runs found under ${resultsDir.path}');
    exit(1);
  }
  final conds = byCond.keys.toList()
    ..sort((a, b) {
      double med(String c) => quantile(byCond[c]!.map((r) => r.m['testFR'] ?? double.nan)
          .where((v) => v.isFinite).toList(), 0.5);
      return med(a).compareTo(med(b));
    });

  // runs.csv
  final csv = StringBuffer('condition,seed,${metrics.keys.join(',')},diverged,agentAccepted,agentRejected,llmCostUsd\n');
  for (final c in conds) {
    for (final r in byCond[c]!) {
      csv.writeln('$c,${r.seed},${metrics.keys.map((k) => r.m[k]?.toString() ?? '').join(',')},'
          '${r.diverged},${r.agent['actionsAccepted'] ?? ''},${r.agent['actionsRejected'] ?? ''},'
          '${r.agent['llmCostUsd'] ?? ''}');
    }
  }
  File('${out.path}/runs.csv').writeAsStringSync(csv.toString());

  // Descriptive statistics.
  final stats = <String, dynamic>{'benchmark': title, 'reference': reference, 'conditions': {}};
  final md = StringBuffer()
    ..writeln('# $title — results')
    ..writeln()
    ..writeln('Generated by `tool/experiments/analyze.dart` on ${DateTime.now().toUtc().toIso8601String()}.')
    ..writeln('Primary metric: free-run (simulation) RMSE on the **test** set, original output units, '
        'initialisation window excluded. Lower is better. Bootstrap: 10 000 resamples, percentile 95 % CI of the mean.')
    ..writeln();
  for (final key in ['testFR', 'testOS', 'testFit', 'valFR', 'nParams', 'evals', 'wall']) {
    final (label, _) = metrics[key]!;
    md
      ..writeln('## $label')
      ..writeln()
      ..writeln('| Condition | n | mean ± sd | median [IQR] | 95 % CI (mean) | min – max | diverged |')
      ..writeln('|---|---|---|---|---|---|---|');
    for (final c in conds) {
      final v = byCond[c]!.map((r) => r.m[key]).whereType<double>().where((x) => x.isFinite).toList();
      if (v.isEmpty) continue;
      final (lo, hi) = bootstrapCi(v);
      final div = byCond[c]!.where((r) => r.diverged).length;
      md.writeln('| $c | ${v.length} | ${f(mean(v))} ± ${f(sd(v))} | ${f(quantile(v, 0.5))} '
          '[${f(quantile(v, 0.25))}, ${f(quantile(v, 0.75))}] | [${f(lo)}, ${f(hi)}] | '
          '${f(v.reduce(math.min))} – ${f(v.reduce(math.max))} | $div |');
      (stats['conditions'][c] ??= <String, dynamic>{})[key] = {
        'n': v.length, 'mean': mean(v), 'sd': sd(v), 'median': quantile(v, 0.5),
        'q1': quantile(v, 0.25), 'q3': quantile(v, 0.75), 'ci95': [lo, hi],
        'min': v.reduce(math.min), 'max': v.reduce(math.max), 'diverged': div,
      };
    }
    md.writeln();
  }

  // Comparisons against the reference condition.
  if (byCond.containsKey(reference)) {
    for (final key in ['testFR', 'valFR', 'nParams']) {
      final (label, _) = metrics[key]!;
      final rows = <(String, String, double, int, double, double)>[];
      final ref = {for (final r in byCond[reference]!) r.seed: r.m[key]};
      for (final c in conds) {
        if (c == reference) continue;
        final other = byCond[c]!;
        final paired = other.every((r) => ref.containsKey(r.seed)) && other.length > 1 &&
            !c.startsWith('legacy') && c != 'frols';
        if (paired) {
          final diffs = [for (final r in other) if (r.m[key] != null && ref[r.seed] != null) r.m[key]! - ref[r.seed]!];
          final (p, n) = wilcoxon(diffs);
          rows.add((c, 'Wilcoxon (paired by seed)', quantile(diffs, 0.5), n, p,
              diffs.where((d) => d < 0).length / math.max(1, diffs.length)));
        } else if (other.length > 1) {
          final x = other.map((r) => r.m[key]).whereType<double>().toList();
          final y = ref.values.whereType<double>().toList();
          final (p, a12) = mannWhitney(x, y);
          rows.add((c, 'Mann–Whitney (unpaired)', quantile(x, 0.5) - quantile(y, 0.5), x.length, p, a12));
        }
      }
      if (rows.isEmpty) continue;
      final adj = holm(rows.map((r) => r.$5).toList());
      md
        ..writeln('## Comparison with `$reference` — $label')
        ..writeln()
        ..writeln('Paired tests use the same seeds. Effect: median of paired differences (condition − reference) '
            'and fraction of seeds where the condition is lower; for unpaired tests, difference of medians and '
            'A12 = P(condition < reference). p-values are two-sided, exact, Holm-adjusted across the rows of this table.')
        ..writeln()
        ..writeln('| Condition | test | n | effect (median Δ) | P(lower) / A12 | p | p (Holm) |')
        ..writeln('|---|---|---|---|---|---|---|');
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        md.writeln('| ${r.$1} | ${r.$2} | ${r.$4} | ${f(r.$3)} | ${f(r.$6, 2)} | ${f(r.$5, 3)} | ${f(adj[i], 3)} |');
        (stats['comparisons'] ??= <String, dynamic>{})['$key/${r.$1}'] = {
          'test': r.$2, 'n': r.$4, 'effect': r.$3, 'pLowerOrA12': r.$6, 'p': r.$5, 'pHolm': adj[i],
        };
      }
      md.writeln();
    }
  }

  // Agents.
  final agentConds = conds.where((c) => byCond[c]!.any((r) => r.agent.isNotEmpty && r.agent['spec'] != 'none'));
  if (agentConds.isNotEmpty) {
    md
      ..writeln('## Agent activity')
      ..writeln()
      ..writeln('| Condition | decisions (status: count, summed over seeds) | actions accepted | rejected | LLM calls | mean latency (ms) | LLM cost (USD) |')
      ..writeln('|---|---|---|---|---|---|---|');
    for (final c in agentConds) {
      final dec = <String, int>{};
      var acc = 0, rej = 0, calls = 0;
      var lat = 0.0, cost = 0.0;
      for (final r in byCond[c]!) {
        (r.agent['decisions'] as Map? ?? {}).forEach((k, v) => dec[k as String] = (dec[k] ?? 0) + (v as num).toInt());
        acc += (r.agent['actionsAccepted'] as num? ?? 0).toInt();
        rej += (r.agent['actionsRejected'] as num? ?? 0).toInt();
        final n = (r.agent['llmCalls'] as num? ?? 0).toInt();
        calls += n;
        lat += ((r.agent['llmMeanLatencyMs'] as num?) ?? 0) * n;
        cost += (r.agent['llmCostUsd'] as num? ?? 0).toDouble();
      }
      md.writeln('| $c | ${dec.entries.map((e) => '${e.key}: ${e.value}').join(', ')} | $acc | $rej | $calls | '
          '${calls > 0 ? f(lat / calls) : '—'} | ${f(cost, 3)} |');
    }
    md.writeln();
  }

  File('${out.path}/SUMMARY.md').writeAsStringSync(md.toString());
  File('${out.path}/stats.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(jsonSafe(stats)));
  final values = {for (final c in conds) c: byCond[c]!.map((r) => r.m['testFR'] ?? double.nan).toList()};
  File('${out.path}/boxplot_test_freerun.svg').writeAsStringSync(boxplotSvg(
      '$title — test free-run RMSE per condition', conds, values, reference,
      'Test free-run RMSE (original units; lower is better)'));
  final cc = convConds.isNotEmpty
      ? convConds.where(byCond.containsKey).toList()
      : conds.where((c) => byCond[c]!.any((r) => r.curve.isNotEmpty)).take(4).toList();
  final conv = convergenceSvg('$title — convergence (median and IQR over seeds)', byCond, cc,
      'Validation free-run RMSE (normalized)');
  if (conv.isNotEmpty) File('${out.path}/convergence.svg').writeAsStringSync(conv);
  stdout.writeln('analysis written to ${out.path} (${conds.length} conditions)');
}

/// JSON-safe copy: non-finite doubles become null.
Object? jsonSafe(Object? v) {
  if (v is double) return v.isFinite ? v : null;
  if (v is Map) return v.map((k, e) => MapEntry(k.toString(), jsonSafe(e)));
  if (v is List) return v.map(jsonSafe).toList();
  if (v is (double, double)) return [jsonSafe(v.$1), jsonSafe(v.$2)];
  return v;
}
