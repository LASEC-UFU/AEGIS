// High-level Dart wrapper over the C++ AEGIS core (dart:ffi).
// Mirrors the interface of DEEngine so app_state.dart can swap backends.
// Pure Dart (no Flutter imports): also used by the headless experiment runner
// in tool/experiments/.

import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../core/math/matrix.dart';
import '../agent/generation_snapshot.dart';
import '../agent/generation_history.dart';
import '../agent/tunable_parameter.dart';
import '../engine/de/de_engine.dart' show EngineState;
import 'aegis_library.dart';
import 'snapshot_parser.dart';

class AegisFfiService {
  final AegisLibrary _lib;
  Pointer<Void>? _pipeline;

  EngineState state = EngineState.idle;
  DateTime? _startTime;
  final GenerationHistory history = GenerationHistory();
  final ParameterRegistry parameters = ParameterRegistry();
  int _lastGeneration = -1;

  void Function(GenerationSnapshot)? onGenerationComplete;
  void Function(EngineState)? onStateChanged;

  AegisFfiService(this._lib) {
    parameters.registerDefaults();
  }

  /// True when the loaded core provides the typed action interface (≥ 1.1.0).
  bool get hasAuditApi => _lib.hasAuditApi;

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// [normalizedData] is the RAW series: the core fits the normalizer on the
  /// training split itself (the name is kept for interface compatibility).
  bool initialize({
    required Matrix normalizedData,
    Matrix? validationData,
    required int outputCol,
    required int numVariables,
    int numIslands = 3,
    int webSocketPort = 8765,
    Map<String, Object?> configOverrides = const {},
    String? configJson,
  }) {
    _disposePipeline();
    history.clear();
    _lastGeneration = -1;
    _pipeline = _lib.createPipeline();
    if (_pipeline == null || _pipeline!.address == 0) return false;

    final rows = normalizedData.rows;
    final cols = normalizedData.cols;
    final nativeData = calloc<Double>(rows * cols);
    try {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          nativeData[r * cols + c] = normalizedData.get(r, c);
        }
      }
      if (_lib.loadData(_pipeline!, nativeData, rows, cols) != 0) return false;
    } finally {
      calloc.free(nativeData);
    }

    final config = configJson ??
        buildCoreConfigJson(parameters,
            outputCol: outputCol,
            numIslands: numIslands,
            webSocketPort: webSocketPort,
            overrides: configOverrides);
    final configPtr = config.toNativeUtf8();
    try {
      if (_lib.configure(_pipeline!, configPtr) != 0) return false;
    } finally {
      calloc.free(configPtr);
    }
    state = EngineState.idle;
    return true;
  }

  bool start() {
    if (_pipeline == null) return false;
    if (_lib.start(_pipeline!) != 0) return false;
    _startTime = DateTime.now();
    history.clear();
    _lastGeneration = -1;
    state = EngineState.running;
    onStateChanged?.call(state);
    return true;
  }

  /// Lockstep mode (config syncMode=true): run up to [n] generations now.
  int step(int n) {
    final fn = _lib.step;
    if (_pipeline == null || fn == null) return 0;
    return fn(_pipeline!, n);
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

  // ── Agent actions ───────────────────────────────────────────────────────

  /// Submits one action through the typed interface. Returns the core's
  /// ActionRecord (accepted, code, message, oldValue, newValue, …). The local
  /// parameter registry is updated only when the core accepts the action.
  Map<String, dynamic> applyAction(String param, double value,
      {String? reason, String source = 'ui'}) {
    if (_pipeline == null) {
      return {'accepted': false, 'code': 'not_running', 'param': param};
    }
    Map<String, dynamic> result;
    final fn = _lib.applyAction;
    if (fn != null) {
      final req = jsonEncode({'param': param, 'value': value, 'reason': reason ?? '', 'source': source});
      try {
        final res = jsonDecode(_lib.callStringArg(_pipeline!, fn, req)) as Map<String, dynamic>;
        final list = (res['results'] as List?) ?? const [];
        result = list.isEmpty
            ? {'accepted': false, 'code': 'no_result', 'param': param}
            : Map<String, dynamic>.from(list.first as Map);
      } catch (e) {
        result = {'accepted': false, 'code': 'invalid_reply', 'message': '$e', 'param': param};
      }
    } else {
      // Legacy core: 0 accepted, 1 rejected, -1 unknown parameter.
      final paramPtr = param.toNativeUtf8();
      final reasonPtr = (reason ?? '').toNativeUtf8();
      try {
        final rc = _lib.applyTuning(_pipeline!, paramPtr, value, reasonPtr);
        result = {
          'accepted': rc == 0,
          'code': rc == 0 ? 'accepted' : (rc == -1 ? 'unknown_parameter' : 'rejected'),
          'param': param,
          'newValue': value,
        };
      } finally {
        calloc.free(paramPtr);
        calloc.free(reasonPtr);
      }
    }
    if (result['accepted'] == true) parameters.update(param, value);
    return result;
  }

  /// Backward-compatible entry point used by the UI and agents.
  void applyTuning(String param, double value, {String? reason, String source = 'ui'}) {
    applyAction(param, value, reason: reason, source: source);
  }

  void setAgentEnabled(bool enabled) {
    final fn = _lib.setAgentEnabled;
    if (_pipeline != null && fn != null) fn(_pipeline!, enabled ? 1 : 0);
  }

  // ── Polling / records ─────────────────────────────────────────────────

  /// Latest snapshot. History receives one entry per distinct generation.
  Future<GenerationSnapshot?> pollSnapshot() async => readSnapshot();

  GenerationSnapshot? readSnapshot() {
    if (_pipeline == null) return null;
    final snap = _lib.callStringFn(() => _lib.getSnapshot(_pipeline!));
    if (snap.isEmpty) return null;
    try {
      final json = jsonDecode(snap) as Map<String, dynamic>;
      final result = snapshotFromCoreJson(json,
          history: history,
          elapsed: _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero);
      if (result.generation > _lastGeneration) {
        history.addSnapshot(result);
        _lastGeneration = result.generation;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Raw snapshot JSON (schema aegis.snapshot/2).
  Map<String, dynamic>? rawSnapshot() => _decodeMap(() => _lib.getSnapshot(_pipeline!));

  Map<String, dynamic>? pollStatus() => _decodeMap(() => _lib.getStatus(_pipeline!));

  List<Map<String, dynamic>> getTuningLog() {
    if (_pipeline == null) return [];
    final s = _lib.callStringFn(() => _lib.getTuningLog(_pipeline!));
    try {
      return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic>? getBestModel() => _decodeMap(() => _lib.getBestModel(_pipeline!));

  Map<String, dynamic>? getFinalReport() {
    final fn = _lib.getFinalReport;
    return fn == null ? null : _decodeMap(() => fn(_pipeline!));
  }

  Map<String, dynamic>? getConfig() {
    final fn = _lib.getConfig;
    return fn == null ? null : _decodeMap(() => fn(_pipeline!));
  }

  Map<String, dynamic>? getActionSchema() {
    final fn = _lib.getActionSchema;
    return fn == null ? null : _decodeMap(() => fn(_pipeline!));
  }

  List<dynamic> getHistoryRecords() {
    final fn = _lib.getHistory;
    if (_pipeline == null || fn == null) return const [];
    try {
      return jsonDecode(_lib.callStringFn(() => fn(_pipeline!))) as List;
    } catch (_) {
      return const [];
    }
  }

  String lastError() {
    final fn = _lib.getLastError;
    if (_pipeline == null || fn == null) return '';
    return _lib.callStringFn(() => fn(_pipeline!));
  }

  Map<String, dynamic>? _decodeMap(Pointer<Utf8> Function() call) {
    if (_pipeline == null) return null;
    final s = _lib.callStringFn(call);
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
}
