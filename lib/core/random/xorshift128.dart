import 'dart:math' as math;

/// Fast PRNG with deterministic seeding — web-compatible wrapper
/// around dart:math.Random.
///
/// Uses dart:math.Random internally (which uses a good PRNG engine)
/// and provides the same API as the original Xorshift128+ but without
/// 64-bit integer literals that break JavaScript compilation.
///
/// Each island gets its own instance with independent seed.
class Xorshift128Plus {
  late final math.Random _rng;

  Xorshift128Plus([int? seed]) {
    _rng = math.Random(seed ?? DateTime.now().microsecondsSinceEpoch);
  }

  /// Raw 32-bit integer.
  int nextInt32() {
    return _rng.nextInt(0x7FFFFFFF);
  }

  /// Uniform int in [0, max) (exclusive).
  int nextIntRange(int max) {
    if (max <= 0) return 0;
    if (max <= 0x7FFFFFFF) return _rng.nextInt(max);
    // For larger ranges, combine two calls
    return (nextDouble() * max).floor() % max;
  }

  /// Uniform int in [min, max] (inclusive).
  int nextIntBetween(int min, int max) {
    if (min >= max) return min;
    return min + nextIntRange(max - min + 1);
  }

  /// Uniform double in [0, 1).
  double nextDouble() {
    return _rng.nextDouble();
  }

  /// Uniform double in [min, max).
  double nextDoubleBetween(double min, double max) {
    return min + nextDouble() * (max - min);
  }

  /// Standard normal via Box-Muller.
  double nextGaussian({double mean = 0.0, double stdDev = 1.0}) {
    double u1, u2;
    do {
      u1 = nextDouble();
    } while (u1 == 0.0);
    u2 = nextDouble();
    final z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
    return mean + z * stdDev;
  }

  /// Cauchy distribution (used by JADE/SHADE for F parameter).
  double nextCauchy({double location = 0.0, double scale = 1.0}) {
    double u;
    do {
      u = nextDouble() - 0.5;
    } while (u == 0.0);
    return location + scale * math.tan(math.pi * u);
  }

  /// Fisher-Yates shuffle of a list in-place.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextIntRange(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  /// Select [count] distinct random indices from [0, max).
  List<int> distinctIndices(int max, int count) {
    assert(count <= max);
    final selected = <int>{};
    while (selected.length < count) {
      selected.add(nextIntRange(max));
    }
    return selected.toList();
  }
}
