// Offline improvement of the interpretable fuzzy policy from logged agent
// trajectories (any agent: UCB1, fuzzy, LLM, manual).
//
//   dart run tool/experiments/learn_fuzzy_policy.dart --out rb.json [--min-support 3]
//        [--seeds 1-5] <runs-dir> [<runs-dir> ...]
//
// Data: every accepted, resolved, conclusive action recorded by the C++ core
// (final report → actions[]) in runs whose seed is in --seeds (training
// seeds). Each record holds the state digest before the action, the action
// (parameter, old → new value) and the observed outcome (default
// --outcome freeRunValFull: the relative change of the champion's VALIDATION
// free-run RMSE in the H generations after the action minus the change in the
// H generations before it; --outcome rmseVal uses the core's one-step record):
// the relative change
// of the champion's validation RMSE in the following H generations minus the
// change in the H generations before the action (drift baseline). Positive =
// better than the drift.
//
// Learning (deliberately simple and auditable):
//  - features at action time are computed exactly as the agent computes them;
//  - for each rule r: support_r = Σ firing_r(x_i) over records with the same
//    parameter and the same direction as r's consequent; utility_r = weighted
//    mean outcome score; the same for the opposite direction;
//  - if support < min-support: rule kept unchanged ("insufficient data");
//    if the opposite direction has positive utility larger than r's: the
//    consequent sign is flipped; else if utility_r < 0: rule disabled
//    (weight 0); otherwise weight 1.
// The resulting rule base is written as JSON with a per-rule report. It must
// be evaluated on different seeds (and benchmarks) before any claim.

import 'dart:convert';
import 'dart:io';

import 'package:aegis/services/fuzzy_policy_agent.dart';

Map<String, double> featuresFromDigest(Map<String, dynamic> pre, {int psl = 150, int totalPop = 150}) {
  double d(String k) => (pre[k] as num?)?.toDouble() ?? double.nan;
  final train = d('rmseTrain'), val = d('rmseVal'), sim = d('freeRunRmseValFull');
  return {
    'stag': d('stagnation') / psl,
    'sr': d('successRate'),
    'div': d('uniqueStructures') / totalPop,
    'gap': (train.isFinite && train > 0 && val.isFinite) ? (val - train) / train : double.nan,
    'sim': (val.isFinite && val > 0 && sim.isFinite) ? sim / val : double.nan,
  };
}

