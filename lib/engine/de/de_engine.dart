import 'dart:math' as math;

import '../../core/math/matrix.dart';
import '../../core/types/chromosome.dart';
import 'island.dart';
import 'migration.dart';
import 'chromosome_factory.dart';
import 'population.dart';
import '../fitness/bic_fitness.dart';
import '../fitness/fitness_evaluator.dart';
import '../identification/model_validator.dart';
import '../stopping/stopping_criterion.dart';
import '../../agent/generation_snapshot.dart';
import '../../agent/generation_history.dart';
import '../../agent/tunable_parameter.dart';

/// Engine state for UI binding.
enum EngineState { idle, running, paused, stopped, completed }

/// Main DE engine — orchestrates islands, migration, and reporting.
///
/// Runs synchronously in batches (designed to yield to the event loop
/// between batches for UI updates in the browser).
class DEEngine {
  // ── Configuration ──
  final int numIslands;
  final int generationsPerBatch;
  final ParameterRegistry parameters;
  late final ChromosomeFactory chromosomeFactory;
  late final FitnessEvaluator fitnessEvaluator;
  late final Migration migration;
  late final CompositeCriterion stoppingCriteria;

  // ── State ──
  final List<Island> islands = [];
  final GenerationHistory history = GenerationHistory();
  EngineState state = EngineState.idle;
  int _generation = 0;
  DateTime? _startTime;
  double _previousBestFitness = double.infinity;
  int _globalStagnation = 0;

  // ── Data ──
  Matrix? _normalizedData;
  Matrix? _validationData;
  int _outputCol = 0;

  // ── Callback ──
  void Function(GenerationSnapshot)? onGenerationComplete;
  void Function(EngineState)? onStateChanged;

  DEEngine({
    this.numIslands = 3,
    this.generationsPerBatch = 10,
    ParameterRegistry? parameters,
  }) : parameters = parameters ?? ParameterRegistry() {
    this.parameters.registerDefaults();
    fitnessEvaluator = const BicFitness();
  }

  /// Initialize with data and start islands.
  void initialize({
    required Matrix normalizedData,
    Matrix? validationData,
    required int outputCol,
    required int numVariables,
  }) {
    _normalizedData = normalizedData;
    _validationData = validationData;
    _outputCol = outputCol;
    _generation = 0;
    _globalStagnation = 0;
    _previousBestFitness = double.infinity;
    history.clear();

    chromosomeFactory = ChromosomeFactory(
      numVariables: numVariables,
      maxRegressors: parameters.get('maxRegressors')!.currentValue.toInt(),
      maxExponent: parameters.get('maxExponent')!.currentValue,
      maxDelay: parameters.get('maxDelay')!.currentValue.toInt(),
    );

    migration = Migration(
      interval: parameters.get('migrationInterval')!.currentValue.toInt(),
      rate: parameters.get('migrationRate')!.currentValue,
    );

    stoppingCriteria = CompositeCriterion([
      MaxGenerations(5000),
      StagnationLimit(parameters.get('stagnationLimit')!.currentValue.toInt()),
      PopulationVariance(1e-10),
      RelativeImprovement(1e-8),
    ]);

    // Create islands
    islands.clear();
    final popSize = parameters.get('populationSize')!.currentValue.toInt();
    for (var i = 0; i < numIslands; i++) {
      islands.add(
        Island(
          id: i,
          config: IslandConfig(
            populationSize: popSize,
            mutationFactor: parameters.get('mutationFactor')!.currentValue,
            crossoverRate: parameters.get('crossoverRate')!.currentValue,
            elitismCount: parameters.get('elitismCount')!.currentValue.toInt(),
          ),
          chromosomeFactory: chromosomeFactory,
          fitnessEvaluator: fitnessEvaluator,
          seed: DateTime.now().microsecondsSinceEpoch + i * 104729,
        ),
      );
    }

    state = EngineState.idle;
    onStateChanged?.call(state);
  }

