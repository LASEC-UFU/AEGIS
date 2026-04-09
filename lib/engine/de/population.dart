import 'dart:math' as math;

import '../../core/types/chromosome.dart';

/// Manages a population of chromosomes for one island.
class Population {
  final List<Chromosome> _individuals;
  int _bestIndex = 0;

  Population(this._individuals) {
    _updateBest();
  }

  List<Chromosome> get individuals => _individuals;
  int get size => _individuals.length;
  Chromosome get best => _individuals[_bestIndex];
  int get bestIndex => _bestIndex;

  Chromosome operator [](int i) => _individuals[i];
  void operator []=(int i, Chromosome c) {
    _individuals[i] = c;
    if (c.isEvaluated &&
        (c.fitness < _individuals[_bestIndex].fitness ||
            !_individuals[_bestIndex].isEvaluated)) {
      _bestIndex = i;
    }
  }

  void _updateBest() {
    var bestFit = double.infinity;
    for (var i = 0; i < _individuals.length; i++) {
      if (_individuals[i].isEvaluated && _individuals[i].fitness < bestFit) {
        bestFit = _individuals[i].fitness;
        _bestIndex = i;
      }
    }
  }

  /// Replaces individual at [index] only if [candidate] is better (greedy selection).
  bool tryReplace(int index, Chromosome candidate) {
    if (!candidate.isEvaluated) return false;
    if (!_individuals[index].isEvaluated ||
        candidate.fitness < _individuals[index].fitness) {
      _individuals[index] = candidate;
      if (candidate.fitness < _individuals[_bestIndex].fitness) {
        _bestIndex = index;
      }
      return true;
    }
    return false;
  }

  /// Fitness statistics for the current population.
  PopulationStats computeStats() {
    final evaluated = _individuals.where((c) => c.isEvaluated).toList();
    if (evaluated.isEmpty) {
      return PopulationStats.empty();
    }

    final fitnesses = evaluated.map((c) => c.fitness).toList()..sort();
    final n = fitnesses.length;

    final bestFit = fitnesses.first;
    final worstFit = fitnesses.last;
    final meanFit = fitnesses.fold(0.0, (s, f) => s + f) / n;
    final medianFit = n.isOdd
        ? fitnesses[n ~/ 2]
        : (fitnesses[n ~/ 2 - 1] + fitnesses[n ~/ 2]) / 2;

    var variance = 0.0;
    for (final f in fitnesses) {
      variance += (f - meanFit) * (f - meanFit);
    }
    variance /= n;

    final q1 = fitnesses[n ~/ 4];
    final q3 = fitnesses[(3 * n) ~/ 4];

    // Structural diversity: count unique structures
    final structureSet = <int>{};
    for (final c in evaluated) {
      structureSet.add(c.structuralHash);
    }

    // Shannon entropy of structures
    final structCounts = <int, int>{};
    for (final c in evaluated) {
      structCounts[c.structuralHash] =
          (structCounts[c.structuralHash] ?? 0) + 1;
    }
    var entropy = 0.0;
    for (final count in structCounts.values) {
      final p = count / n;
      if (p > 0) entropy -= p * math.log(p);
    }

    return PopulationStats(
      bestFitness: bestFit,
      worstFitness: worstFit,
      meanFitness: meanFit,
      medianFitness: medianFit,
      stdDevFitness: math.sqrt(variance),
      q1: q1,
      q3: q3,
      uniqueStructures: structureSet.length,
      structureEntropy: entropy,
      evaluatedCount: n,
      totalCount: _individuals.length,
    );
  }

  /// Returns the top [count] individuals sorted by fitness.
  List<Chromosome> topN(int count) {
    final sorted = _individuals.where((c) => c.isEvaluated).toList()
      ..sort((a, b) => a.fitness.compareTo(b.fitness));
    return sorted.take(count).toList();
  }

  /// Reinitializes a fraction of the population (worst individuals).
  void reinitializeWorst(double fraction, List<Chromosome> newIndividuals) {
    final sorted = List<int>.generate(size, (i) => i)
      ..sort((a, b) {
        final fa = _individuals[a].isEvaluated
            ? _individuals[a].fitness
            : double.infinity;
        final fb = _individuals[b].isEvaluated
            ? _individuals[b].fitness
            : double.infinity;
        return fb.compareTo(fa); // worst first
      });
    final count = (size * fraction).ceil().clamp(0, newIndividuals.length);
    for (var i = 0; i < count; i++) {
      _individuals[sorted[i]] = newIndividuals[i];
    }
    _updateBest();
  }
}

/// Snapshot of population statistics.
class PopulationStats {
  final double bestFitness;
  final double worstFitness;
  final double meanFitness;
  final double medianFitness;
  final double stdDevFitness;
  final double q1;
  final double q3;
  final int uniqueStructures;
  final double structureEntropy;
  final int evaluatedCount;
  final int totalCount;

  const PopulationStats({
    required this.bestFitness,
    required this.worstFitness,
    required this.meanFitness,
    required this.medianFitness,
    required this.stdDevFitness,
    required this.q1,
    required this.q3,
    required this.uniqueStructures,
    required this.structureEntropy,
    required this.evaluatedCount,
    required this.totalCount,
  });

  factory PopulationStats.empty() => const PopulationStats(
    bestFitness: double.infinity,
    worstFitness: double.infinity,
    meanFitness: double.infinity,
    medianFitness: double.infinity,
    stdDevFitness: 0,
    q1: double.infinity,
    q3: double.infinity,
    uniqueStructures: 0,
    structureEntropy: 0,
    evaluatedCount: 0,
    totalCount: 0,
  );
}
