import '../math/matrix.dart';

/// Holds the identified NARX model with everything needed for simulation.
class NarxModel {
  /// Display equation in text form.
  final String equation;

  /// Coefficient values.
  final List<double> coefficients;

  /// Regressor descriptions.
  final List<String> regressorNames;

  /// ERR per regressor (ordered by importance).
  final List<double> errValues;

  /// Fitness score (BIC/AIC/MDL).
  final double fitness;

  /// Training metrics.
  final double rmseTraining;
  final double r2Training;

  /// Validation metrics (null if no validation set).
  final double? rmseValidation;
  final double? r2Validation;

  /// Residual analysis.
  final Matrix? residuals;
  final List<double>? residualAutocorrelation;

  const NarxModel({
    required this.equation,
    required this.coefficients,
    required this.regressorNames,
    required this.errValues,
    required this.fitness,
    required this.rmseTraining,
    required this.r2Training,
    this.rmseValidation,
    this.r2Validation,
    this.residuals,
    this.residualAutocorrelation,
  });
}