  /// Run one batch of generations. Returns true if should continue.
  bool runBatch() {
    if (_normalizedData == null || islands.isEmpty) return false;
    if (state == EngineState.completed || state == EngineState.stopped) {
      return false;
    }

    _startTime ??= DateTime.now();
    state = EngineState.running;
    onStateChanged?.call(state);

    for (var b = 0; b < generationsPerBatch; b++) {
      // Run one generation on each island
      for (final island in islands) {
        island.runGenerations(1, _normalizedData!, _outputCol);
      }

      // Migration
      if (migration.shouldMigrate(_generation)) {
        migration.migrate(islands);
      }

      _generation++;

      // Collect snapshot
      final snapshot = _buildSnapshot();
      history.addSnapshot(snapshot);
      onGenerationComplete?.call(snapshot);

      // Check stopping criteria
      final ctx = StoppingContext(
        generation: _generation,
        stagnationCounter: _globalStagnation,
        bestFitness: snapshot.bestFitness,
        previousBestFitness: _previousBestFitness,
        stats: PopulationStats(
          bestFitness: snapshot.bestFitness,
          worstFitness: snapshot.worstFitness,
          meanFitness: snapshot.meanFitness,
          medianFitness: snapshot.medianFitness,
          stdDevFitness: snapshot.stdDevFitness,
          q1: snapshot.q1Fitness,
          q3: snapshot.q3Fitness,
          uniqueStructures: snapshot.uniqueStructures,
          structureEntropy: snapshot.structureEntropy,
          evaluatedCount: islands.fold(0, (s, i) => s + i.population.size),
          totalCount: islands.fold(0, (s, i) => s + i.population.size),
        ),
        elapsedTime: DateTime.now().difference(_startTime!),
        fitnessHistory: history.fitnessHistory,
      );

      if (stoppingCriteria.shouldStop(ctx)) {
        state = EngineState.completed;
        onStateChanged?.call(state);
        return false;
      }

      // Update global stagnation
      if (snapshot.bestFitness < _previousBestFitness - 1e-12) {
        _globalStagnation = 0;
      } else {
        _globalStagnation++;
      }
      _previousBestFitness = snapshot.bestFitness;
    }

    return true;
  }

  /// Pause the engine.
  void pause() {
    if (state == EngineState.running) {
      state = EngineState.paused;
      onStateChanged?.call(state);
    }
  }

  /// Stop the engine.
  void stop() {
    state = EngineState.stopped;
    onStateChanged?.call(state);
  }

  /// Apply a tuning action from the agent.
  void applyTuning(String paramName, double newValue, {String? reason}) {
    final param = parameters.get(paramName);
    if (param == null) return;
    final oldValue = param.currentValue;
    parameters.update(paramName, newValue);
    history.addTuningAction(
      TuningAction(
        parameterName: paramName,
        oldValue: oldValue,
        newValue: newValue,
        generation: _generation,
        reason: reason,
      ),
    );
  }

  /// Best model found across all islands.
  Chromosome? get bestChromosome {
    Chromosome? best;
    for (final island in islands) {
      final ib = island.population.best;
      if (best == null || (ib.isEvaluated && ib.fitness < best.fitness)) {
        best = ib;
      }
    }
    return best;
  }

