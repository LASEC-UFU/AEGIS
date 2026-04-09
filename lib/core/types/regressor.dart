import 'term.dart';

/// A compound term in a NARX regressor: product of [Term]s each raised to an [exponent].
///
/// Example: x0(k-1)^2 * x1(k-3)^1
/// = CompoundTerm(components: [(x0, delay=1, exp=2), (x1, delay=3, exp=1)])
class CompoundTerm {
  final Term term;
  final double exponent;

  const CompoundTerm({required this.term, required this.exponent});

  CompoundTerm copyWith({Term? term, double? exponent}) {
    return CompoundTerm(
      term: term ?? this.term,
      exponent: exponent ?? this.exponent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompoundTerm && term == other.term && exponent == other.exponent;

  @override
  int get hashCode => Object.hash(term, exponent);

  @override
  String toString() {
    if (exponent == 1.0) return term.toString();
    return '$term^${exponent.toStringAsFixed(1)}';
  }
}

/// A regressor is a list of compound terms multiplied together.
///
/// Example: y(k-1)^2 * u(k-2) is a single regressor with 2 compound terms.
class Regressor {
  final List<CompoundTerm> components;

  const Regressor(this.components);

  /// Whether this regressor contains any denominator terms.
  bool get isDenominator => components.any((c) => c.term.isDenominator);

  /// Maximum delay used in this regressor.
  int get maxDelay {
    if (components.isEmpty) return 0;
    return components.map((c) => c.term.delay).reduce((a, b) => a > b ? a : b);
  }

  /// Number of component terms.
  int get complexity => components.length;

  /// Maximum exponent used.
  double get maxExponent {
    if (components.isEmpty) return 0;
    return components.map((c) => c.exponent).reduce((a, b) => a > b ? a : b);
  }

  /// Structural hash (ignoring exponent values, only structure).
  int get structuralHash {
    var h = 0;
    for (final c in components) {
      h = h * 31 + c.term.encoded;
    }
    return h;
  }

  Regressor copyWith({List<CompoundTerm>? components}) {
    return Regressor(components ?? this.components);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Regressor && _listEquals(components, other.components);

  static bool _listEquals(List<CompoundTerm> a, List<CompoundTerm> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(components);

  @override
  String toString() => components.join(' × ');
}
