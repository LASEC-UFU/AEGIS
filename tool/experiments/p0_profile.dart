// P0 profiling analyzer (docs/architecture/10_AUDITORIA_DO_09.md §11.3,
// 12_AUDITORIA_DO_11.md §6). Reads the probe files written by an instrumented
// build (-DAEGIS_PROFILE, cpp/src/perf_probe.hpp) and the run JSON of the same
// directory. Validation-only runs; reads no metric of any kind, only times,
// structure counts and `wallSeconds`.
//
//   dart run tool/experiments/p0_profile.dart <run_dir> [<run_dir> ...]
//
// Probe columns: K nden nfac nnonint md ok t_psi t_fit t_pred t_err t_ratio
// t_val t_sim t_rest [struct]. Times in ns.
//   psi   = build Ψ (train)                fit  = pseudo-linearise + QR
//   pred  = one-step prediction (train)    err  = full ERR (chrom.err)
//   ratio = grouped ERR (input ratio)      val  = Ψ val + one-step val
//   sim   = Metrics + free-run simulation  rest = stability, residual corr, fitness
// Early-return candidates (invalid Ψ or fit failure) put their time in the
// stage reached; they are counted with ok = 0.
//
// With a struct column, also simulates the hit rate of an unbounded cache of
// shift-invariant statistics (10 §11.1): 1-lag keys for N·N, N·y, D·y and
// 2-lag keys for N·D and D·D.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const stages = ['psi', 'fit', 'pred', 'err', 'ratio', 'val', 'sim', 'rest'];
const kBins = [5, 10, 20, 30, 40, 1 << 30];

String binName(int i) => i == 0
    ? 'K≤5'
    : (kBins[i] >= 1 << 30 ? 'K>${kBins[i - 1]}' : '${kBins[i - 1] + 1}–${kBins[i]}');

int binOf(int k) {
  for (var i = 0; i < kBins.length; i++) {
    if (k <= kBins[i]) return i;
  }
  return kBins.length - 1;
}

String pct(double x) => '${(100 * x).toStringAsFixed(1)} %';
String sec(double ns) => (ns / 1e9).toStringAsFixed(1);

class Shape {
  final String key;
  final int m;
  final bool den;
  Shape(this.key, this.m, this.den);
}

Shape parseRegressor(String s) {
  final den = s.startsWith('D:');
  final terms = s.substring(2).split(';').map((t) {
    final p = t.split(',');
    return [int.parse(p[0]), int.parse(p[1]), double.parse(p[2])];
  }).toList();
  final m = terms.map((t) => t[1] as int).reduce(math.min);
  final rel = terms.map((t) => '${t[0]}@${(t[1] as int) - m}^${t[2]}').toList()..sort();
  return Shape(rel.join('*'), m, den);
}