  GenerationSnapshot _buildSnapshot() {
    final islandSnaps = islands.map((i) => i.snapshot()).toList();

    // Global stats
    var globalBest = double.infinity;
    var globalWorst = double.negativeInfinity;
    var sumFit = 0.0;
    var count = 0;

    for (final snap in islandSnaps) {
      globalBest = math.min(globalBest, snap.stats.bestFitness);
      globalWorst = math.max(globalWorst, snap.stats.worstFitness);
      sumFit += snap.stats.meanFitness * snap.stats.evaluatedCount;
      count += snap.stats.evaluatedCount;
      // Add individual fitnesses for quartiles
    }

    final meanFit = count > 0 ? sumFit / count : double.infinity;

    // Find global best chromosome
    Chromosome? bestChr;
    for (final snap in islandSnaps) {
      if (bestChr == null || snap.bestChromosome.fitness < (bestChr.fitness)) {
        bestChr = snap.bestChromosome;
      }
    }

    // Success rate
    final avgSuccess = islandSnaps.isEmpty
        ? 0.0
        : islandSnaps.fold(0.0, (s, i) => s + i.successRate) /
              islandSnaps.length;

    // Diversity
    final structureSet = <int>{};
    for (final island in islands) {
      for (final ind in island.population.individuals) {
        if (ind.isEvaluated) structureSet.add(ind.structuralHash);
      }
    }

    // Improvement rates
    double impAbs = 0, impRel = 0, impRate5 = 0, impRate20 = 0;
    if (history.length > 0) {
      final prev = history.fitnessHistory.last;
      impAbs = prev - globalBest;
      impRel = prev.abs() > 1e-30 ? impAbs / prev.abs() : 0;
    }
    if (history.length >= 5) impRate5 = history.improvementRate(5);
    if (history.length >= 20) impRate20 = history.improvementRate(20);

    // Validation metrics
    double? valRMSE;
    if (_validationData != null && bestChr != null && bestChr.isEvaluated) {
      valRMSE = ModelValidator.rmse(bestChr, _validationData!, _outputCol);
    }

    // Best model training metrics
    double trainRMSE = double.infinity;
    double trainR2 = 0;
    if (bestChr != null && bestChr.isEvaluated && _normalizedData != null) {
      trainRMSE = ModelValidator.rmse(bestChr, _normalizedData!, _outputCol);
      trainR2 = ModelValidator.r2(bestChr, _normalizedData!, _outputCol);
    }

    // Residual autocorrelation
    List<double>? resAutocorr;
    if (bestChr != null && bestChr.isEvaluated && _normalizedData != null) {
      final res = ModelValidator.residuals(
        bestChr,
        _normalizedData!,
        _outputCol,
      );
      if (res.rows > 20) {
        resAutocorr = res.autocorrelation(20);
      }
    }

    final medianFit = meanFit; // Approximate (exact would need all fitnesses)
    final stdDev = islandSnaps.isEmpty
        ? 0.0
        : islandSnaps.fold(0.0, (s, i) => s + i.stats.stdDevFitness) /
              islandSnaps.length;

    return GenerationSnapshot(
      generation: _generation,
      elapsed: _startTime != null
          ? DateTime.now().difference(_startTime!)
          : Duration.zero,
      bestFitness: globalBest,
      worstFitness: globalWorst,
      meanFitness: meanFit,
      medianFitness: medianFit,
      stdDevFitness: stdDev,
      q1Fitness: islandSnaps.isEmpty
          ? double.infinity
          : islandSnaps.first.stats.q1,
      q3Fitness: islandSnaps.isEmpty
          ? double.infinity
          : islandSnaps.first.stats.q3,
      improvementAbsolute: impAbs,
      improvementRelative: impRel,
      improvementRate5: impRate5,
      improvementRate20: impRate20,
      stagnationCounter: _globalStagnation,
      uniqueStructures: structureSet.length,
      structureEntropy: islandSnaps.isEmpty
          ? 0
          : islandSnaps.first.stats.structureEntropy,
      phenotypicDiversity: stdDev,
      regressorFrequency: {},
      populationVariance: stdDev * stdDev,
      successRate: avgSuccess,
      successRateHistory: history.successRateHistory(),
      bestModelComplexity: bestChr?.numRegressors ?? 0,
      bestModelMaxDegree: bestChr?.maxDegree ?? 0,
      bestModelMaxDelay: bestChr?.maxDelay ?? 0,
      bestModelERR: bestChr?.err ?? [],
      bestModelRMSE: trainRMSE,
      bestModelValidationRMSE: valRMSE,
      bestModelR2: trainR2,
      residualAutocorrelation: resAutocorr,
      islandSnapshots: islandSnaps,
      migrationImpact: null,
    );
  }
}
