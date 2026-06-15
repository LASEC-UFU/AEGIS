import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:math' as math;

import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/stat_card.dart';
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
    } else {
      best = notifier.engine?.bestChromosome;
    }

    if (snap == null || best == null || !best.isEvaluated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.bar_chart,
                size: 64,
                color: AppColors.gray700,
              ),
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
        : ref.read(outputIndexProvider);

    // R²/RMSE for train/val come from the live snapshot for the Dart engine,
    // or from the final best-model JSON for the C++ engine.
    final r2Train = notifier.usingCpp
        ? (bestModelJson?['r2Train'] as num?)?.toDouble() ?? double.nan
        : snap.bestModelR2;
    final rmseTrain = notifier.usingCpp
        ? (bestModelJson?['rmseTrain'] as num?)?.toDouble() ?? double.nan
        : snap.bestModelRMSE;
    final r2Test = (bestModelJson?['r2Test'] as num?)?.toDouble();
    final rmseTest = (bestModelJson?['rmseTest'] as num?)?.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identified Model'),
        actions: [
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
    maxDelay: (j['maxDelay'] as num?)?.toInt() ?? 0,
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

  const _ERRTable({required this.err, required this.coefficients});

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
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('ERR (%)')),
                  DataColumn(label: Text('Cumulative (%)')),
                  DataColumn(label: Text('Coefficient')),
                ],
                rows: List.generate(err.length, (i) {
                  final cumulative = err
                      .sublist(0, i + 1)
                      .fold(0.0, (s, e) => s + e);
                  return DataRow(
                    cells: [
                      DataCell(Text('${i + 1}')),
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
