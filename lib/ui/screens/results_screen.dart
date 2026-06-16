import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/stat_card.dart';
import '../../agent/generation_snapshot.dart';
import '../../engine/de/de_engine.dart';
import '../../core/types/chromosome.dart';
import '../../core/types/regressor.dart';
import '../../core/types/term.dart';

/// Results screen — shows final model, equation, and validation.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eState = ref.watch(engineProvider);
    final snap = eState.latestSnapshot;
    final notifier = ref.watch(engineProvider.notifier);

    Chromosome? best;
    Map<String, dynamic>? bestModelJson;
    if (notifier.usingCpp) {
      bestModelJson = notifier.getBestModelJson();
      if (bestModelJson != null && bestModelJson['status'] != 'not_available') {
        best = _chromosomeFromJson(bestModelJson);
      }
    } else if (notifier.loadedChromosome != null) {
      best = notifier.loadedChromosome;
    } else {
      best = notifier.engine?.bestChromosome;
    }

    if (snap == null || best == null || !best.isEvaluated) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Results'),
          actions: [
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Carregar JSON exportado',
              onPressed: () => _importJson(context, ref),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, size: 64, color: AppColors.gray700),
              const SizedBox(height: 16),
              Text(
                eState.state == EngineState.completed
                    ? 'No model was identified'
                    : 'Results will appear after evolution completes',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Carregar resultado JSON'),
                onPressed: () => _importJson(context, ref),
              ),
            ],
          ),
        ),
      );
    }

    final model = best;

    // Output column index — used to tell apart input regressors (u) from
    // autoregressive output-feedback regressors (y) in the equation display.
    final outputCol = notifier.usingCpp
        ? (bestModelJson?['outputCol'] as num?)?.toInt() ?? 0
        : notifier.loadedChromosome != null
            ? notifier.loadedChromosome!.outputIndex
            : ref.read(outputIndexProvider);

    // R²/RMSE for train/val come from the live snapshot for the Dart engine,
    // or from the final best-model JSON for the C++ engine.
    final r2Train = notifier.usingCpp
        ? (bestModelJson?['r2Train'] as num?)?.toDouble() ?? double.nan
        : snap.bestModelR2;
    final rmseTrain = notifier.usingCpp
        ? (bestModelJson?['rmseTrain'] as num?)?.toDouble() ?? double.nan
        : snap.bestModelRMSE;
    final r2Test = notifier.usingCpp
        ? (bestModelJson?['r2Test'] as num?)?.toDouble()
        : notifier.loadedR2Test;
    final rmseTest = notifier.usingCpp
        ? (bestModelJson?['rmseTest'] as num?)?.toDouble()
        : notifier.loadedRmseTest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identified Model'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Carregar JSON exportado',
            onPressed: () => _importJson(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Exportar JSON',
            onPressed: () => _exportJson(
              context,
              best: model,
              snap: snap,
              r2Train: r2Train,
              rmseTrain: rmseTrain,
              r2Test: r2Test,
              rmseTest: rmseTest,
              outputCol: outputCol,
            ),
          ),
          if (eState.state == EngineState.completed)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Chip(
                avatar: Icon(
                  Icons.check_circle,
                  size: 14,
                  color: AppColors.success,
                ),
                label: Text(
                  'Complete',
                  style: TextStyle(fontSize: 11, color: AppColors.success),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Model equation
                _ModelEquationCard(best: model, outputCol: outputCol),
                const SizedBox(height: 20),
                // Quality metrics
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 600 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 2.0,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        StatCard(
                          label: 'FITNESS (BIC)',
                          value: model.fitness.toStringAsFixed(4),
                          icon: Icons.emoji_events,
                          valueColor: AppColors.success,
                        ),
                        StatCard(
                          label: 'R² (TRAIN)',
                          value: r2Train.toStringAsFixed(6),
                          icon: Icons.my_location,
                          valueColor: r2Train > 0.95
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                        StatCard(
                          label: 'RMSE (TRAIN)',
                          value: rmseTrain.toStringAsFixed(6),
                          icon: Icons.straighten,
                        ),
                        StatCard(
                          label: 'REGRESSORS',
                          value: '${model.numRegressors}',
                          icon: Icons.layers,
                          subtitle:
                              'Max degree ${model.maxDegree}, delay ${model.maxDelay}',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                // Test-set validation (held-out 15%, never seen during evolution)
                if (r2Test != null && rmseTest != null)
                  _TestValidationCard(r2Test: r2Test, rmseTest: rmseTest),
                if (r2Test != null && rmseTest != null)
                  const SizedBox(height: 20),
                // ERR contributions
                _ERRTable(
                  err: model.err ?? [],
                  coefficients: model.coefficients ?? [],
                  labels: snap.bestModelTermLabels,
                ),
                const SizedBox(height: 20),
                // Residual analysis
                if (snap.residualAutocorrelation != null)
                  _AutocorrelationCard(autocorr: snap.residualAutocorrelation!),
                const SizedBox(height: 20),
                // Run summary
                _RunSummary(
                  generations: snap.generation,
                  elapsed: snap.elapsed,
                  stagnation: snap.stagnationCounter,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Export JSON ─────────────────────────────────────────────

Future<void> _exportJson(
  BuildContext context, {
  required Chromosome best,
  required GenerationSnapshot snap,
  required double r2Train,
  required double rmseTrain,
  double? r2Test,
  double? rmseTest,
  required int outputCol,
}) async {
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);

  final regressors = best.regressors.map((reg) {
    return {
      'terms': reg.components.map((ct) => {
        'variable': ct.term.variable,
        'delay': ct.term.delay,
        'exponent': ct.exponent,
        'isDenominator': ct.term.isDenominator,
        'role': (ct.term.isDenominator || ct.term.variable == outputCol) ? 'y' : 'u',
      }).toList(),
    };
  }).toList();

  // Gerar labels de cada regressor para o JSON exportado
  final termLabels = regressors.map<String>((r) {
    return _regressorLabel(r as Map<String, dynamic>);
  }).toList();

  final payload = {
    'aegis_version': '2.1',
    'exported_at': timestamp,
    'output_col': outputCol,
    'term_labels': termLabels,
    'model': {
      'num_regressors': best.numRegressors,
      'max_delay': best.maxDelay,
      'max_degree': best.maxDegree,
      'intercept': best.intercept,
      'coefficients': best.coefficients ?? [],
      'err': best.err ?? [],
      'regressors': regressors,
      'fitness': best.fitness,
    },
    'metrics': {
      'r2_train': r2Train,
      'rmse_train': rmseTrain,
      'r2_test': r2Test,
      'rmse_test': rmseTest,
    },
    'run': {
      'generations': snap.generation,
      'elapsed_ms': snap.elapsed.inMilliseconds,
      'stagnation': snap.stagnationCounter,
      'phase': snap.phase,
      'phase_name': snap.phaseName,
      'success_rate': snap.successRate,
      'unique_structures': snap.uniqueStructures,
      'population_variance': snap.populationVariance,
      'input_contribution_ratio': snap.inputContributionRatio,
    },
    'fitness_breakdown': snap.fitnessBreakdown,
  };

  final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
  final defaultName = 'aegis_model_$timestamp.json';

  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar modelo identificado',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return; // cancelled
    await File(path).writeAsString(jsonString, encoding: utf8);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exportado: $path'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao exportar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

// ─── Geração de label de regressor (espelho do C++ make_regressor_label) ──

String _regressorLabel(Map<String, dynamic> regMap) {
  final terms = regMap['terms'] as List? ?? [];
  if (terms.isEmpty) return 'const';
  final parts = terms.map<String>((t) {
    final tm = t as Map<String, dynamic>;
    final role = tm['role'] as String? ?? 'u';
    final delay = (tm['delay'] as num).toInt();
    final exponent = (tm['exponent'] as num?)?.toDouble() ?? 1.0;
    var label = '${role == 'y' ? 'y' : 'u'}(k-$delay)';
    if ((exponent - 1.0).abs() > 0.05) {
      final rounded = exponent.roundToDouble().toInt();
      if ((exponent - rounded.toDouble()).abs() < 0.05) {
        label += rounded == 2 ? '²' : rounded == 3 ? '³' : '^$rounded';
      } else {
        label += '^${exponent.toStringAsFixed(2)}';
      }
    }
    return label;
  }).join('·');
  final isDenom = terms.any((t) => (t as Map)['isDenominator'] as bool? ?? false);
  return isDenom ? '$parts[D]' : parts;
}

List<String> _labelsFromPayload(Map<String, dynamic> payload) {
  // Se o JSON já traz term_labels (v2.1+), usa diretamente
  final stored = payload['term_labels'];
  if (stored is List && stored.isNotEmpty) {
    return stored.map((e) => e.toString()).toList();
  }
  // Compatibilidade retroativa: gera a partir da estrutura de regressores
  final regs = (payload['model']?['regressors'] as List?) ?? [];
  return regs.map<String>((r) => _regressorLabel(r as Map<String, dynamic>)).toList();
}

// ─── Import JSON ────────────────────────────────────────────────

Future<void> _importJson(BuildContext context, WidgetRef ref) async {
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Abrir modelo AEGIS exportado',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir arquivo: $e'),
            backgroundColor: AppColors.error),
      );
    }
    return;
  }
  if (result == null || result.files.isEmpty) return;

  try {
    final path = result.files.single.path!;
    final content = await File(path).readAsString();
    final payload = jsonDecode(content) as Map<String, dynamic>;

    // Valida formato básico
    if (payload['model'] == null) {
      throw const FormatException('JSON inválido: campo "model" ausente.');
    }

    final modelMap = payload['model'] as Map<String, dynamic>;
    final metricsMap = (payload['metrics'] as Map<String, dynamic>?) ?? {};
    final runMap = (payload['run'] as Map<String, dynamic>?) ?? {};

    // Reconstrói cromossomo
    final chromosome = _chromosomeFromJson(modelMap)
        .copyWith(outputIndex: (payload['output_col'] as num?)?.toInt() ?? 0);

    // Labels: do JSON (v2.1+) ou gerados dos regressores
    final labels = _labelsFromPayload(payload);

    // Métricas de treino
    final r2Train   = (metricsMap['r2_train']   as num?)?.toDouble() ?? double.nan;
    final rmseTrain = (metricsMap['rmse_train']  as num?)?.toDouble() ?? double.nan;
    final r2Test    = (metricsMap['r2_test']     as num?)?.toDouble();
    final rmseTest  = (metricsMap['rmse_test']   as num?)?.toDouble();

    // Snapshot sintético com os dados do arquivo
    final snap = GenerationSnapshot(
      generation:            (runMap['generations'] as num?)?.toInt() ?? 0,
      elapsed:               Duration(milliseconds: (runMap['elapsed_ms'] as num?)?.toInt() ?? 0),
      bestFitness:           chromosome.fitness.isFinite ? chromosome.fitness : 0.0,
      worstFitness:          double.infinity,
      meanFitness:           chromosome.fitness.isFinite ? chromosome.fitness : 0.0,
      medianFitness:         chromosome.fitness.isFinite ? chromosome.fitness : 0.0,
      stdDevFitness:         0.0,
      q1Fitness:             double.infinity,
      q3Fitness:             double.infinity,
      improvementAbsolute:   0.0,
      improvementRelative:   0.0,
      improvementRate5:      0.0,
      improvementRate20:     0.0,
      stagnationCounter:     (runMap['stagnation'] as num?)?.toInt() ?? 0,
      uniqueStructures:      (runMap['unique_structures'] as num?)?.toInt() ?? 0,
      structureEntropy:      0.0,
      phenotypicDiversity:   0.0,
      regressorFrequency:    {},
      populationVariance:    (runMap['population_variance'] as num?)?.toDouble() ?? 0.0,
      successRate:           (runMap['success_rate'] as num?)?.toDouble() ?? 0.0,
      successRateHistory:    [],
      bestModelComplexity:   chromosome.numRegressors,
      bestModelMaxDegree:    chromosome.maxDegree,
      bestModelMaxDelay:     chromosome.maxDelay,
      bestModelERR:          chromosome.err ?? [],
      bestModelTermLabels:   labels,
      bestModelRMSE:         rmseTrain,
      bestModelR2:           r2Train,
      islandSnapshots:       [],
      phase:                 (runMap['phase'] as num?)?.toInt() ?? 0,
      phaseName:             (runMap['phase_name'] as String?) ?? '',
      inputContributionRatio: (runMap['input_contribution_ratio'] as num?)?.toDouble(),
      fitnessBreakdown:      _mapToDoubleMap(payload['fitness_breakdown']),
    );

    ref.read(engineProvider.notifier).loadFromJson(
      chromosome: chromosome,
      snapshot:   snap,
      r2Test:     r2Test,
      rmseTest:   rmseTest,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modelo carregado: ${result.files.single.name}'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao importar JSON: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

Map<String, double> _mapToDoubleMap(dynamic raw) {
  if (raw is! Map) return {};
  return raw.map((k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0));
}

// ─── JSON → Chromosome (C++ engine best-model result) ─────────

Chromosome _chromosomeFromJson(Map<String, dynamic> j) {
  final regressorsJson = j['regressors'] as List? ?? [];
  final regressors = regressorsJson.map((r) {
    final termsJson = (r as Map<String, dynamic>)['terms'] as List? ?? [];
    final components = termsJson.map((t) {
      final tm = t as Map<String, dynamic>;
      return CompoundTerm(
        term: Term(
          variable: (tm['variable'] as num).toInt(),
          delay: (tm['delay'] as num).toInt(),
          isDenominator: tm['isDenominator'] as bool? ?? false,
        ),
        exponent: (tm['exponent'] as num?)?.toDouble() ?? 1.0,
      );
    }).toList();
    return Regressor(components);
  }).toList();

  final coeffs = (j['coefficients'] as List?)
      ?.map((e) => (e as num).toDouble())
      .toList();
  final err = (j['err'] as List?)?.map((e) => (e as num).toDouble()).toList();

  return Chromosome(
    regressors: regressors,
    coefficients: coeffs,
    intercept: (j['intercept'] as num?)?.toDouble() ?? 0.0,
    err: err,
    fitness: (j['fitness'] as num?)?.toDouble() ?? double.nan,
    sse: (j['sse'] as num?)?.toDouble() ?? double.nan,
    maxDelay: (j['maxDelay'] as num?)?.toInt()
        ?? (j['max_delay'] as num?)?.toInt()
        ?? 0,
  );
}

// ─── Test-set validation card ─────────────────────────────────

class _TestValidationCard extends StatelessWidget {
  final double r2Test;
  final double rmseTest;

  const _TestValidationCard({required this.r2Test, required this.rmseTest});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.fact_check, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Test Set Validation (held-out 15%)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'R² (TEST)',
                    value: r2Test.isFinite ? r2Test.toStringAsFixed(6) : 'N/A',
                    icon: Icons.my_location,
                    valueColor: r2Test > 0.95
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: 'RMSE (TEST)',
                    value: rmseTest.isFinite
                        ? rmseTest.toStringAsFixed(6)
                        : 'N/A',
                    icon: Icons.straighten,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Model equation card ──────────────────────────────────────

class _ModelEquationCard extends StatelessWidget {
  final Chromosome best;
  final int outputCol;

  const _ModelEquationCard({required this.best, required this.outputCol});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.functions,
                  size: 18,
                  color: AppColors.accent,
                ),
                SizedBox(width: 10),
                Text(
                  'Model Equation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.backgroundDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.gray750),
              ),
              child: SelectableText(
                _buildEquation(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: AppColors.accent,
                  height: 1.8,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${best.numRegressors} terms | Max degree: ${best.maxDegree} | Max delay: ${best.maxDelay}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildEquation() {
    final buf = StringBuffer('y(k) = ');
    final coeffs = best.coefficients ?? [];
    final regressors = best.regressors;

    for (var i = 0; i < regressors.length && i < coeffs.length; i++) {
      if (i > 0) {
        buf.write(coeffs[i] >= 0 ? ' + ' : ' - ');
      } else if (coeffs[i] < 0) {
        buf.write('-');
      }
      final c = coeffs[i].abs();
      buf.write(c.toStringAsFixed(6));
      buf.write(' * ');
      buf.write(_regressorToString(regressors[i]));
      if (i < regressors.length - 1 && (i + 1) % 2 == 0) {
        buf.write('\n       ');
      }
    }

    final intercept = best.intercept;
    if (intercept.abs() > 1e-12) {
      final wroteTerm = regressors.isNotEmpty && coeffs.isNotEmpty;
      if (wroteTerm) {
        buf.write(intercept >= 0 ? ' + ' : ' - ');
      } else if (intercept < 0) {
        buf.write('-');
      }
      buf.write(intercept.abs().toStringAsFixed(6));
    }

    return buf.toString();
  }

  String _regressorToString(Regressor reg) {
    final parts = <String>[];
    for (final ct in reg.components) {
      final t = ct.term;
      // A term referencing the output column is an autoregressive
      // (feedback) term — y(k-d) — regardless of whether it sits in the
      // numerator or the denominator of a rational model.
      final name = (t.isDenominator || t.variable == outputCol)
          ? 'y'
          : 'u${t.variable}';
      final delay = t.delay;
      final exp = ct.exponent;
      var s = '$name(k-$delay)';
      if (exp != 1.0) s += '^${exp.toStringAsFixed(1)}';
      parts.add(s);
    }
    return parts.join('·');
  }
}

// ─── ERR table ───────────────────────────────────────────────

class _ERRTable extends StatelessWidget {
  final List<double> err;
  final List<double> coefficients;
  final List<String> labels;

  const _ERRTable({
    required this.err,
    required this.coefficients,
    this.labels = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'ERR & Coefficients',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  AppColors.surfaceVariant,
                ),
                columnSpacing: 32,
                headingTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                dataTextStyle: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary,
                ),
                columns: const [
                  DataColumn(label: Text('Regressor')),
                  DataColumn(label: Text('ERR (%)')),
                  DataColumn(label: Text('Cumulative (%)')),
                  DataColumn(label: Text('Coefficient')),
                ],
                rows: List.generate(err.length, (i) {
                  final cumulative = err
                      .sublist(0, i + 1)
                      .fold(0.0, (s, e) => s + e);
                  final label = (labels.isNotEmpty && i < labels.length)
                      ? labels[i]
                      : 'R${i + 1}';
                  return DataRow(
                    cells: [
                      DataCell(Text(label)),
                      DataCell(Text((err[i] * 100).toStringAsFixed(4))),
                      DataCell(
                        Text((cumulative * 100).toStringAsFixed(4)),
                      ),
                      DataCell(
                        Text(
                          i < coefficients.length
                              ? coefficients[i].toStringAsExponential(4)
                              : '-',
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Autocorrelation card ─────────────────────────────────────

class _AutocorrelationCard extends StatelessWidget {
  final List<double> autocorr;

  const _AutocorrelationCard({required this.autocorr});

  @override
  Widget build(BuildContext context) {
    final confBound =
        1.96 / math.sqrt(autocorr.isNotEmpty ? 100 : 1); // Approximate

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.waves, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Residual Autocorrelation',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _AutocorrelationPainter(autocorr, confBound),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutocorrelationPainter extends CustomPainter {
  final List<double> data;
  final double confBound;

  _AutocorrelationPainter(this.data, this.confBound);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final barWidth = size.width / (data.length + 1);
    final midY = size.height / 2;

    // Confidence bounds
    final confPaint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final confY = confBound * midY;
    canvas.drawRect(
      Rect.fromLTRB(0, midY - confY, size.width, midY + confY),
      confPaint,
    );

    // Center line
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = AppColors.gray700
        ..strokeWidth = 1,
    );

    // Bars
    final barPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < data.length; i++) {
      final x = (i + 0.5) * barWidth;
      final h = data[i] * midY;
      final isOutside = data[i].abs() > confBound;
      barPaint.color = isOutside ? AppColors.error : AppColors.accent;

      if (h > 0) {
        canvas.drawRect(Rect.fromLTRB(x - 2, midY - h, x + 2, midY), barPaint);
      } else {
        canvas.drawRect(Rect.fromLTRB(x - 2, midY, x + 2, midY - h), barPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Run summary ──────────────────────────────────────────────

class _RunSummary extends StatelessWidget {
  final int generations;
  final Duration elapsed;
  final int stagnation;

  const _RunSummary({
    required this.generations,
    required this.elapsed,
    required this.stagnation,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.list_alt,
                  size: 16,
                  color: AppColors.accent,
                ),
                SizedBox(width: 8),
                Text(
                  'Run Summary',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Total Generations', '$generations'),
            _row(
              'Duration',
              '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s',
            ),
            _row('Final Stagnation', '$stagnation'),
            _row(
              'Avg Time/Gen',
              '${(elapsed.inMilliseconds / (generations.clamp(1, 999999))).toStringAsFixed(1)} ms',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
