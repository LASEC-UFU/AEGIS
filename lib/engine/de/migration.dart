import '../../core/types/chromosome.dart';
import '../../core/random/xorshift128.dart';
import 'island.dart';

/// Strategy for migrating individuals between islands.
enum MigrationTopology { ring, star, random }

/// Manages migration between islands.
class Migration {
  final MigrationTopology topology;
  final int interval;
  final double rate;
  final Xorshift128Plus rng;

  Migration({
    this.topology = MigrationTopology.ring,
    this.interval = 20,
    this.rate = 0.1,
    Xorshift128Plus? rng,
  }) : rng = rng ?? Xorshift128Plus();

  /// Check if migration should occur at this generation.
  bool shouldMigrate(int generation) =>
      generation > 0 && generation % interval == 0;

  /// Perform migration between islands.
  /// Returns the fitness improvement caused by migration (for indicators).
  double migrate(List<Island> islands) {
    if (islands.length < 2) return 0;

    final numMigrants = (islands[0].population.size * rate).ceil().clamp(1, 5);
    var totalImprovement = 0.0;

    switch (topology) {
      case MigrationTopology.ring:
        _ringMigration(islands, numMigrants);
      case MigrationTopology.star:
        _starMigration(islands, numMigrants);
      case MigrationTopology.random:
        _randomMigration(islands, numMigrants);
    }

    // Measure improvement (simplified)
    for (final island in islands) {
      final newBest = island.population.best.fitness;
      totalImprovement += newBest;
    }

    return totalImprovement / islands.length;
  }

  void _ringMigration(List<Island> islands, int numMigrants) {
    final emigrants = <List<Chromosome>>[];
    for (final island in islands) {
      emigrants.add(island.population.topN(numMigrants).map((c) => c).toList());
    }
    for (var i = 0; i < islands.length; i++) {
      final source = (i + 1) % islands.length;
      islands[i].acceptMigrants(emigrants[source]);
    }
  }

  void _starMigration(List<Island> islands, int numMigrants) {
    // Find global best island
    var bestIsland = 0;
    var bestFit = double.infinity;
    for (var i = 0; i < islands.length; i++) {
      if (islands[i].population.best.fitness < bestFit) {
        bestFit = islands[i].population.best.fitness;
        bestIsland = i;
      }
    }
    final bestEmigrants = islands[bestIsland].population.topN(numMigrants);
    for (var i = 0; i < islands.length; i++) {
      if (i != bestIsland) {
        islands[i].acceptMigrants(bestEmigrants);
      }
    }
  }

  void _randomMigration(List<Island> islands, int numMigrants) {
    final indices = List.generate(islands.length, (i) => i);
    rng.shuffle(indices);
    for (var i = 0; i < indices.length - 1; i += 2) {
      final a = indices[i];
      final b = indices[i + 1];
      final emigrantsA = islands[a].population.topN(numMigrants);
      final emigrantsB = islands[b].population.topN(numMigrants);
      islands[a].acceptMigrants(emigrantsB);
      islands[b].acceptMigrants(emigrantsA);
    }
  }
}
