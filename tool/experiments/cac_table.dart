// Extracts the CAC arm table (agent.cacTable) from a run JSON written by
// run_agent_experiment.dart, so the next development run can start from it.
//   dart run tool/experiments/cac_table.dart <run.json> <table.json>
import 'dart:convert';
import 'dart:io';

void main(List<String> a) {
  final j = jsonDecode(File(a[0]).readAsStringSync()) as Map<String, dynamic>;
  final t = (j['agent'] as Map?)?['cacTable'];
  if (t == null) { stderr.writeln('no cacTable in ${a[0]}'); exit(1); }
  File(a[1]).writeAsStringSync(jsonEncode(t));
}
