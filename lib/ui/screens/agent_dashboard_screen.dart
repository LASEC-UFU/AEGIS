import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../../agent/tunable_parameter.dart';
import '../../agent/generation_snapshot.dart';

/// Agent dashboard — exposes all indicators and tuning controls.
class AgentDashboardScreen extends ConsumerStatefulWidget {
  const AgentDashboardScreen({super.key});

  @override
  ConsumerState<AgentDashboardScreen> createState() =>
      _AgentDashboardScreenState();
}

class _AgentDashboardScreenState extends ConsumerState<AgentDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(snapshotProvider);
    final params = ref.watch(parameterRegistryProvider);
    final history = ref.watch(fitnessHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Dashboard'),
        actions: [
          if (snap != null)
            Chip(
              avatar: const Icon(
                LucideIcons.brain,
                size: 14,
                color: AppColors.accent,
              ),
              label: Text(
                'Gen ${snap.generation}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: snap == null
          ? _buildEmpty()
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: isWide
                      ? _buildWideLayout(snap, params, history)
                      : _buildNarrowLayout(snap, params, history),
                );
              },
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.brainCircuit, size: 64, color: AppColors.gray700),
          const SizedBox(height: 16),
          const Text(
            'Agent dashboard will activate during evolution',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(
    GenerationSnapshot snap,
    ParameterRegistry? params,
    List<double> history,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Indicators
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildIndicatorsGrid(snap),
              const SizedBox(height: 20),
              _buildIslandMonitor(snap),
              const SizedBox(height: 20),
              _buildERRChart(snap),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // Right: Tuning panel
        Expanded(flex: 2, child: _buildTuningPanel(params)),
      ],
    );
  }

  Widget _buildNarrowLayout(
    GenerationSnapshot snap,
    ParameterRegistry? params,
    List<double> history,
  ) {
    return Column(
      children: [
        _buildIndicatorsGrid(snap),
        const SizedBox(height: 20),
        _buildTuningPanel(params),
        const SizedBox(height: 20),
        _buildIslandMonitor(snap),
        const SizedBox(height: 20),
        _buildERRChart(snap),
      ],
    );
  }

  // ─── Indicators grid ──────────────────────────────────────

  Widget _buildIndicatorsGrid(GenerationSnapshot snap) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.gauge, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Indicators',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 18,
              children: [
                _IndicatorTile(
                  'Best Fitness',
                  snap.bestFitness.toStringAsFixed(4),
                  AppColors.success,
                ),
                _IndicatorTile(
                  'Mean Fitness',
                  snap.meanFitness.toStringAsFixed(4),
                  AppColors.textPrimary,
                ),
                _IndicatorTile(
                  'Std Dev',
                  snap.stdDevFitness.toStringAsFixed(4),
                  AppColors.textPrimary,
                ),
                _IndicatorTile(
                  'Success Rate',
                  '${(snap.successRate * 100).toStringAsFixed(1)}%',
                  snap.successRate > 0.1
                      ? AppColors.success
                      : AppColors.warning,
                ),
                _IndicatorTile(
                  'Unique Structures',
                  '${snap.uniqueStructures}',
                  AppColors.info,
                ),
                _IndicatorTile(
                  'Entropy',
                  snap.structureEntropy.toStringAsFixed(3),
                  AppColors.accent,
                ),
                _IndicatorTile(
                  'Pop Variance',
                  snap.populationVariance.toStringAsExponential(2),
                  AppColors.textPrimary,
                ),
                _IndicatorTile(
                  'Stagnation',
                  '${snap.stagnationCounter}',
                  snap.stagnationCounter > 50
                      ? AppColors.error
                      : AppColors.textPrimary,
                ),
                _IndicatorTile(
                  'RMSE',
                  snap.bestModelRMSE.toStringAsFixed(6),
                  AppColors.textPrimary,
                ),
                _IndicatorTile(
                  'R²',
                  snap.bestModelR2.toStringAsFixed(6),
                  snap.bestModelR2 > 0.95
                      ? AppColors.success
                      : AppColors.warning,
                ),
                _IndicatorTile(
                  'Complexity',
                  '${snap.bestModelComplexity}',
                  AppColors.textPrimary,
                ),
                _IndicatorTile(
                  'Max Delay',
                  '${snap.bestModelMaxDelay}',
                  AppColors.textPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tuning panel ───────────────────────────────────────────

  Widget _buildTuningPanel(ParameterRegistry? params) {
    if (params == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 32,
                color: AppColors.gray600,
              ),
              const SizedBox(height: 12),
              const Text(
                'Parameters will appear when engine is initialized',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final paramList = params.all;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.slidersHorizontal,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Tunable Parameters',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    for (final p in paramList) {
                      ref
                          .read(engineProvider.notifier)
                          .applyTuning(p.name, p.defaultValue, reason: 'Reset');
                    }
                    setState(() {});
                  },
                  icon: const Icon(LucideIcons.rotateCcw, size: 14),
                  label: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...paramList.map(
              (p) => _ParameterSlider(
                param: p,
                onChanged: (v) {
                  ref
                      .read(engineProvider.notifier)
                      .applyTuning(p.name, v, reason: 'User adjustment');
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Island monitor ─────────────────────────────────────────

  Widget _buildIslandMonitor(GenerationSnapshot snap) {
    final islands = snap.islandSnapshots;
    if (islands.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.globe2, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Island Monitor',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.surfaceElevated,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          'Island ${group.x}\n${rod.toY.toStringAsFixed(4)}',
                          const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (v, m) => Text(
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
                        getTitlesWidget: (v, m) => Text(
                          'I${v.toInt()}',
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
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppColors.gray750, strokeWidth: 0.5),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(islands.length, (i) {
                    final isnap = islands[i];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: isnap.stats.bestFitness,
                          width: 20,
                          color: AppColors
                              .chartPalette[i % AppColors.chartPalette.length],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ERR chart ──────────────────────────────────────────────

  Widget _buildERRChart(GenerationSnapshot snap) {
    final err = snap.bestModelERR as List<double>?;
    if (err == null || err.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.barChart3, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'ERR Contributions',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Total ERR: ${err.fold(0.0, (s, e) => s + e).toStringAsFixed(4)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, m) => Text(
                          'R${v.toInt() + 1}',
                          style: const TextStyle(
                            fontSize: 9,
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
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(err.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: err[i],
                          width: 14,
                          color: AppColors.accent.withValues(
                            alpha: 0.6 + 0.4 * err[i],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(3),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small widgets ──────────────────────────────────────────────

class _IndicatorTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _IndicatorTile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _ParameterSlider extends StatelessWidget {
  final TunableParameter param;
  final ValueChanged<double> onChanged;

  const _ParameterSlider({required this.param, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                param.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                param.type == ParameterType.integer
                    ? param.currentValue.toInt().toString()
                    : param.currentValue.toStringAsFixed(3),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: param.currentValue.clamp(param.minValue, param.maxValue),
              min: param.minValue,
              max: param.maxValue,
              divisions: param.type == ParameterType.integer
                  ? (param.maxValue - param.minValue).toInt()
                  : 100,
              onChanged: onChanged,
            ),
          ),
          Text(
            param.description,
            style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
