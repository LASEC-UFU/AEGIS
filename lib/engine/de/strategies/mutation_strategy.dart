import '../../../core/types/chromosome.dart';
import '../../../core/random/xorshift128.dart';

/// Abstract mutation strategy for Differential Evolution.
///
/// [O] Open/Closed: New strategies can be added without modifying existing code.
/// [L] Liskov: All strategies are interchangeable.
abstract class MutationStrategy {
  /// Produces a mutant vector from the population.
  ///
  /// [target]: index of the target individual
  /// [population]: current population
  /// [best]: best individual index
  /// [rng]: random number generator
  /// [params]: strategy-specific parameters (F, etc.)
  Chromosome mutate({
    required int target,
    required List<Chromosome> population,
    required int best,
    required Xorshift128Plus rng,
    required MutationParams params,
  });

  String get name;
}

/// Parameters for mutation strategies, allowing per-individual adaptation.
class MutationParams {
  /// Scaling factor F.
  final double f;

  /// Optional secondary scaling factor (for DE/rand/2, etc.).
  final double f2;

  const MutationParams({this.f = 0.5, this.f2 = 0.5});
}
