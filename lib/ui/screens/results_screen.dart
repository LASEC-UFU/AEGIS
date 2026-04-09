import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:math' as math;

import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/stat_card.dart';
import '../../engine/de/de_engine.dart';

/// Results screen — shows final model, equation, and validation.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eState = ref.watch(engineProvider);
    final snap = eState.latestSnapshot;
    final engine = ref.watch(engineProvider.notifier).engine;
    final best = engine?.bestChromosome;

    if (snap == null || best == null || !best.isEvaluated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.fileBarChart,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identified Model'),
        actions: [
          if (eState.state == EngineState.completed)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Chip(
                avatar: Icon(
                  LucideIcons.checkCircle,
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
                _ModelEquationCard(best: best),
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
                          value: best.fitness.toStringAsFixed(4),
                          icon: LucideIcons.trophy,
                          valueColor: AppColors.success,
                        ),
                        StatCard(
                          label: 'R²',
                          value: snap.bestModelR2.toStringAsFixed(6),
                          icon: LucideIcons.target,
                          valueColor: snap.bestModelR2 > 0.95
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                        StatCard(
                          label: 'RMSE',
                          value: snap.bestModelRMSE.toStringAsFixed(6),
                          icon: LucideIcons.ruler,
                        ),
                        StatCard(
                          label: 'REGRESSORS',
                          value: '${best.numRegressors}',
                          icon: LucideIcons.layers,
                          subtitle:
                              'Max degree ${best.maxDegree}, delay ${best.maxDelay}',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                // ERR contributions
                _ERRTable(
                  err: best.err ?? [],
                  coefficients: best.coefficients ?? [],
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

// ─── Model equation card ──────────────────────────────────────

class _ModelEquationCard extends StatelessWidget {
  final dynamic best;

  const _ModelEquationCard({required this.best});

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
                  LucideIcons.functionSquare,
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
    final coeffs = best.coefficients;
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

    return buf.toString();
  }

  String _regressorToString(dynamic reg) {
    final terms = reg.terms;
    final parts = <String>[];
    for (final ct in terms) {
      final t = ct.term;
      final name = t.isDenominator ? 'y' : 'u${t.variable}';
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
                Icon(LucideIcons.barChart, size: 16, color: AppColors.accent),
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
                Icon(LucideIcons.waves, size: 16, color: AppColors.accent),
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
                  LucideIcons.clipboardList,
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
