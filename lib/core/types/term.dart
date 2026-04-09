/// Represents a single component of a NARX regressor term.
///
/// Mirrors the C++ `Termo` struct but in an immutable Dart form.
/// A term is: variable^exponent(k - delay)
/// For rational models, [isDenominator] marks denominator terms.
class Term {
  /// Variable index (0-based: 0 = first input, last = output).
  final int variable;

  /// Time delay (k - delay). Always >= 1 for dynamic models.
  final int delay;

  /// Whether this term belongs to the denominator (rational models).
  final bool isDenominator;

  const Term({
    required this.variable,
    required this.delay,
    this.isDenominator = false,
  });

  Term copyWith({int? variable, int? delay, bool? isDenominator}) {
    return Term(
      variable: variable ?? this.variable,
      delay: delay ?? this.delay,
      isDenominator: isDenominator ?? this.isDenominator,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Term &&
          variable == other.variable &&
          delay == other.delay &&
          isDenominator == other.isDenominator;

  @override
  int get hashCode => Object.hash(variable, delay, isDenominator);

  @override
  String toString() => '${isDenominator ? "D" : "N"}:x$variable(k-$delay)';

  /// Compact integer encoding for hashing and fast comparison.
  int get encoded =>
      (isDenominator ? 1 : 0) << 22 |
      (variable & 0x7FF) << 11 |
      (delay & 0x7FF);
}
