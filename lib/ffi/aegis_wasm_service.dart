// Web WASM implementation of AegisFfiService.
// Mirrors the interface of aegis_ffi_service_native.dart so app_state.dart
// needs zero changes.  pollSnapshot() drives the engine synchronously by
// calling step() before reading — the existing 200 ms polling timer works
// identically for both native (async thread) and WASM (sync batch).

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../core/math/matrix.dart';
import '../agent/generation_snapshot.dart';
import '../agent/generation_history.dart';
import '../agent/tunable_parameter.dart';
import '../engine/de/de_engine.dart' show EngineState;
import 'aegis_library.dart';

// ── JS bridge declarations ────────────────────────────────────────────────

@JS('AegisWasm.createPipeline')
external int _jsCreatePipeline();

@JS('AegisWasm.destroyPipeline')
external void _jsDestroyPipeline(int p);

@JS('AegisWasm.loadData')
external int _jsLoadData(int p, JSFloat64Array arr, int rows, int cols);

@JS('AegisWasm.configure')
external int _jsConfigure(int p, JSString json);

@JS('AegisWasm.start')
external int _jsStart(int p);

@JS('AegisWasm.pause')
external int _jsPause(int p);

@JS('AegisWasm.resume')
external int _jsResume(int p);

@JS('AegisWasm.stop')
external int _jsStop(int p);

@JS('AegisWasm.step')
external int _jsStep(int p, int n);

@JS('AegisWasm.getStatus')
external JSString _jsGetStatus(int p);

@JS('AegisWasm.getSnapshot')
external JSString _jsGetSnapshot(int p);

@JS('AegisWasm.getBestModel')
external JSString _jsGetBestModel(int p);

@JS('AegisWasm.applyTuning')
external int _jsApplyTuning(int p, JSString param, double value, JSString reason);

// ── Service class ─────────────────────────────────────────────────────────

class AegisFfiService {
  // Unused on web — kept only to match the native constructor signature.
  // ignore: unused_field
  final AegisLibrary _lib;

  int _pipeline = 0; // 0 = null pointer

  EngineState state = EngineState.idle;
  final GenerationHistory history = GenerationHistory();
  final ParameterRegistry parameters = ParameterRegistry();

  void Function(GenerationSnapshot)? onGenerationComplete;
  void Function(EngineState)? onStateChanged;

  static const int _kStepsPerPoll = 5;

  AegisFfiService(this._lib) {
    parameters.registerDefaults();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  bool initialize({
    required Matrix normalizedData,
    Matrix? validationData,
    required int outputCol,
    required int numVariables,
    int numIslands = 3,
  }) {
    _disposePipeline();
    _pipeline = _jsCreatePipeline();
    if (_pipeline == 0) return false;

    // Build flat row-major Float64Array for WASM
    final rows = normalizedData.rows;
    final cols = normalizedData.cols;
    final flat = Float64List(rows * cols);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        flat[r * cols + c] = normalizedData.get(r, c);
      }
    }

    final rc = _jsLoadData(_pipeline, flat.toJS, rows, cols);
    if (rc != 0) { _disposePipeline(); return false; }

    final config = _buildConfigJson(outputCol, numIslands);
    final rc2 = _jsConfigure(_pipeline, config.toJS);
    if (rc2 != 0) { _disposePipeline(); return false; }

    state = EngineState.idle;
    return true;
  }

  bool start() {
    if (_pipeline == 0) return false;
    final rc = _jsStart(_pipeline);
    if (rc != 0) return false;
    state = EngineState.running;
    onStateChanged?.call(state);
    return true;
  }

  void pause() {
    if (_pipeline == 0) return;
    _jsPause(_pipeline);
    state = EngineState.paused;
    onStateChanged?.call(state);
  }

  void resume() {
    if (_pipeline == 0) return;
    _jsResume(_pipeline);
    state = EngineState.running;
    onStateChanged?.call(state);
  }

  void stop() {
    if (_pipeline == 0) return;
    _jsStop(_pipeline);
    state = EngineState.stopped;
    onStateChanged?.call(state);
  }

  void applyTuning(String param, double value, {String? reason}) {
    if (_pipeline == 0) return;
    parameters.update(param, value);
    _jsApplyTuning(_pipeline, param.toJS, value, (reason ?? '').toJS);
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  /// Drive the engine synchronously then return the latest snapshot.
  /// Called every 200 ms by the UI polling timer in app_state.dart.
  GenerationSnapshot? pollSnapshot() {
    if (_pipeline == 0) return null;

    // Drive computation (WASM has no background thread)
    if (state == EngineState.running) {
      _jsStep(_pipeline, _kStepsPerPoll);
    }

    final raw = _jsGetSnapshot(_pipeline).toDart;
    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _snapshotFromJson(json);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? pollStatus() {
    if (_pipeline == 0) return null;
    final raw = _jsGetStatus(_pipeline).toDart;
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? getBestModel() {
    if (_pipeline == 0) return null;
    final raw = _jsGetBestModel(_pipeline).toDart;
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void dispose() => _disposePipeline();

  void _disposePipeline() {
    if (_pipeline != 0) {
      _jsDestroyPipeline(_pipeline);
      _pipeline = 0;
    }
  }

  // ── Config builder ────────────────────────────────────────────────────────

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
    });
  }

  // ── Snapshot deserializer ──────────────────────────────────────────────────

  GenerationSnapshot _snapshotFromJson(Map<String, dynamic> j) {
    double d(String k, [double def = 0.0]) =>
        (j[k] as num?)?.toDouble() ?? def;
    int    n(String k, [int def = 0]) => (j[k] as num?)?.toInt() ?? def;

    List<double> arr(String k) {
      final raw = j[k];
      if (raw is List) return raw.map((e) => (e as num).toDouble()).toList();
      return [];
    }

    final gen = n('generation');
    return GenerationSnapshot(
      generation:              gen,
      elapsed:                 Duration.zero,
      bestFitness:             d('best_fitness', double.infinity),
      worstFitness:            double.infinity,
      meanFitness:             d('best_fitness', double.infinity),
      medianFitness:           d('best_fitness', double.infinity),
      stdDevFitness:           d('population_diversity'),
      q1Fitness:               double.infinity,
      q3Fitness:               double.infinity,
      improvementAbsolute:     0,
      improvementRelative:     0,
      improvementRate5:        0,
      improvementRate20:       0,
      stagnationCounter:       n('stagnation'),
      uniqueStructures:        0,
      structureEntropy:        0,
      phenotypicDiversity:     d('population_diversity'),
      regressorFrequency:      {},
      populationVariance:      0,
      successRate:             0,
      successRateHistory:      [],
      bestModelComplexity:     n('num_terms'),
      bestModelMaxDegree:      0,
      bestModelMaxDelay:       0,
      bestModelERR:            arr('residual_autocorr'),
      bestModelRMSE:           d('rmse_train'),
      bestModelValidationRMSE: d('rmse_validation').isFinite
          ? d('rmse_validation') : null,
      bestModelR2:             0,
      residualAutocorrelation: arr('residual_autocorr').isEmpty
          ? null : arr('residual_autocorr'),
      islandSnapshots:         [],
      migrationImpact:         null,
    );
  }
}