void main(List<String> dirs) {
  final out = StringBuffer();
  for (final d in dirs) {
    final dir = Directory(d);
    final probes = dir.listSync().whereType<File>().where((f) => RegExp(r'probe\.\d+\.tsv$').hasMatch(f.path)).toList();
    final runs = dir.listSync().whereType<File>().where((f) => RegExp(r'run_\d+\.json$').hasMatch(f.path)).toList();
    if (probes.isEmpty) {
      out.writeln('## $d\n\nno probe file\n');
      continue;
    }
    double wall = double.nan;
    if (runs.length == 1) {
      final j = jsonDecode(runs.first.readAsStringSync());
      final w = j['wallSeconds'] ?? (j['report'] is Map ? j['report']['wallSeconds'] : null);
      if (w is num) wall = w.toDouble();
    }
    final tot = List<double>.filled(stages.length, 0);
    final binT = List.generate(kBins.length, (_) => List<double>.filled(stages.length, 0));
    final binN = List<int>.filled(kBins.length, 0);
    final ks = <int>[];
    var n = 0, nOk = 0, withDen = 0, fac = 0, nonint = 0;
    // cache study
    final seen1 = <String>{}, seen2 = <String>{};
    var req1 = 0, hit1 = 0, req2 = 0, hit2 = 0;
    final decile = <List<int>>[]; // per tenth of the run: [req, hit] over both
    var hasStruct = false;
    final lines = <String>[];
    for (final p in probes) {
      lines.addAll(p.readAsLinesSync().where((l) => l.isNotEmpty));
    }
    final total = lines.length;
    for (final l in lines) {
      final c = l.split('\t');
      final k = int.parse(c[0]);
      final nden = int.parse(c[1]);
      n++;
      if (c[5] == '1') nOk++;
      if (nden > 0) withDen++;
      fac += int.parse(c[2]);
      nonint += int.parse(c[3]);
      ks.add(k);
      final b = binOf(k);
      binN[b]++;
      for (var s = 0; s < stages.length; s++) {
        final t = double.parse(c[6 + s]);
        tot[s] += t;
        binT[b][s] += t;
      }
      if (c.length > 14 && c[14].isNotEmpty) {
        hasStruct = true;
        final regs = c[14].split('/').map(parseRegressor).toList();
        final dec = math.min(9, (10 * (n - 1)) ~/ math.max(1, total));
        while (decile.length <= dec) {
          decile.add([0, 0]);
        }
        void ask1(String key) {
          req1++;
          decile[dec][0]++;
          if (!seen1.add(key)) {
            hit1++;
            decile[dec][1]++;
          }
        }
        void ask2(String key) {
          req2++;
          decile[dec][0]++;
          if (!seen2.add(key)) {
            hit2++;
            decile[dec][1]++;
          }
        }
        for (var a = 0; a < regs.length; a++) {
          final ra = regs[a];
          // column times y: N·y (1 lag) or D·y (1 lag, weight y²)
          ask1('${ra.den ? 'Dy' : 'Ny'}|${ra.key}|${ra.m}');
          for (var bb = a; bb < regs.length; bb++) {
            final rb = regs[bb];
            if (!ra.den && !rb.den) {
              // N·N: shift invariant, keyed by the lag difference
              var x = ra, y = rb;
              if (x.key.compareTo(y.key) > 0) {
                x = rb;
                y = ra;
              }
              ask1('NN|${x.key}|${y.key}|${x.m - y.m}');
            } else if (ra.den && rb.den) {
              var x = ra, y = rb;
              if ('${x.key}|${x.m}'.compareTo('${y.key}|${y.m}') > 0) {
                x = rb;
                y = ra;
              }
              ask2('DD|${x.key}|${x.m}|${y.key}|${y.m}');
            } else {
              final nn = ra.den ? rb : ra, dd = ra.den ? ra : rb;
              ask2('ND|${nn.key}|${nn.m}|${dd.key}|${dd.m}');
            }
          }
        }
      }
    }
    ks.sort();
    int q(double f) => ks[math.min(ks.length - 1, (f * ks.length).floor())];
    final evalNs = tot.reduce((a, b) => a + b);
    out.writeln('## $d\n');
    out.writeln('- evaluate() calls: $n (valid $nOk); K quartiles ${q(0.25)} / ${q(0.5)} / ${q(0.75)}, max ${ks.last}');
    out.writeln('- candidates with denominator: ${pct(withDen / n)}; non-integer exponent factors: ${pct(nonint / math.max(1, fac))} of $fac');
    if (wall.isFinite) {
      out.writeln('- wall ${wall.toStringAsFixed(1)} s; inside evaluate() ${sec(evalNs)} s '
          '(${pct(evalNs / 1e9 / wall)}); outside (DE, migration, diagnostics, I/O) ${pct(1 - evalNs / 1e9 / wall)}');
    }
    out.writeln('\n| stage | ${stages.join(' | ')} |');
    out.writeln('|---|${'---|' * stages.length}');
    out.writeln('| share of evaluate() | ${List.generate(stages.length, (s) => s).map((s) => pct(tot[s] / evalNs)).join(' | ')} |');
    for (var b = 0; b < kBins.length; b++) {
      if (binN[b] == 0) continue;
      final bt = binT[b].reduce((a, c) => a + c);
      out.writeln('| ${binName(b)} (${binN[b]} cand., ${(bt / binN[b] / 1e3).toStringAsFixed(0)} µs/cand.) | '
          '${List.generate(stages.length, (s) => s).map((s) => pct(binT[b][s] / bt)).join(' | ')} |');
    }
    if (hasStruct) {
      out.writeln('\nShift-invariant statistics cache (unbounded, simulated):');
      out.writeln('- 1-lag keys (N·N, N·y, D·y): requests $req1, hit ${pct(hit1 / math.max(1, req1))}, distinct ${seen1.length}');
      out.writeln('- 2-lag keys (N·D, D·D): requests $req2, hit ${pct(hit2 / math.max(1, req2))}, distinct ${seen2.length}');
      out.writeln('- hit rate by tenth of the run: '
          '${decile.map((x) => pct(x[1] / math.max(1, x[0]))).join(', ')}');
    }
    out.writeln();
  }
  stdout.write(out);
}
