import '../de/population.dart';

/// Abstract stopping criterion. Composable via [CompositeCriterion].
///
/// [O] Open for extension: add new criteria without modifying existing.
abstract class StoppingCriterion {
  /// Returns true if the optimization should stop.
  bool shouldStop(StoppingContext context);

  /// Human-readable reason for stopping.
  String get reason;

  String get name;
}

/// Context passed to stopping criteria.
class StoppingContext {
  final int generation;
  final int stagnationCounter;
  final double bestFitness;
  final double previousBestFitness;
  final PopulationStats stats;
  final Duration elapsedTime;
  final List<double> fitnessHistory;

  const StoppingContext({
    required this.generation,
    required this.stagnationCounter,
    required this.bestFitness,
    required this.previousBestFitness,
    required this.stats,
    required this.elapsedTime,
    required this.fitnessHistory,
  });
}

/// Stops after a maximum number of generations.
class MaxGenerations implements StoppingCriterion {
  final int maxGen;
  MaxGenerations(this.maxGen);

  @override
  String get name => 'MaxGenerations';

  @override
  String get reason => 'Reached $maxGen generations';

  @override
  bool shouldStop(StoppingContext ctx) => ctx.generation >= maxGen;
}

/// Stops after N generations without improvement.
class StagnationLimit implements StoppingCriterion {
  final int limit;
  StagnationLimit(this.limit);

  @override
  String get name => 'Stagnation';

  @override
  String get reason => 'No improvement for $limit generations';

  @override
  bool shouldStop(StoppingContext ctx) => ctx.stagnationCounter >= limit;
}

/// Stops when population variance drops below threshold (premature convergence).
class PopulationVariance implements StoppingCriterion {
  final double threshold;
  PopulationVariance(this.threshold);

  @override
  String get name => 'PopulationVariance';

  @override
  String get reason => 'Population converged (variance < $threshold)';

  @override
  bool shouldStop(StoppingContext ctx) {
    final variance = ctx.stats.stdDevFitness * ctx.stats.stdDevFitness;
    return variance < threshold && ctx.generation > 10;
  }
}

/// Stops when relative improvement drops below threshold.
class RelativeImprovement implements StoppingCriterion {
  final double threshold;
  final int windowSize;
  RelativeImprovement(this.threshold, {this.windowSize = 50});

  @override
  String get name => 'RelativeImprovement';

  @override
  String get reason => 'Relative improvement below $threshold';

  @override
  bool shouldStop(StoppingContext ctx) {
    if (ctx.fitnessHistory.length < windowSize) return false;
    final recent = ctx.fitnessHistory.sublist(
      ctx.fitnessHistory.length - windowSize,
    );
    final old = recent.first;
    final current = recent.last;
    if (old.abs() < 1e-30) return false;
    return ((old - current) / old.abs()).abs() < threshold;
  }
}

/// Stops after a time limit.
class TimeLimit implements StoppingCriterion {
  final Duration limit;
  TimeLimit(this.limit);

  @override
  String get name => 'TimeLimit';

  @override
  String get reason => 'Time limit of ${limit.inSeconds}s reached';

  @override
  bool shouldStop(StoppingContext ctx) => ctx.elapsedTime >= limit;
}

/// Composite criterion: stops when ANY (or ALL) sub-criteria are met.
class CompositeCriterion implements StoppingCriterion {
  final List<StoppingCriterion> criteria;
  final bool requireAll;

  /// If [requireAll] is true, ALL criteria must be met. Otherwise, ANY suffices.
  CompositeCriterion(this.criteria, {this.requireAll = false});

  @override
  String get name => requireAll ? 'AllOf' : 'AnyOf';

  @override
  String get reason {
    final met = criteria.where((c) => _lastResults[c] == true);
    return met.map((c) => c.reason).join('; ');
  }

  final Map<StoppingCriterion, bool> _lastResults = {};

  @override
  bool shouldStop(StoppingContext ctx) {
    _lastResults.clear();
    for (final c in criteria) {
      _lastResults[c] = c.shouldStop(ctx);
    }
    if (requireAll) {
      return _lastResults.values.every((v) => v);
    }
    return _lastResults.values.any((v) => v);
  }
}
