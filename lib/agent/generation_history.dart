import 'generation_snapshot.dart';
import 'tunable_parameter.dart';

/// Full history of the optimization run.
///
/// Stores every generation snapshot and all tuning actions.
class GenerationHistory {
  final List<GenerationSnapshot> _snapshots = [];
  final List<TuningAction> _tuningActions = [];

  void addSnapshot(GenerationSnapshot snapshot) {
    _snapshots.add(snapshot);
  }

  void addTuningAction(TuningAction action) {
    _tuningActions.add(action);
  }

  List<GenerationSnapshot> get snapshots => List.unmodifiable(_snapshots);
  List<TuningAction> get tuningActions => List.unmodifiable(_tuningActions);

  int get length => _snapshots.length;
  bool get isEmpty => _snapshots.isEmpty;

  GenerationSnapshot? get latest => _snapshots.isEmpty ? null : _snapshots.last;

  /// Fitness history as a flat list (for charts / stopping criteria).
  List<double> get fitnessHistory =>
      _snapshots.map((s) => s.bestFitness).toList();

  /// Success rate history (last N generations).
  List<double> successRateHistory([int window = 20]) {
    final start = (_snapshots.length - window).clamp(0, _snapshots.length);
    return _snapshots.sublist(start).map((s) => s.successRate).toList();
  }

  /// Computes improvement rate over a window of generations.
  double improvementRate(int window) {
    if (_snapshots.length < window + 1) return 0;
    final old = _snapshots[_snapshots.length - window - 1].bestFitness;
    final current = _snapshots.last.bestFitness;
    if (old.abs() < 1e-30) return 0;
    return (old - current) / old.abs();
  }

  void clear() {
    _snapshots.clear();
    _tuningActions.clear();
  }
}
