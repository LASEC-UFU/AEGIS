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
import 'snapshot_parser.dart';

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

// step() agora retorna Promise<string> (snapshot JSON do melhor Worker)
@JS('AegisWasm.step')
external JSPromise<JSString> _jsStep(int p, int n);

@JS('AegisWasm.getStatus')
external JSString _jsGetStatus(int p);

@JS('AegisWasm.getSnapshot')
external JSString _jsGetSnapshot(int p);

@JS('AegisWasm.getBestModel')
external JSString _jsGetBestModel(int p);

@JS('AegisWasm.getTuningLog')
external JSString _jsGetTuningLog(int p);

@JS('AegisWasm.applyTuning')
external int _jsApplyTuning(
  int p,
  JSString param,
  double value,
  JSString reason,
);

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

  // 1 geração por poll evita bloquear a UI por muitos segundos em datasets pesados.
  // Para datasets leves pode aumentar para 2-3.
  static const int _kStepsPerPoll = 1;

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
    if (rc != 0) {
      _disposePipeline();
      return false;
    }

    final config = _buildConfigJson(outputCol, numIslands);
    final rc2 = _jsConfigure(_pipeline, config.toJS);
    if (rc2 != 0) {
      _disposePipeline();
      return false;
    }

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

  /// The web build routes every action through the core's validated
  /// interface via the legacy entry point (0 accepted, 1 rejected, -1 unknown).
  Map<String, dynamic> applyAction(String param, double value,
      {String? reason, String source = 'ui'}) {
    if (_pipeline == 0) return {'accepted': false, 'code': 'not_running', 'param': param};
    final rc = _jsApplyTuning(_pipeline, param.toJS, value, (reason ?? '').toJS);
    if (rc == 0) parameters.update(param, value);
    return {
      'accepted': rc == 0,
      'code': rc == 0 ? 'accepted' : (rc == -1 ? 'unknown_parameter' : 'rejected'),
      'param': param,
      'newValue': value,
      'source': source,
    };
  }

  void applyTuning(String param, double value, {String? reason, String source = 'ui'}) {
    applyAction(param, value, reason: reason, source: source);
  }

  // Features of the audited native core not exposed by the JS coordinator.
  bool get hasAuditApi => false;
  int step(int n) => 0;
  void setAgentEnabled(bool enabled) {}
  Map<String, dynamic>? getFinalReport() => null;
  Map<String, dynamic>? getConfig() => null;
  Map<String, dynamic>? getActionSchema() => null;
  List<dynamic> getHistoryRecords() => const [];
  String lastError() => '';
  int _lastGeneration = -1;

  // ── Polling ───────────────────────────────────────────────────────────────

  /// Avança a engine e retorna o snapshot mais recente.
  /// Chamado a cada 200 ms pelo timer de polling em app_state.dart.
  /// Retorna Future porque step() dos Workers é assíncrono (Promise JS).
  Future<GenerationSnapshot?> pollSnapshot() async {
    if (_pipeline == 0) return null;

    String raw;
    if (state == EngineState.running) {
      // step() retorna Promise<string> com o melhor snapshot dos Workers
      final jsResult = await _jsStep(_pipeline, _kStepsPerPoll).toDart;
      raw = jsResult.toDart;
    } else {
      // Pausado/parado: lê cache do coordenador (síncrono)
      raw = _jsGetSnapshot(_pipeline).toDart;
    }

    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final result = snapshotFromCoreJson(json, history: history, elapsed: Duration.zero);
      if (result.generation > _lastGeneration) {
        history.addSnapshot(result);
        _lastGeneration = result.generation;
      }
      return result;
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

  List<Map<String, dynamic>> getTuningLog() {
    if (_pipeline == 0) return [];
    final raw = _jsGetTuningLog(_pipeline).toDart;
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
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

  String _buildConfigJson(int outputCol, int numIslands) => buildCoreConfigJson(
        parameters,
        outputCol: outputCol,
        numIslands: numIslands,
        webSocketPort: 0,
      );
}
