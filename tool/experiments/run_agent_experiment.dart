// Headless AEGIS experiment runner with agents (lockstep mode).
//
//   dart run tool/experiments/run_agent_experiment.dart \
//     --dll cpp/build/aegis_core.dll --data est.csv [--data-test test.csv] \
//     --config experiments/configs/conditions/aegis_full.json [--set key=value ...] \
//     --agent none|ucb1|fuzzy|fuzzy:<rulebase.json>|cac|cac:<table.json>|cac4|cac4:<table.json>|script:<p=v@g;...>|llm --seed 1 --output <dir> [--label name]
//     [--llm-model claude-opus-5-5] [--llm-effort medium] [--consult-every 50] [--max-cost 5]
//
// Each generation: step(1) → snapshot → agent.consult() (awaited) → proposed
// actions are submitted through aegis_apply_action (source = agent id) and the
// core's ActionRecord is returned to the agent. Writes run_<seed>.json in the
// same format as aegis_batch (report + history) plus the agent decisions
// (decisions_<seed>.jsonl) so all conditions are analysed by the same tool.
// The LLM agent is only used with --agent llm and requires ANTHROPIC_API_KEY.

import 'dart:convert';
import 'dart:io';

import 'package:aegis/agent/generation_snapshot.dart';
import 'package:aegis/core/math/matrix.dart';
import 'package:aegis/ffi/aegis_ffi_service_native.dart';
import 'package:aegis/ffi/aegis_library_native.dart';
import 'package:aegis/services/fuzzy_policy_agent.dart';
import 'package:aegis/services/convergence_controller.dart';
import 'package:aegis/services/scripted_agent.dart';
import 'package:aegis/services/llm_agent_native.dart';
import 'package:aegis/services/local_adaptive_agent.dart';
import 'package:aegis/services/optimization_agent.dart';

List<List<double>> readCsv(String path) {
  final rows = <List<double>>[];
  for (final line in File(path).readAsLinesSync()) {
    final parts = line.split(RegExp(r'[,;\t]')).where((s) => s.trim().isNotEmpty);
    final values = parts.map((s) => double.tryParse(s.trim())).toList();
    if (values.isEmpty || values.any((v) => v == null)) continue;
    rows.add(values.cast<double>());
  }
  return rows;
}

