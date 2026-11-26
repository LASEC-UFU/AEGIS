// P2'a audit summary: reads AEGIS_P2A_AUDIT files (one line per inner-loop
// candidate) and reports fallback rate and agreement with the exact QR path.
//   dart run tool/experiments/p2a_audit.dart <dir> [<dir> ...]
// Columns: K nDen fast reason [coefRel sseRel ratioDiff zerosQR zerosNormal]
import 'dart:io';

double q(List<double> v, double f) => v.isEmpty ? double.nan : v[((v.length - 1) * f).round()];
String e(double x) => x.isNaN ? '—' : x.toStringAsExponential(1);

void main(List<String> dirs) {
  for (final d in dirs) {
    final lines = Directory(d).listSync().whereType<File>()
        .where((f) => RegExp(r'audit\.\d+\.tsv$').hasMatch(f.path))
        .expand((f) => f.readAsLinesSync()).where((l) => l.isNotEmpty).toList();
    var n = 0, fast = 0, qrFail = 0;
    final reasons = <String, int>{};
    final coef = <double>[], sse = <double>[], ratio = <double>[];
    var rankMismatch = 0;
    for (final l in lines) {
      final c = l.split('\t');
      n++;
      if (c[2] == '0') { reasons[c[3]] = (reasons[c[3]] ?? 0) + 1; continue; }
      if (c.length < 9) { qrFail++; continue; }
      fast++;
      coef.add(double.parse(c[4]).abs());
      sse.add(double.parse(c[5]));
      ratio.add(double.parse(c[6]).abs());
      if (c[7] != c[8]) rankMismatch++;
    }
    coef.sort(); sse.sort(); ratio.sort();
    final absSse = sse.map((x) => x.abs()).toList()..sort();
    print('## $d\n');
    print('- candidates: $n; fast path: $fast (${(100 * fast / n).toStringAsFixed(1)} %); '
        'fallback: ${reasons.entries.map((e) => 'reason ${e.key} = ${e.value}').join(', ')}; QR failed in audit: $qrFail');
    print('- rank decisions differ (zero coefficients QR vs normal): $rankMismatch');
    print('- max |Δθ| / max|θ|: median ${e(q(coef, .5))}, p99 ${e(q(coef, .99))}, max ${e(q(coef, 1))}');
    print('- (SSE_normal − SSE_QR)/SSE_QR: median ${e(q(sse, .5))}, p99 |.| ${e(q(absSse, .99))}, max ${e(q(sse, 1))}, min ${e(q(sse, 0))}');
    print('- |Δ input ratio|: median ${e(q(ratio, .5))}, p99 ${e(q(ratio, .99))}, max ${e(q(ratio, 1))}\n');
  }
}
