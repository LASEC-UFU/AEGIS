// Prepares the public benchmark datasets used in the AEGIS evaluation.
//
//   dart run tool/benchmarks/prepare_benchmarks.dart [--raw experiments/data/raw]
//                                                    [--out experiments/data/processed]
//
// Raw files must be downloaded first (see docs/BENCHMARKS.md). For each raw
// file the SHA-256 is verified against the value recorded at download time.
// Splits follow the open-source `nonlinear_benchmarks` dataloader
// (Beintema & Schoukens), which encodes the official protocols:
//   Wiener-Hammerstein: train = samples [5200, 105200), test = [105200, 184000)
//   Silverbox (SNLS80mV): train = multisine [40650, 105712),
//                          test_multisine = [105712, 127400), test_arrow = [100, 40575)
//   Cascaded Tanks: train = uEst/yEst, test = uVal/yVal
// with a 50-sample state-initialisation window at the start of each test set.
//
// To bound the computational cost of the evolutionary runs, the estimation
// file of the two long benchmarks is a contiguous prefix of the official
// training set (--est-samples, default 20000); test sets are kept complete.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'mat5.dart';

const expectedRawSha256 = {
  'cascaded_tanks/CascadedTanksFiles.zip':
      'eb0fa05851e8a7136846c2e3b61fbef87def78d0852c86ab91b02ac5db541b51',
  'wiener_hammerstein/WienerHammerBenchMark.mat':
      '096e6128687efb664d146d28fc17db4c5a94f247c4b3a2e451319be1efb25ae2',
  'silverbox/SilverboxFiles.zip':
      '2398dda503ac4c30f46c7a1ba09d8a8864d001cc71bbeb59f207a054cc592d8c',
};

String sha256File(String path) => sha256.convert(File(path).readAsBytesSync()).toString();

