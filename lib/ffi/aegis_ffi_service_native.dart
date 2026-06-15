// High-level Dart wrapper over the C++ AEGIS core.
// Mirrors the interface of DEEngine so app_state.dart can swap backends
// with minimal changes.

import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../core/math/matrix.dart';
import '../agent/generation_snapshot.dart';
import '../agent/generation_history.dart';
import '../agent/tunable_parameter.dart';
import '../engine/de/de_engine.dart' show EngineState;
import 'aegis_library.dart';

class AegisFfiService {
  final AegisLibrary _lib;
  Pointer<Void>? _pipeline;

  EngineState state = EngineState.idle;
  final GenerationHistory history = GenerationHistory();
  final ParameterRegistry parameters = ParameterRegistry();

  void Function(GenerationSnapshot)? onGenerationComplete;
  void Function(EngineState)? onStateChanged;

  AegisFfiService(this._lib) {
    parameters.registerDefaults();
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  bool initialize({
    required Matrix normalizedData,
    Matrix? validationData,
    required int outputCol,
    required int numVariables,
    int numIslands = 3,
  }) {
    _disposePipeline();
    _pipeline = _lib.createPipeline();
    if (_pipeline == null || _pipeline!.address == 0) return false;

    // Transfer training data (row-major)
    final rows = normalizedData.rows;
    final cols = normalizedData.cols;
    final nativeData = calloc<Double>(rows * cols);
    try {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          // Matrix is column-major; convert to row-major for C++
          nativeData[r * cols + c] = normalizedData.get(r, c);
        }
      }
      final rc = _lib.loadData(_pipeline!, nativeData, rows, cols);
      if (rc != 0) return false;
    } finally {
      calloc.free(nativeData);
    }

    // Build config JSON from current parameters
    final config = _buildConfigJson(outputCol, numIslands);
    final configPtr = config.toNativeUtf8();
    try {
      final rc = _lib.configure(_pipeline!, configPtr);
      if (rc != 0) return false;
    } finally {
      calloc.free(configPtr);
    }