Future<void> main(List<String> args) async {
  final opts = <String, List<String>>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      final key = args[i].substring(2);
      final value = (i + 1 < args.length && !args[i + 1].startsWith('--')) ? args[++i] : 'true';
      (opts[key] ??= []).add(value);
    }
  }
  String opt(String k, [String? def]) {
    final v = opts[k]?.last ?? def;
    if (v == null) {
      stderr.writeln('missing --$k');
      exit(2);
    }
    return v;
  }

  final dll = opt('dll', 'cpp/build/aegis_core.dll');
  final seed = int.parse(opt('seed', '1'));
  final agentSpec = opt('agent', 'none');
  final outDir = opt('output');
  final label = opt('label', agentSpec);
  if (!AegisLibrary.tryLoad(path: File(dll).absolute.path)) {
    stderr.writeln('cannot load $dll');
    exit(1);
  }
  final lib = AegisLibrary.instance!;
  if (!lib.hasAuditApi) {
    stderr.writeln('the loaded core does not provide the typed action interface');
    exit(1);
  }

  // ── Data and configuration (same conventions as aegis_batch) ──────────
  final est = readCsv(opt('data'));
  final testPath = opts['data-test']?.last;
  final test = testPath != null ? readCsv(testPath) : <List<double>>[];
  final all = [...est, ...test];
  final cols = all.first.length;
  final m = Matrix(all.length, cols);
  for (var r = 0; r < all.length; r++) {
    for (var c = 0; c < cols; c++) {
      m.set(r, c, all[r][c]);
    }
  }
  final config = jsonDecode(File(opt('config')).readAsStringSync()) as Map<String, dynamic>;
  for (final kv in opts['set'] ?? const <String>[]) {
    final eq = kv.indexOf('=');
    final k = kv.substring(0, eq), raw = kv.substring(eq + 1);
    Object? v;
    try {
      v = jsonDecode(raw);
    } catch (_) {
      v = raw;
    }
    config[k] = v;
  }
  if (test.isNotEmpty) {
    config.putIfAbsent('trainEndRow', () => (est.length * ((config['trainRatio'] as num?) ?? 0.8)).floor());
    config.putIfAbsent('valEndRow', () => est.length);
    config['testStartRow'] = est.length;
  }
  config['syncMode'] = true;
  config['webSocketPort'] = 0;
  config['randomSeed'] = seed;
  config.putIfAbsent('numThreads', () => 1);

  // ── Agent ─────────────────────────────────────────────────────────────
  final service = AegisFfiService(lib);
  OptimizationAgent? agent;
  if (agentSpec == 'ucb1') {
    agent = LocalAdaptiveAgent(currentParameters: () => service.parameters.currentValues);
  } else if (agentSpec == 'fuzzy') {
    agent = FuzzyPolicyAgent(phaseStagnationLimit: (config['phaseStagnationLimit'] as num?)?.toInt() ?? 150);
  } else if (agentSpec.startsWith('fuzzy:')) {
    final rb = FuzzyRuleBase.fromJson(
        jsonDecode(File(agentSpec.substring(6)).readAsStringSync()) as Map<String, dynamic>);
    agent = FuzzyPolicyAgent(
      ruleBase: rb,
      id: 'fuzzy-${rb.name}',
      phaseStagnationLimit: (config['phaseStagnationLimit'] as num?)?.toInt() ?? 150,
    );
  } else if (agentSpec.startsWith('script:')) {
    agent = ScriptedAgent.parse(agentSpec.substring(7), actionSchema: service.getActionSchema,
        phaseStagnationLimit: (config['phaseStagnationLimit'] as num?)?.toInt() ?? 150);
  } else if (agentSpec == 'cac' || agentSpec.startsWith('cac:') || agentSpec == 'cac4' || agentSpec.startsWith('cac4:')) {
    final v4 = agentSpec.startsWith('cac4');
    final tablePath = agentSpec.contains(':') ? agentSpec.substring(agentSpec.indexOf(':') + 1) : null;
    agent = AdaptiveConvergenceController(
      actionSchema: service.getActionSchema,
      currentParameters: () => service.parameters.currentValues,
      phaseStagnationLimit: (config['phaseStagnationLimit'] as num?)?.toInt() ?? 150,
      seed: seed,
      version: v4 ? 4 : 3,
      table: tablePath != null
          ? jsonDecode(File(tablePath).readAsStringSync()) as Map<String, dynamic>
          : null,
    );
  } else if (agentSpec == 'llm') {
    agent = LlmAgent(
      model: opt('llm-model', 'claude-opus-5-5'),
      effort: opt('llm-effort', 'medium'),
      consultEvery: int.parse(opt('consult-every', '50')),
      maxCostUsd: double.parse(opt('max-cost', '5')),
    );
    if (!agent.available) {
      stderr.writeln('LLM agent requested but ANTHROPIC_API_KEY is not set; aborting (no call made).');
      exit(3);
    }
  } else if (agentSpec != 'none') {
    stderr.writeln('unknown agent $agentSpec');
    exit(2);
  }

  Directory(outDir).createSync(recursive: true);
  final decisionsFile = File('$outDir/decisions_$seed.jsonl').openWrite();
  final decisionCounts = <String, int>{};
  var acceptedActions = 0, rejectedActions = 0;
  double llmCost = 0, llmLatencyTotal = 0;
  var llmCalls = 0;
  agent?.onDecision = (AgentDecision d) {
    decisionCounts[d.status] = (decisionCounts[d.status] ?? 0) + 1;
    if (d.latencyMs != null) {
      llmLatencyTotal += d.latencyMs!;
      llmCalls++;
    }
    llmCost += d.costUsd ?? 0;
    decisionsFile.writeln(jsonEncode(d.toMap()));
  };
  agent?.onSuggestion = (param, value, reason) {
    final result = service.applyAction(param, value, reason: reason, source: agent!.id);
    if (result['accepted'] == true) {
      acceptedActions++;
    } else {
      rejectedActions++;
    }
    decisionsFile.writeln(jsonEncode({'schema': 'aegis.action_result/1', 'seed': seed, ...result}));
    agent.onActionResult(result);
  };

  // ── Run ───────────────────────────────────────────────────────────────
  if (!service.initialize(
    normalizedData: m,
    outputCol: (config['outputCol'] as num?)?.toInt() ?? cols - 1,
    numVariables: cols,
    configJson: jsonEncode(config),
  )) {
    stderr.writeln('initialize failed: ${service.lastError()}');
    exit(1);
  }
  final sw = Stopwatch()..start();
  if (!service.start()) {
    stderr.writeln('start failed: ${service.lastError()}');
    exit(1);
  }
  while (service.step(1) > 0) {
    if (agent == null) continue;
    final GenerationSnapshot? snap = service.readSnapshot();
    if (snap == null || snap.stopReason.isNotEmpty) continue;
    await agent.consult(snap);
  }
  final wall = sw.elapsedMicroseconds / 1e6;
  await decisionsFile.flush();
  await decisionsFile.close();

  final report = service.getFinalReport();
  final history = service.getHistoryRecords();
  final record = {
    'schema': 'aegis.batch_run/1',
    'label': label,
    'seed': seed,
    'timestamp': DateTime.now().toIso8601String(),
    'dataFile': opt('data'),
    'testFile': testPath ?? '',
    'wallSeconds': wall,
    'agent': {
      'spec': agentSpec,
      'id': agent?.id,
      'name': agent?.name,
      'decisions': decisionCounts,
      'actionsAccepted': acceptedActions,
      'actionsRejected': rejectedActions,
      'llmCalls': llmCalls,
      'llmMeanLatencyMs': llmCalls > 0 ? llmLatencyTotal / llmCalls : null,
      'llmCostUsd': llmCost,
      if (agent is LocalAdaptiveAgent) 'arms': agent.armStatistics,
      if (agent is LocalAdaptiveAgent) 'inconclusiveObservations': agent.inconclusiveObservations,
      if (agent is FuzzyPolicyAgent) 'ruleBase': agent.ruleBase.toJson(),
      if (agent is AdaptiveConvergenceController) 'cacTable': agent.tableJson(),
      if (agent is AdaptiveConvergenceController) 'cacCalibration': agent.calibration,
      if (agent is AdaptiveConvergenceController) 'cacInconclusive': agent.inconclusive,
    },
    'report': report,
    'history': history,
  };
  File('$outDir/run_$seed.json').writeAsStringSync(jsonEncode(record));
  agent?.dispose();
  service.dispose();
  stdout.writeln('seed $seed ($label) done in ${wall.toStringAsFixed(1)} s; '
      'decisions=$decisionCounts accepted=$acceptedActions rejected=$rejectedActions');
}
