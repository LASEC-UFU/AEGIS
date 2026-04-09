import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/stat_card.dart';
import '../../engine/de/de_engine.dart' show EngineState;

/// Real-time evolution monitoring screen.
class EvolutionScreen extends ConsumerWidget {
  const EvolutionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineState = ref.watch(engineProvider);
    final snapshot = engineState.latestSnapshot;
    final isRunning = engineState.state == EngineState.running;
    final isPaused = engineState.state == EngineState.paused;
    final isIdle = engineState.state == EngineState.idle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evolution Monitor'),
        actions: [
          if (snapshot != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  engineState.state.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _stateColor(engineState.state),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Control bar
          _ControlBar(
            isRunning: isRunning,
            isPaused: isPaused,
            isIdle: isIdle,
            hasData: ref.watch(loadedDataProvider) != null,
            onStart: () {
              final notifier = ref.read(engineProvider.notifier);
              if (isIdle) notifier.initialize();
              notifier.start();
            },
            onPause: () => ref.read(engineProvider.notifier).pause(),
            onResume: () => ref.read(engineProvider.notifier).resume(),
            onStop: () => ref.read(engineProvider.notifier).stop(),
          ),
          const Divider(height: 1),
          // Dashboard
          Expanded(
            child: snapshot == null
                ? const _EmptyState()
                : _EvolutionDashboard(ref: ref),
          ),
        ],
      ),
    );
  }

  Color _stateColor(EngineState state) {
    return switch (state) {
      EngineState.running => AppColors.success,
      EngineState.paused => AppColors.warning,
      EngineState.stopped => AppColors.error,
      EngineState.completed => AppColors.accent,
      EngineState.idle => AppColors.textTertiary,
    };
  }
}

// ─── Control bar ──────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  final bool isRunning, isPaused, isIdle, hasData;
  final VoidCallback onStart, onPause, onResume, onStop;

  const _ControlBar({
    required this.isRunning,
    required this.isPaused,
    required this.isIdle,
    required this.hasData,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: AppColors.backgroundDeep,
      child: Row(
        children: [
          if (!isRunning && !isPaused)
            ElevatedButton.icon(
              onPressed: hasData ? onStart : null,
              icon: const Icon(LucideIcons.play, size: 16),
              label: const Text('Start'),
            ),
          if (isRunning)
            OutlinedButton.icon(
              onPressed: onPause,
              icon: const Icon(LucideIcons.pause, size: 16),
              label: const Text('Pause'),
            ),
          if (isPaused) ...[
            ElevatedButton.icon(
              onPressed: onResume,
              icon: const Icon(LucideIcons.play, size: 16),
              label: const Text('Resume'),
            ),
            const SizedBox(width: 8),
          ],
          if (isRunning || isPaused) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(LucideIcons.square, size: 16),
              label: const Text('Stop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
            ),
          ],
          if (!hasData)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'Load data first',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.activity, size: 64, color: AppColors.gray700),
          const SizedBox(height: 16),
          Text(
            'No evolution data yet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Load data and start the engine to see real-time metrics',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Evolution dashboard ──────────────────────────────────────

class _EvolutionDashboard extends StatelessWidget {
  final WidgetRef ref;

  const _EvolutionDashboard({required this.ref});

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(snapshotProvider)!;
    final history = ref.watch(fitnessHistoryProvider);
    final elapsed = ref.watch(engineProvider).elapsed;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 900 ? 4 : 2;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top KPIs
              GridView.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StatCard(
                    label: 'GENERATION',
                    value: '${snap.generation}',
                    icon: LucideIcons.hash,
                    valueColor: AppColors.accent,
                  ),
                  StatCard(
                    label: 'BEST FITNESS (BIC)',
                    value: snap.bestFitness.toStringAsFixed(4),
                    icon: LucideIcons.trophy,
                    valueColor: AppColors.success,
                  ),
                  StatCard(
                    label: 'R²',
                    value: snap.bestModelR2.toStringAsFixed(6),
                    icon: LucideIcons.target,
                    valueColor: snap.bestModelR2 > 0.95
                        ? AppColors.success
                        : snap.bestModelR2 > 0.8
                        ? AppColors.warning
                        : AppColors.error,
                  ),
                  StatCard(
                    label: 'ELAPSED',
                    value: _formatDuration(elapsed),
                    icon: LucideIcons.timer,
                    subtitle: '${snap.stagnationCounter} stall',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Fitness chart
              _FitnessChart(history: history),
              const SizedBox(height: 20),
              // Detail metrics
              GridView.count(
                crossAxisCount: constraints.maxWidth >= 900 ? 3 : 1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: constraints.maxWidth >= 900 ? 2.5 : 3.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MetricsCard(
                    title: 'Population',
                    icon: LucideIcons.users,
                    metrics: {
                      'Mean Fitness': snap.meanFitness.toStringAsFixed(4),
                      'Std Dev': snap.stdDevFitness.toStringAsFixed(4),
                      'Unique Structs': '${snap.uniqueStructures}',
                      'Success Rate':
                          '${(snap.successRate * 100).toStringAsFixed(1)}%',
                    },
                  ),
                  _MetricsCard(
                    title: 'Best Model',
                    icon: LucideIcons.sparkles,
                    metrics: {
                      'Complexity': '${snap.bestModelComplexity} regressors',
                      'Max Degree': '${snap.bestModelMaxDegree}',
                      'Max Delay': '${snap.bestModelMaxDelay}',
                      'RMSE': snap.bestModelRMSE.toStringAsFixed(6),
                    },
                  ),
                  _MetricsCard(
                    title: 'Convergence',
                    icon: LucideIcons.trendingDown,
                    metrics: {
                      'Improvement': snap.improvementRelative
                          .toStringAsExponential(2),
                      'Rate (5g)': snap.improvementRate5.toStringAsExponential(
                        2,
                      ),
                      'Rate (20g)': snap.improvementRate20
                          .toStringAsExponential(2),
                      'Variance': snap.populationVariance.toStringAsExponential(
                        2,
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }
}

// ─── Fitness chart ────────────────────────────────────────────

class _FitnessChart extends StatelessWidget {
  final List<double> history;

  const _FitnessChart({required this.history});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(LucideIcons.lineChart, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Fitness Evolution',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: history.length < 2
                  ? const Center(
                      child: Text(
                        'Waiting for data...',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: AppColors.gray750,
                            strokeWidth: 0.5,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (v, meta) => Text(
                                v.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              interval: (history.length / 5)
                                  .ceilToDouble()
                                  .clamp(1, double.infinity),
                              getTitlesWidget: (v, meta) => Text(
                                v.toInt().toString(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: List.generate(
                              history.length,
                              (i) => FlSpot(i.toDouble(), history[i]),
                            ),
                            isCurved: true,
                            curveSmoothness: 0.2,
                            color: AppColors.accent,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.accent.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => AppColors.surfaceElevated,
                            tooltipBorder: const BorderSide(
                              color: AppColors.gray700,
                            ),
                            getTooltipItems: (spots) => spots.map((s) {
                              return LineTooltipItem(
                                'Gen ${s.x.toInt()}\n${s.y.toStringAsFixed(4)}',
                                const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Metrics card ─────────────────────────────────────────────

class _MetricsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, String> metrics;

  const _MetricsCard({
    required this.title,
    required this.icon,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...metrics.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