void main(List<String> args) {
  String? out;
  var minSupport = 3.0;
  var outcome = 'freeRunValFull';
  var seedLo = 1, seedHi = 1 << 30;
  final dirs = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out':
        out = args[++i];
      case '--outcome':
        outcome = args[++i];
      case '--min-support':
        minSupport = double.parse(args[++i]);
      case '--seeds':
        final p = args[++i].split('-');
        seedLo = int.parse(p.first);
        seedHi = int.parse(p.last);
      default:
        dirs.add(args[i]);
    }
  }
  if (out == null || dirs.isEmpty) {
    stderr.writeln('usage: learn_fuzzy_policy --out rb.json [--seeds a-b] dir...');
    exit(2);
  }

  // ── Collect conclusive action records ───────────────────────────────────
  final records = <({String param, double dir, double score, Map<String, double> f, String source})>[];
  var seen = 0, inconclusive = 0, rejected = 0;
  for (final d in dirs) {
    for (final f in Directory(d).listSync().whereType<File>()) {
      final m = RegExp(r'run_(\d+)\.json$').firstMatch(f.path);
      if (m == null) continue;
      final seed = int.parse(m.group(1)!);
      if (seed < seedLo || seed > seedHi) continue;
      final run = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final rep = run['report'] as Map<String, dynamic>?;
      final cfg = rep?['config'] as Map<String, dynamic>? ?? const {};
      final psl = (cfg['phaseStagnationLimit'] as num?)?.toInt() ?? 150;
      final pop = ((cfg['numIslands'] as num?) ?? 3).toInt() * ((cfg['populationSize'] as num?) ?? 50).toInt();
      // Per-generation validation free-run RMSE (for the simulation-aligned outcome).
      final frByGen = <int, double>{
        for (final h in (run['history'] as List? ?? const []))
          if (h is Map && h['freeRunValFull'] is num) (h['g'] as num).toInt(): (h['freeRunValFull'] as num).toDouble(),
      };
      final horizon = (cfg['outcomeHorizon'] as num?)?.toInt() ?? 25;
      double? frAt(int g) => frByGen[g];
      for (final a in (rep?['actions'] as List? ?? const [])) {
        final r = a as Map<String, dynamic>;
        if (r['source'] == 'reflex') continue;
        seen++;
        if (r['accepted'] != true) {
          rejected++;
          continue;
        }
        if (r['outcome'] == 'inconclusive' || r['resolved'] != true) {
          inconclusive++;
          continue;
        }
        double score;
        if (outcome == 'rmseVal') {
          // Core outcome: one-step validation RMSE, drift-corrected.
          final post = (r['postChange'] as num?)?.toDouble();
          final pre = (r['preTrend'] as num?)?.toDouble() ?? 0.0;
          if (post == null || !post.isFinite) {
            inconclusive++;
            continue;
          }
          score = (-post) - (-(pre.isFinite ? pre : 0.0));
        } else {
          // Simulation-aligned outcome: validation free-run RMSE (whole split),
          // relative change in the H generations after the action minus the
          // change in the H generations before it.
          final g = (r['generationApplied'] as num?)?.toInt() ?? -1;
          final before = frAt(g - horizon), at = frAt(g), after = frAt(g + horizon);
          if (at == null || after == null || at <= 0) {
            inconclusive++;
            continue;
          }
          final dAfter = (after - at) / at;
          final dBefore = (before != null && before > 0) ? (at - before) / before : 0.0;
          score = (-dAfter) - (-dBefore);
        }
        final oldV = (r['oldValue'] as num?)?.toDouble() ?? double.nan;
        final newV = (r['newValue'] as num?)?.toDouble() ?? double.nan;
        if (!oldV.isFinite || !newV.isFinite || oldV == newV) continue;
        records.add((
          param: r['param'] as String,
          dir: (newV - oldV).sign,
          score: score,
          f: featuresFromDigest(r['pre'] as Map<String, dynamic>, psl: psl, totalPop: pop),
          source: r['source'] as String? ?? '',
        ));
      }
    }
  }

  // ── Per-rule utility ────────────────────────────────────────────────────
  final base = FuzzyRuleBase.expert();
  final agent = FuzzyPolicyAgent(ruleBase: base);
  final newRules = <FuzzyRule>[];
  final report = <Map<String, dynamic>>[];
  for (final rule in base.rules) {
    double wSame = 0, sSame = 0, wOpp = 0, sOpp = 0;
    var nSame = 0, nOpp = 0;
    for (final rec in records) {
      if (rec.param != rule.param) continue;
      final w = agent.firing(rec.f)[rule.id] ?? 0.0;
      if (w <= 0) continue;
      if (rec.dir == rule.delta.sign) {
        wSame += w;
        sSame += w * rec.score;
        nSame++;
      } else {
        wOpp += w;
        sOpp += w * rec.score;
        nOpp++;
      }
    }
    final uSame = wSame > 0 ? sSame / wSame : double.nan;
    final uOpp = wOpp > 0 ? sOpp / wOpp : double.nan;
    var decision = 'kept (insufficient data)';
    var updated = rule;
    if (wSame + wOpp >= minSupport) {
      if (wOpp >= minSupport && uOpp > 0 && (uSame.isNaN || uOpp > uSame)) {
        updated = rule.copyWith(delta: -rule.delta, weight: 1.0);
        decision = 'consequent flipped';
      } else if (wSame >= minSupport && uSame < 0) {
        updated = rule.copyWith(weight: 0.0);
        decision = 'disabled (negative utility)';
      } else if (wSame >= minSupport) {
        decision = 'kept (non-negative utility)';
      }
    }
    newRules.add(updated);
    report.add({
      'rule': rule.id,
      'param': rule.param,
      'delta': rule.delta,
      'supportSame': wSame,
      'nSame': nSame,
      'utilitySame': uSame.isNaN ? null : uSame,
      'supportOpposite': wOpp,
      'nOpposite': nOpp,
      'utilityOpposite': uOpp.isNaN ? null : uOpp,
      'decision': decision,
    });
  }
  final learned = FuzzyRuleBase(
    name: 'learned-v1',
    variables: base.variables,
    rules: newRules,
    bounds: base.bounds,
    evidenceThreshold: base.evidenceThreshold,
  );
  File(out).writeAsStringSync(learned.encode());
  final summary = {
    'schema': 'aegis.fuzzy_learning_report/1',
    'sources': dirs,
    'trainingSeeds': '$seedLo-${seedHi == 1 << 30 ? 'all' : seedHi}',
    'actionsSeen': seen,
    'rejectedByCore': rejected,
    'inconclusive': inconclusive,
    'conclusiveRecords': records.length,
    'meanScore': records.isEmpty ? null : records.map((r) => r.score).reduce((a, b) => a + b) / records.length,
    'bySource': {
      for (final s in records.map((r) => r.source).toSet())
        s: records.where((r) => r.source == s).length,
    },
    'minSupport': minSupport,
    'outcome': outcome,
    'rules': report,
  };
  File('${out.replaceAll(RegExp(r'\.json$'), '')}_report.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
}
