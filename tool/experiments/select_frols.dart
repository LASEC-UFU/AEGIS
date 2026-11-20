// Picks the FROLS configuration with the lowest VALIDATION free-run RMSE and
// writes <dir>/selected.json (the analysis tool reads it). Test metrics are
// carried along but never used for the choice.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final dir = Directory(args.first);
  Map<String, dynamic>? best;
  double bestVal = double.infinity;
  String? bestFile;
  final table = <String>[];
  for (final f in dir.listSync().whereType<File>().where((f) => RegExp(r'frols_ny.*\.json$').hasMatch(f.path))) {
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final sel = j['selectedByValidationSimulation'] as Map<String, dynamic>?;
    final v = (((sel?['metrics'] as Map?)?['validation'] as Map?)?['rmseFreeRunOrig'] as num?)?.toDouble();
    table.add('${f.uri.pathSegments.last}: k=${(sel?['numRegressors'])}, validation free-run RMSE=$v');
    if (v != null && v.isFinite && v < bestVal) {
      bestVal = v;
      best = j;
      bestFile = f.path;
    }
  }
  if (best == null) {
    stderr.writeln('no FROLS result found in ${dir.path}');
    exit(1);
  }
  File('${dir.path}/selected.json').writeAsStringSync(jsonEncode({
    'schema': 'aegis.frols_selection/1',
    'criterion': 'minimum validation free-run RMSE over the (ny, nu, degree) grid',
    'selectedFile': bestFile,
    'ny': best['ny'], 'nu': best['nu'], 'degree': best['degree'],
    'totalSeconds': best['totalSeconds'],
    'result': best['selectedByValidationSimulation'],
    'grid': table,
  }));
  stdout.writeln(table.join('\n'));
  stdout.writeln('selected: $bestFile');
}