    state = EngineState.idle;
    return true;
  }

  bool start() {
    if (_pipeline == null) return false;
    final rc = _lib.start(_pipeline!);
    if (rc != 0) return false;
    state = EngineState.running;
    onStateChanged?.call(state);
    return true;
  }

  void pause() {
    if (_pipeline == null) return;
    _lib.pause(_pipeline!);
    state = EngineState.paused;
    onStateChanged?.call(state);
  }

  void resume() {
    if (_pipeline == null) return;
    _lib.resume(_pipeline!);
    state = EngineState.running;
    onStateChanged?.call(state);
  }

  void stop() {
    if (_pipeline == null) return;
    _lib.stop(_pipeline!);
    state = EngineState.stopped;
    onStateChanged?.call(state);
  }

  void applyTuning(String param, double value, {String? reason}) {
    if (_pipeline == null) return;
    parameters.update(param, value);
    final paramPtr  = param.toNativeUtf8();
    final reasonPtr = (reason ?? '').toNativeUtf8();
    try {
      _lib.applyTuning(_pipeline!, paramPtr, value, reasonPtr);
    } finally {
      calloc.free(paramPtr);
      calloc.free(reasonPtr);
    }
  }

  /// Poll the C++ engine for the latest snapshot. Call this from the UI timer.
  GenerationSnapshot? pollSnapshot() {
    if (_pipeline == null) return null;
    final snap = _lib.callStringFn(() => _lib.getSnapshot(_pipeline!));
    if (snap.isEmpty) return null;
    try {
      final json = jsonDecode(snap) as Map<String, dynamic>;
      final result = _snapshotFromJson(json);
      history.addSnapshot(result);
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Poll pipeline status string (state, generation, fitness, etc.)
  Map<String, dynamic>? pollStatus() {
    if (_pipeline == null) return null;
    final s = _lib.callStringFn(() => _lib.getStatus(_pipeline!));
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Poll the agent's tuning action log (parameter changes applied so far).
  List<Map<String, dynamic>> getTuningLog() {
    if (_pipeline == null) return [];
    final s = _lib.callStringFn(() => _lib.getTuningLog(_pipeline!));
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic>? getBestModel() {
    if (_pipeline == null) return null;
    final s = _lib.callStringFn(() => _lib.getBestModel(_pipeline!));
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────

  void dispose() => _disposePipeline();

  void _disposePipeline() {
    if (_pipeline != null && _pipeline!.address != 0) {
      _lib.destroyPipeline(_pipeline!);
      _pipeline = null;
    }
  }

  // ── Config builder ───────────────────────────────────────────────────────

  String _buildConfigJson(int outputCol, int numIslands) {
    double p(String k) => parameters.get(k)?.currentValue ?? 0.0;
    int    i(String k) => p(k).toInt();

    return jsonEncode({
      'normalizerType':    'minmax',
      'outputCol':         outputCol,
      'numIslands':        numIslands,
      'populationSize':    i('populationSize'),
      'mutationFactor':    p('mutationFactor'),
      'crossoverRate':     p('crossoverRate'),
      'elitismCount':      i('elitismCount'),
      'migrationInterval': i('migrationInterval'),
      'migrationRate':     p('migrationRate'),
      'maxRegressors':     i('maxRegressors'),
      'maxDelay':          i('maxDelay'),
      'pmin':              0.5,
      'pmax':              p('maxExponent'),
      'stagnationLimit':   i('stagnationLimit'),
      'complexityPenalty': p('complexityPenalty'),
      'noInputPenalty':    p('noInputPenalty'),
      'freeRunPenalty':    p('freeRunPenalty'),
      'freeRunHorizon':    i('freeRunHorizon'),
      'inputContributionMin': p('inputContributionMin'),
      'gammaAnnealStart':  p('gammaAnnealStart'),
      'gammaAnnealEnd':    p('gammaAnnealEnd'),
      'phaseStagnationLimit': i('phaseStagnationLimit'),
      'reinitializationRatio': p('reinitializationRatio'),
      'webSocketPort':     8765,
    });
  }

  // ── Snapshot deserializer ─────────────────────────────────────────────

  GenerationSnapshot _snapshotFromJson(Map<String, dynamic> j) {
    double d(String k, [double def = 0.0]) =>
        (j[k] as num?)?.toDouble() ?? def;
    int    n(String k, [int def = 0]) => (j[k] as num?)?.toInt() ?? def;

    List<double> arr(String k) {
      final raw = j[k];
      if (raw is List) return raw.map((e) => (e as num).toDouble()).toList();
      return [];
    }

    Map<String, double> fitnessBreakdown() {
      final raw = j['fitness_breakdown'];
      if (raw is Map) {
        return raw.map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0),
        );
      }
      return {};
    }

    double? optd(String k) {
      final v = j[k];
      if (v == null) return null;
      final dv = (v as num).toDouble();
      return dv.isFinite ? dv : null;
    }

    List<String> islandRoles() {
      final raw = j['island_roles'];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return [];
    }

    final gen = n('generation');
    final bestFitness = d('best_fitness', double.infinity);

    // Improvement metrics, derived from previously-recorded snapshots.
    final fitHistory = history.fitnessHistory;
    double impAbs = 0, impRel = 0;
    if (fitHistory.isNotEmpty) {
      final prev = fitHistory.last;
      impAbs = prev - bestFitness;
      impRel = prev.abs() > 1e-30 ? impAbs / prev.abs() : 0;
    }
    double improvementRate(int window) {
      if (fitHistory.length < window) return 0;
      final old = fitHistory[fitHistory.length - window];
      if (old.abs() < 1e-30) return 0;
      return (old - bestFitness) / old.abs();
    }

    return GenerationSnapshot(
      generation:            gen,
      elapsed:               Duration.zero,
      bestFitness:           bestFitness,
      worstFitness:          double.infinity,
      meanFitness:           bestFitness,
      medianFitness:         bestFitness,
      stdDevFitness:         d('population_diversity'),
      q1Fitness:             double.infinity,
      q3Fitness:             double.infinity,
      improvementAbsolute:   impAbs,
      improvementRelative:   impRel,
      improvementRate5:      improvementRate(5),
      improvementRate20:     improvementRate(20),
      stagnationCounter:     n('stagnation'),
      uniqueStructures:      n('unique_structures'),
      structureEntropy:      d('structure_entropy'),
      phenotypicDiversity:   d('population_diversity'),
      regressorFrequency:    {},
      populationVariance:    d('population_variance'),
      successRate:           d('success_rate'),
      successRateHistory:    [],
      bestModelComplexity:   n('num_terms'),
      bestModelMaxDegree:    0,
      bestModelMaxDelay:     0,
      bestModelERR:          arr('residual_autocorr'),
      bestModelRMSE:         d('rmse_train'),
      bestModelValidationRMSE: d('rmse_validation').isFinite
          ? d('rmse_validation') : null,
      bestModelR2:           d('r2_train'),
      residualAutocorrelation: arr('residual_autocorr').isEmpty
          ? null : arr('residual_autocorr'),
      islandSnapshots:       [],
      migrationImpact:       null,
      phase:                 n('phase'),
      phaseName:             (j['phase_name'] as String?) ?? '',
      freeRunRmse:           optd('free_run_rmse'),
      inputContributionRatio: optd('input_contribution_ratio'),
      residualInputCorr:     optd('residual_input_corr'),
      fitnessBreakdown:      fitnessBreakdown(),
      bestContextsSurvived:  n('best_contexts_survived'),
      bestWorstFitnessSeen:  optd('best_worst_fitness_seen'),
      islandRoles:           islandRoles(),
    );
  }
}
