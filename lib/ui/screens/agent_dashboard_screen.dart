import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../../agent/tunable_parameter.dart';
import '../../agent/generation_snapshot.dart';
import '../../services/optimization_agent.dart';

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
                Icons.timeline,
                size: 14,
                color: AppColors.accent,
              ),
              label: Text(
                _phaseLabel(snap.phase, snap.phaseName),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          const SizedBox(width: 8),
          if (snap != null)
            Chip(
              avatar: const Icon(
                Icons.psychology,
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

  static const _phaseShortNames = [
    'Fase 1: Exploração Estrutural',
    'Fase 2: Expansão Não Linear',
    'Fase 3: Parcimônia & Validação',
    'Fase 4: Refinamento Local',
  ];

  String _phaseLabel(int phase, String phaseName) {
    if (phase >= 0 && phase < _phaseShortNames.length) {
      return _phaseShortNames[phase];
    }
    return phaseName.isNotEmpty ? phaseName : 'Fase $phase';
  }

  static const _islandRoleLabels = {
    'balanced': 'Balanceada',
    'parsimony': 'Parcimônia',
    'free_run_fidelity': 'Fidelidade Free-Run',
    'stability': 'Estabilidade',
  };

  String _islandRoleLabel(String role) => _islandRoleLabels[role] ?? role;

  Widget _buildEmpty() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildAgentSelector(),
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Icon(Icons.psychology, size: 64, color: AppColors.gray700),
                const SizedBox(height: 16),
                const Text(
                  'O dashboard sera ativado durante a evolucao',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
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
              _buildFitnessBreakdown(snap),
              const SizedBox(height: 20),
              _buildIslandMonitor(snap),
              const SizedBox(height: 20),
              _buildERRChart(snap),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // Right: Tuning panel + agent activity log
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildAgentSelector(),
              const SizedBox(height: 20),
              _buildTuningPanel(params),
              const SizedBox(height: 20),
              _buildAgentActivityLog(),
            ],
          ),
        ),
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
        _buildFitnessBreakdown(snap),
        const SizedBox(height: 20),
        _buildAgentSelector(),
        const SizedBox(height: 20),
        _buildTuningPanel(params),
        const SizedBox(height: 20),
        _buildAgentActivityLog(),
        const SizedBox(height: 20),
        _buildIslandMonitor(snap),
        const SizedBox(height: 20),
        _buildERRChart(snap),
      ],
    );
  }

  Widget _buildAgentSelector() {
    final mode = ref.watch(agentModeProvider);
    final notifier = ref.read(engineProvider.notifier);
    final description = switch (mode) {
      AgentMode.off => 'Monitoramento automatico desativado.',
      AgentMode.local =>
        'Politica adaptativa local, sem rede, com uma decisao conservadora '
            'a cada janela de 25 geracoes.',
      AgentMode.fuzzy =>
        'Politica fuzzy local interpretavel (regras Takagi-Sugeno), sem rede; '
            'recusa agir quando a ativacao das regras e insuficiente.',
      AgentMode.remote =>
        'Supervisor remoto via Claude API. Requer ANTHROPIC_API_KEY.',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.memory, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Supervisor adaptativo',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<AgentMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: AgentMode.off,
                  icon: Icon(Icons.power_settings_new, size: 16),
                  label: Text('Desligado'),
                ),
                ButtonSegment(
                  value: AgentMode.local,
                  icon: Icon(Icons.computer, size: 16),
                  label: Text('Local'),
                ),
                ButtonSegment(
                  value: AgentMode.fuzzy,
                  icon: Icon(Icons.rule, size: 16),
                  label: Text('Fuzzy'),
                ),
                ButtonSegment(
                  value: AgentMode.remote,
                  icon: Icon(Icons.cloud_outlined, size: 16),
                  label: Text('Remoto'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                ref.read(engineProvider.notifier).setAgentMode(selection.first);
              },
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
            if (mode == AgentMode.remote && !notifier.agentAvailable) ...[
              const SizedBox(height: 8),
              const Text(
                'Chave remota nao encontrada; o motor continuara sem '
                'sugestoes ate a chave ser configurada.',
                style: TextStyle(color: AppColors.warning, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Agent activity log ──────────────────────────────────────

  Widget _buildAgentActivityLog() {
    final notifier = ref.read(engineProvider.notifier);
    final log = notifier.getTuningLog();
    final decisions = notifier.agentDecisions;
    final counts = <String, int>{};
    for (final d in decisions) {
      counts[d.status] = (counts[d.status] ?? 0) + 1;
    }
    final lastDecision = decisions.isEmpty ? null : decisions.last;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Agent Activity Log',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (decisions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Decisões do agente: '
                  '${counts.entries.map((e) => '${e.key} ${e.value}').join(' · ')}'
                  '${lastDecision == null ? '' : '\nÚltima (geração ${lastDecision.generation}): '
                      '${lastDecision.status} — ${lastDecision.rationale}'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            if (log.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No tuning actions yet. The agent will appear here as it '
                  'adjusts parameters during the run.',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: log.length,
                  reverse: true,
                  itemBuilder: (context, i) {
                    // Show newest entries first.
                    final entry = log[log.length - 1 - i];
                    final accepted = entry['accepted'] == true;
                    final param = entry['param']?.toString() ?? '?';
                    final newValue = (entry['newValue'] as num?)?.toDouble();
                    final reason = entry['reason']?.toString() ?? '';
                    final rejection =
                        entry['rejectionReason']?.toString() ?? '';
                    final gen = entry['generation']?.toString() ?? '?';
                    final source = entry['source']?.toString() ?? '';
                    final outcome = entry['outcome']?.toString() ?? '';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            accepted ? Icons.check_circle : Icons.cancel,
                            size: 14,
                            color: accepted
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gen $gen: $param → '
                                  '${newValue?.toStringAsFixed(4) ?? '-'}'
                                  '${source.isEmpty ? '' : '  [$source]'}'
                                  '${accepted && outcome.isNotEmpty && outcome != 'n/a' ? '  · $outcome' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (reason.isNotEmpty)
                                  Text(
                                    reason,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                if (!accepted && rejection.isNotEmpty)
                                  Text(
                                    'Rejected: $rejection',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.error,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
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
                Icon(Icons.speed, size: 16, color: AppColors.accent),
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
                _IndicatorTile(
                  'Free-Run RMSE',
                  snap.freeRunRmse != null
                      ? snap.freeRunRmse!.toStringAsFixed(6)
                      : '—',
                  AppColors.textPrimary,
                ),
                _IndicatorTile(
                  'Input Contribution',
                  snap.inputContributionRatio != null
                      ? '${(snap.inputContributionRatio! * 100).toStringAsFixed(1)}%'
                      : '—',
                  snap.inputContributionRatio != null &&
                          snap.inputContributionRatio! < 0.3
                      ? AppColors.warning
                      : AppColors.success,
                ),
                _IndicatorTile(
                  'Residual×Input Corr',
                  snap.residualInputCorr != null
                      ? snap.residualInputCorr!.toStringAsFixed(4)
                      : '—',
                  snap.residualInputCorr != null &&
                          snap.residualInputCorr!.abs() > 0.2
                      ? AppColors.warning
                      : AppColors.textPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Fitness breakdown ────────────────────────────────────────

  Widget _buildFitnessBreakdown(GenerationSnapshot snap) {
    final fb = snap.fitnessBreakdown;
    if (fb.isEmpty) return const SizedBox.shrink();

    const labels = {
      'rmse': 'RMSE',
      'bic_term': 'BIC (α)',
      'denom_term': 'Denominador (β)',
      'complexity_term': 'Complexidade (γ)',
      'exponent_term': 'Expoente (δ)',
      'stability_term': 'Estabilidade (η)',
      'no_input_term': 'Sem Entrada (ζ)',
      'free_run_term': 'Free-Run (θ)',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.donut_small, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Composição do Fitness',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...labels.entries.map((e) {
              final value = fb[e.key];
              if (value == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        e.value,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value.toStringAsFixed(6),
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (snap.bestContextsSurvived > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text(
                      'Robustez (campeão)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'sobreviveu a ${snap.bestContextsSurvived} contexto(s)'
                      '${snap.bestWorstFitnessSeen != null ? ' · pior fitness: ${snap.bestWorstFitnessSeen!.toStringAsFixed(6)}' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
              Icon(Icons.tune, size: 32, color: AppColors.gray600),
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
                const Icon(Icons.tune, size: 16, color: AppColors.accent),
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
                  icon: const Icon(Icons.rotate_left, size: 14),
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
                Icon(Icons.language, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Text(
                  'Island Monitor',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (snap.islandRoles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(snap.islandRoles.length, (i) {
                  return Chip(
                    label: Text(
                      'I$i: ${_islandRoleLabel(snap.islandRoles[i])}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: AppColors
                        .chartPalette[i % AppColors.chartPalette.length]
                        .withValues(alpha: 0.18),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }),
              ),
            ],
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
                Icon(Icons.bar_chart, size: 16, color: AppColors.accent),
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
              height: 180,
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
                        reservedSize: 56,
                        getTitlesWidget: (v, m) {
                          final i = v.toInt();
                          final labels = snap.bestModelTermLabels;
                          final label = (labels.isNotEmpty && i < labels.length)
                              ? labels[i]
                              : 'R${i + 1}';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
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