void writeCsv(String path, List<double> u, List<double> y) {
  final sb = StringBuffer('u,y\n');
  for (var i = 0; i < u.length; i++) {
    sb.writeln('${u[i]},${y[i]}');
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(sb.toString());
}

List<List<double>> readCsvColumns(String path) {
  final lines = File(path).readAsLinesSync();
  final cols = <List<double>>[];
  for (final line in lines) {
    final parts = line.split(',').where((s) => s.trim().isNotEmpty).toList();
    final values = parts.map((s) => double.tryParse(s.trim())).toList();
    if (values.isEmpty || values.first == null) continue; // header
    while (cols.length < values.length) {
      cols.add(<double>[]);
    }
    for (var i = 0; i < values.length; i++) {
      if (values[i] != null) cols[i].add(values[i]!);
    }
  }
  return cols;
}

void main(List<String> args) {
  String opt(String name, String def) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
  }

  final raw = opt('--raw', 'experiments/data/raw');
  final out = opt('--out', 'experiments/data/processed');
  final estSamples = int.parse(opt('--est-samples', '20000'));
  final provenance = <String, dynamic>{
    'tool': 'tool/benchmarks/prepare_benchmarks.dart',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'estSamplesLongBenchmarks': estSamples,
    'raw': <String, dynamic>{},
    'processed': <String, dynamic>{},
  };

  // ── Verify raw files ──────────────────────────────────────────────────
  for (final e in expectedRawSha256.entries) {
    final path = '$raw/${e.key}';
    if (!File(path).existsSync()) {
      stderr.writeln('missing raw file $path (see docs/BENCHMARKS.md)');
      exitCode = 1;
      continue;
    }
    final h = sha256File(path);
    provenance['raw'][e.key] = {'sha256': h, 'expected': e.value, 'ok': h == e.value};
    if (h != e.value) {
      stderr.writeln('SHA-256 mismatch for $path\n  got      $h\n  expected ${e.value}');
      exitCode = 1;
    }
  }
  if (exitCode != 0) return;

  void record(String key, String path, Map<String, dynamic> meta) {
    provenance['processed'][key] = {
      'file': path,
      'sha256': sha256File(path),
      ...meta,
    };
  }

  // ── Cascaded Tanks ────────────────────────────────────────────────────
  {
    final cols = readCsvColumns('$raw/cascaded_tanks/extracted/CascadedTanksFiles/dataBenchmark.csv');
    // Columns: uEst, uVal, yEst, yVal, Ts (Ts only in the first row).
    final n = cols[0].length;
    final est = '$out/cascaded_tanks/est.csv';
    final test = '$out/cascaded_tanks/test.csv';
    writeCsv(est, cols[0], cols[2].sublist(0, n));
    writeCsv(test, cols[1], cols[3].sublist(0, n));
    final meta = {'samplingTime': cols[4].first, 'initWindow': 50, 'source': 'dataBenchmark.csv'};
    record('cascaded_tanks/est', est, {...meta, 'rows': n, 'definition': 'uEst, yEst (complete)'});
    record('cascaded_tanks/test', test, {...meta, 'rows': n, 'definition': 'uVal, yVal (complete)'});
  }

  // ── Wiener-Hammerstein ────────────────────────────────────────────────
  {
    final mat = readMat5('$raw/wiener_hammerstein/WienerHammerBenchMark.mat');
    final u = mat['uBenchMark']!.vector;
    final y = mat['yBenchMark']!.vector;
    final fs = mat['fs']!.vector.first;
    final trainU = u.sublist(5200, 105200), trainY = y.sublist(5200, 105200);
    final testU = u.sublist(105200, 184000), testY = y.sublist(105200, 184000);
    final est = '$out/wiener_hammerstein/est.csv';
    final estFull = '$out/wiener_hammerstein/est_full.csv';
    final test = '$out/wiener_hammerstein/test.csv';
    writeCsv(est, trainU.sublist(0, estSamples), trainY.sublist(0, estSamples));
    writeCsv(estFull, trainU, trainY);
    writeCsv(test, testU, testY);
    final meta = {'fs': fs, 'samplingTime': 1 / fs, 'initWindow': 50, 'recordLength': u.length};
    record('wiener_hammerstein/est', est, {...meta, 'rows': estSamples,
        'definition': 'official train [5200,105200) — first $estSamples samples'});
    record('wiener_hammerstein/est_full', estFull, {...meta, 'rows': trainU.length,
        'definition': 'official train [5200,105200)'});
    record('wiener_hammerstein/test', test, {...meta, 'rows': testU.length,
        'definition': 'official test [105200,184000)'});

    // Provenance of the legacy repository file Benchmarks/WH_estimation_uy.csv.
    final legacy = File('Benchmarks/WH_estimation_uy.csv');
    if (legacy.existsSync()) {
      final lc = readCsvColumns(legacy.path);
      int match = -1;
      for (var s = 0; s + lc[0].length <= u.length && match < 0; s++) {
        if ((u[s] - lc[0][0]).abs() < 1e-6 && (y[s] - lc[1][0]).abs() < 1e-6) {
          var ok = true;
          for (var i = 1; i < 50 && ok; i++) {
            ok = (u[s + i] - lc[0][i]).abs() < 1e-6 && (y[s + i] - lc[1][i]).abs() < 1e-6;
          }
          if (ok) match = s;
        }
      }
      var maxDev = double.nan;
      if (match >= 0) {
        maxDev = 0;
        for (var i = 0; i < lc[0].length; i++) {
          maxDev = [maxDev, (u[match + i] - lc[0][i]).abs(), (y[match + i] - lc[1][i]).abs()]
              .reduce((a, b) => a > b ? a : b);
        }
      }
      provenance['legacyRepositoryFile'] = {
        'file': legacy.path,
        'sha256': sha256File(legacy.path),
        'rows': lc[0].length,
        'matchesOfficialRecordAtSample': match,
        'maxAbsDeviation': maxDev.isNaN ? null : maxDev,
      };
    }
  }

  // ── Silverbox ─────────────────────────────────────────────────────────
  {
    final cols = readCsvColumns('$raw/silverbox/extracted/SilverboxFiles/SNLS80mV.csv');
    final u = cols[0], y = cols[1];
    final multisineStart = 40650, multisineEnd = 127400;
    final s = ((multisineEnd - multisineStart) * 0.75).toInt();
    final trU = u.sublist(multisineStart, multisineStart + s);
    final trY = y.sublist(multisineStart, multisineStart + s);
    final est = '$out/silverbox/est.csv';
    final testMs = '$out/silverbox/test_multisine.csv';
    final testArrow = '$out/silverbox/test_arrow.csv';
    writeCsv(est, trU.sublist(0, estSamples), trY.sublist(0, estSamples));
    writeCsv(testMs, u.sublist(multisineStart + s, multisineEnd), y.sublist(multisineStart + s, multisineEnd));
    writeCsv(testArrow, u.sublist(100, 40575), y.sublist(100, 40575));
    final meta = {'samplingTime': 1 / 610.35, 'initWindow': 50, 'source': 'SNLS80mV.csv (V1 input, V2 output)'};
    record('silverbox/est', est, {...meta, 'rows': estSamples,
        'definition': 'multisine train [40650,${multisineStart + s}) — first $estSamples samples'});
    record('silverbox/test_multisine', testMs, {...meta, 'rows': multisineEnd - multisineStart - s,
        'definition': 'test_multisine [${multisineStart + s},127400)'});
    record('silverbox/test_arrow', testArrow, {...meta, 'rows': 40475,
        'definition': 'test_arrow_full [100,40575) (includes amplitude extrapolation)'});
  }

  final pf = File('$out/PROVENANCE.json')..parent.createSync(recursive: true);
  pf.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(provenance));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(provenance));
}

