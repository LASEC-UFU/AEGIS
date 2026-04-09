import '../../core/math/matrix.dart';
import '../../core/types/types.dart';
import '../../core/random/xorshift128.dart';
import '../fitness/fitness_evaluator.dart';
import 'population.dart';
import 'chromosome_factory.dart';
import 'regressor_builder.dart';
import 'strategies/strategies.dart';

/// Configuration for one DE island.
class IslandConfig {
  final int populationSize;
  final double mutationFactor;
  final double crossoverRate;
  final int elitismCount;
  final String mutationStrategyName;
  final String crossoverStrategyName;

  const IslandConfig({
    this.populationSize = 50,
    this.mutationFactor = 0.5,
    this.crossoverRate = 0.9,
    this.elitismCount = 2,
    this.mutationStrategyName = 'JADE',
    this.crossoverStrategyName = 'Binomial',
  });

  IslandConfig copyWith({
    int? populationSize,
    double? mutationFactor,
    double? crossoverRate,
    int? elitismCount,
    String? mutationStrategyName,
    String? crossoverStrategyName,
  }) {
    return IslandConfig(
      populationSize: populationSize ?? this.populationSize,
      mutationFactor: mutationFactor ?? this.mutationFactor,
      crossoverRate: crossoverRate ?? this.crossoverRate,
      elitismCount: elitismCount ?? this.elitismCount,
      mutationStrategyName: mutationStrategyName ?? this.mutationStrategyName,
      crossoverStrategyName:
          crossoverStrategyName ?? this.crossoverStrategyName,
    );
  }
}

/// A DE island: runs an independent population with its own RNG.
///
/// This replaces the original pipeline architecture (TAMPIPELINE=3) with
/// fully independent populations that communicate only via migration.
class Island {
  final int id;
  IslandConfig config;
  late Population population;
  late final Xorshift128Plus rng;
  late MutationStrategy mutationStrategy;
  late CrossoverStrategy crossoverStrategy;
  final ChromosomeFactory chromosomeFactory;
  final FitnessEvaluator fitnessEvaluator;

  int generation = 0;
  int stagnationCounter = 0;
  double _previousBestFitness = double.infinity;
  int _successCount = 0;
  int _totalTrials = 0;

  // JADE-specific
  JadeMutation? _jade;

  Island({
    required this.id,
    required this.config,
    required this.chromosomeFactory,
    required this.fitnessEvaluator,
    int? seed,
  }) {
    rng = Xorshift128Plus(
      seed ?? (DateTime.now().microsecondsSinceEpoch + id * 7919),
    );
    _initStrategies();
    population = Population(
      chromosomeFactory.createPopulation(config.populationSize, rng),
    );
  }

  void _initStrategies() {
    switch (config.mutationStrategyName) {
      case 'JADE':
        _jade = JadeMutation(
          muF: config.mutationFactor,
          muCR: config.crossoverRate,
        );
        mutationStrategy = _jade!;
      case 'DE/rand/1':
        _jade = null;
        mutationStrategy = const DeRand1();
      default:
        _jade = JadeMutation(
          muF: config.mutationFactor,
          muCR: config.crossoverRate,
        );
        mutationStrategy = _jade!;
    }

    switch (config.crossoverStrategyName) {
      case 'Exponential':
        crossoverStrategy = const ExponentialCrossover();
      default:
        crossoverStrategy = const BinomialCrossover();
    }
  }

  /// Runs [count] generations of DE on the given data.
  ///
  /// [dataMatrix]: normalized input/output data (samples × variables).
  /// [outputCol]: column index of the target output in dataMatrix.
  ///
  /// Returns snapshot after all generations.
  IslandSnapshot runGenerations(int count, Matrix dataMatrix, int outputCol) {
    for (var g = 0; g < count; g++) {
      _runOneGeneration(dataMatrix, outputCol);
    }
    return snapshot();
  }

  void _runOneGeneration(Matrix dataMatrix, int outputCol) {
    _successCount = 0;
    _totalTrials = 0;

    for (var i = 0; i < population.size; i++) {
      final target = population[i];

      // Generate per-individual F and CR
      final double fi;
      final double cri;
      if (_jade != null) {
        fi = _jade!.generateF(rng);
        cri = _jade!.generateCR(rng);
      } else {
        fi = config.mutationFactor;
        cri = config.crossoverRate;
      }

      // Mutation
      final mutant = mutationStrategy.mutate(
        target: i,
        population: population.individuals,
        best: population.bestIndex,
        rng: rng,
        params: MutationParams(f: fi),
      );

      // Crossover
      final trial = crossoverStrategy.crossover(
        target: target,
        mutant: mutant,
        cr: cri,
        rng: rng,
      );

      // Evaluate trial
      final regressorMatrix = RegressorBuilder.buildMatrix(trial, dataMatrix);
      if (regressorMatrix == null) continue;

      final output = dataMatrix
          .column(outputCol)
          .subMatrix(trial.maxDelay, dataMatrix.rows, 0, 1);

      final evaluatedTrial = fitnessEvaluator.evaluateChromosome(
        trial,
        regressorMatrix,
        output,
      );

      // Greedy selection
      _totalTrials++;
      if (population.tryReplace(i, evaluatedTrial)) {
        _successCount++;
        _jade?.recordSuccess(fi, cri);
      }
    }

    // Update JADE parameters
    _jade?.endGeneration();

    // Track stagnation
    final currentBest = population.best.fitness;
    if (currentBest < _previousBestFitness - 1e-12) {
      stagnationCounter = 0;
    } else {
      stagnationCounter++;
    }
    _previousBestFitness = currentBest;

    generation++;
  }

  /// Accept immigrants from another island.
  void acceptMigrants(List<Chromosome> immigrants) {
    population.reinitializeWorst(
      immigrants.length / population.size,
      immigrants,
    );
  }

  /// Snapshot of island state for reporting.
  IslandSnapshot snapshot() {
    final stats = population.computeStats();
    return IslandSnapshot(
      islandId: id,
      generation: generation,
      stats: stats,
      bestChromosome: population.best,
      stagnationCounter: stagnationCounter,
      successRate: _totalTrials > 0 ? _successCount / _totalTrials : 0,
      muF: _jade?.muF ?? config.mutationFactor,
      muCR: _jade?.muCR ?? config.crossoverRate,
    );
  }

  /// Update a tunable parameter at runtime.
  void updateConfig(IslandConfig newConfig) {
    config = newConfig;
    _initStrategies();
  }
}

/// Immutable snapshot of an island's state at a point in time.
class IslandSnapshot {
  final int islandId;
  final int generation;
  final PopulationStats stats;
  final Chromosome bestChromosome;
  final int stagnationCounter;
  final double successRate;
  final double muF;
  final double muCR;

  const IslandSnapshot({
    required this.islandId,
    required this.generation,
    required this.stats,
    required this.bestChromosome,
    required this.stagnationCounter,
    required this.successRate,
    required this.muF,
    required this.muCR,
  });
}
