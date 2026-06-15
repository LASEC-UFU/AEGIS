import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/data_loader.dart';
import '../../engine/de/de_engine.dart';
import '../../engine/identification/data_normalizer.dart';
import '../../engine/identification/data_splitter.dart';
import '../../agent/generation_snapshot.dart';
import '../../agent/generation_history.dart';
import '../../agent/tunable_parameter.dart';
import '../../ffi/aegis_library.dart';
import '../../ffi/aegis_ffi_service.dart';
import '../../services/local_adaptive_agent.dart';
import '../../services/llm_agent.dart';
import '../../services/optimization_agent.dart';

// ─── Data providers ───────────────────────────────────────────

final loadedDataProvider = StateProvider<DataLoadResult?>((ref) => null);
final variableNamesProvider = StateProvider<List<String>>((ref) => []);
final inputIndicesProvider = StateProvider<List<int>>((ref) => []);
final outputIndexProvider = StateProvider<int>((ref) => 0);
final agentModeProvider = StateProvider<AgentMode>((ref) => AgentMode.local);

// ─── Engine provider ─────────────────────────────────────────

final engineProvider = StateNotifierProvider<EngineNotifier, EngineUiState>((
  ref,
) {
  return EngineNotifier(ref);
});

class EngineUiState {
  final EngineState state;
  final int generation;
  final GenerationSnapshot? latestSnapshot;
  final String? statusMessage;
  final double? bestFitness;
  final Duration elapsed;

  const EngineUiState({
    this.state = EngineState.idle,
    this.generation = 0,
    this.latestSnapshot,
    this.statusMessage,
    this.bestFitness,
    this.elapsed = Duration.zero,
  });

  EngineUiState copyWith({
    EngineState? state,
    int? generation,
    GenerationSnapshot? latestSnapshot,
    String? statusMessage,
    double? bestFitness,
    Duration? elapsed,
  }) {
    return EngineUiState(
      state: state ?? this.state,
      generation: generation ?? this.generation,
      latestSnapshot: latestSnapshot ?? this.latestSnapshot,
      statusMessage: statusMessage ?? this.statusMessage,
      bestFitness: bestFitness ?? this.bestFitness,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

class EngineNotifier extends StateNotifier<EngineUiState> {
  final Ref _ref;

  // ── Dart engine (always available — web + native fallback) ─────────────
  DEEngine? _engine;
  Timer? _runTimer;

  // ── C++ FFI engine (Windows native only) ──────────────────────────────
  AegisFfiService? _ffiService;
  Timer? _pollTimer;

  // ── Adaptive supervisor (local policy or remote Claude API) ─────────────
  OptimizationAgent? _agent;
  AgentMode? _activeAgentMode;

  EngineNotifier(this._ref) : super(const EngineUiState()) {
    _ensureAgent();
  }

  bool get _usingCpp => _ffiService != null;

  bool get usingCpp => _usingCpp;

  DEEngine? get engine => _engine;

  /// Best model (final result) from the C++ engine, as raw JSON.
  /// Returns null if unavailable or not using the C++ backend.
  Map<String, dynamic>? getBestModelJson() => _ffiService?.getBestModel();

  /// Log of tuning actions applied by the active backend.
  List<Map<String, dynamic>> getTuningLog() {
    if (_usingCpp) return _ffiService?.getTuningLog() ?? [];
    return (_engine?.history.tuningActions ?? [])
        .map(
          (action) => {
            'accepted': true,
            'param': action.parameterName,
            'oldValue': action.oldValue,
            'newValue': action.newValue,
            'generation': action.generation,
            'reason': action.reason ?? '',
            'rejectionReason': '',
          },
        )
        .toList();
  }

  String get agentName => _agent?.name ?? 'Agente desligado';
  bool get agentAvailable => _agent?.available ?? true;

  GenerationHistory? get history =>
      _usingCpp ? _ffiService!.history : _engine?.history;

  ParameterRegistry? get parameters =>
      _usingCpp ? _ffiService!.parameters : _engine?.parameters;

  // ── Initialize ─────────────────────────────────────────────────────────

  void initialize({int numIslands = 3}) {
    final data = _ref.read(loadedDataProvider);
    if (data == null) return;
    _ensureAgent(force: true);

    final outputCol = _ref.read(outputIndexProvider);

    // The C++/WASM pipeline owns normalization and sequential splitting.
    // Pass the complete raw series so it does not split an already-split set.
    if (AegisLibrary.isAvailable) {
      _ffiService?.dispose();
      _ffiService = AegisFfiService(AegisLibrary.instance!);
      _ffiService!.onGenerationComplete = _onGeneration;
      _ffiService!.onStateChanged = _onStateChanged;
      final ok = _ffiService!.initialize(
        normalizedData: data.data,
        outputCol: outputCol,
        numVariables: data.numCols,
        numIslands: numIslands,
      );
      if (ok) {
        _engine = null; // disable Dart engine when C++ is active
        state = state.copyWith(
          state: EngineState.idle,
          generation: 0,
          statusMessage:
              '[C++ core] Initialized with ${data.numRows} samples, '
              '${data.numCols} variables',
        );
        return;
      }
      // C++ init failed — fall through to Dart engine
      _ffiService?.dispose();
      _ffiService = null;
    }

    // Dart fallback owns its own normalization and split.
    final normalized = DataNormalizer.normalize(
      data.data,
      fitRows: (data.numRows * 0.7).floor(),
    );
    final split = DataSplitter.split(normalized.data);

    // Dart engine fallback (web + native without DLL)
    _engine = DEEngine(numIslands: numIslands);
    _engine!.initialize(
      normalizedData: split.training,
      validationData: split.validation,
      outputCol: outputCol,
      numVariables: data.numCols,
    );

    _engine!.onGenerationComplete = _onGeneration;
    _engine!.onStateChanged = _onStateChanged;

    state = state.copyWith(
      state: EngineState.idle,
      generation: 0,
      statusMessage:
          'Initialized with ${data.numRows} samples, ${data.numCols} variables',
    );
  }

  // ── Start ──────────────────────────────────────────────────────────────

  void start() {
    _ensureAgent();
    if (_usingCpp) {
      if (_ffiService!.start()) _startCppPolling();
      return;
    }

    _startDartLoop();
  }

  void _startCppPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final snap = _ffiService?.pollSnapshot();
      if (snap != null) _onGeneration(snap);

      final status = _ffiService?.pollStatus();
      if (status != null) {
        final stateStr = status['state'] as String? ?? '';
        if (stateStr == 'completed') {
          _pollTimer?.cancel();
          _onStateChanged(EngineState.completed);
        } else if (stateStr == 'stopped') {
          _pollTimer?.cancel();
          _onStateChanged(EngineState.stopped);
        }
      }
    });
  }

  void _startDartLoop() {
    if (_engine == null) return;
    _runTimer?.cancel();
    _runTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_engine!.state == EngineState.paused ||
          _engine!.state == EngineState.stopped ||
          _engine!.state == EngineState.completed) {
        _runTimer?.cancel();
        return;
      }
      final shouldContinue = _engine!.runBatch();
      if (!shouldContinue) _runTimer?.cancel();
    });
  }

  // ── Pause / Stop / Resume ──────────────────────────────────────────────

  void pause() {
    if (_usingCpp) {
      _ffiService?.pause();
      _pollTimer?.cancel();
    } else {
      _engine?.pause();
      _runTimer?.cancel();
    }
  }

  void stop() {
    if (_usingCpp) {
      _ffiService?.stop();
      _pollTimer?.cancel();
    } else {
      _engine?.stop();
      _runTimer?.cancel();
    }
  }

  void resume() {
    if (_usingCpp) {
      _ffiService?.resume();
      _startCppPolling();
    } else {
      _startDartLoop();
    }
  }

  // ── Agent tuning ───────────────────────────────────────────────────────

  void setAgentMode(AgentMode mode) {
    _ref.read(agentModeProvider.notifier).state = mode;
    _ensureAgent(force: true);
  }

  void _ensureAgent({bool force = false}) {
    final mode = _ref.read(agentModeProvider);
    if (!force && mode == _activeAgentMode) return;

    _agent?.dispose();
    _agent = switch (mode) {
      AgentMode.off => null,
      AgentMode.local => LocalAdaptiveAgent(
        currentParameters: () =>
            parameters?.currentValues ?? const <String, double>{},
      ),
      AgentMode.remote => LlmAgent(),
    };
    _activeAgentMode = mode;
    _agent?.onSuggestion = (parameter, value, reason) {
      applyTuning(parameter, value, reason: reason);
    };
  }

  void applyTuning(String param, double value, {String? reason}) {
    if (_usingCpp) {
      _ffiService?.applyTuning(param, value, reason: reason);
    } else {
      _engine?.applyTuning(param, value, reason: reason);
    }
  }

  // ── Callbacks ──────────────────────────────────────────────────────────

  void _onGeneration(GenerationSnapshot snapshot) {
    final engineState = _usingCpp
        ? (_ffiService?.state ?? EngineState.running)
        : (_engine?.state ?? EngineState.idle);

    _ensureAgent();
    _agent?.processSnapshot(snapshot);

    state = EngineUiState(
      state: engineState,
      generation: snapshot.generation,
      latestSnapshot: snapshot,
      bestFitness: snapshot.bestFitness,
      elapsed: snapshot.elapsed,
      statusMessage:
          'Gen ${snapshot.generation} | '
          'Best: ${snapshot.bestFitness.toStringAsFixed(4)} | '
          'R²: ${snapshot.bestModelR2.toStringAsFixed(4)}',
    );
  }

  void _onStateChanged(EngineState engineState) {
    state = state.copyWith(state: engineState);
  }

  // ── Dispose ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _runTimer?.cancel();
    _pollTimer?.cancel();
    _agent?.dispose();
    _ffiService?.dispose();
    super.dispose();
  }
}

// ─── Convenience providers ───────────────────────────────────

final snapshotProvider = Provider<GenerationSnapshot?>((ref) {
  return ref.watch(engineProvider).latestSnapshot;
});

final fitnessHistoryProvider = Provider<List<double>>((ref) {
  final engineNotifier = ref.watch(engineProvider.notifier);
  return engineNotifier.history?.fitnessHistory ?? [];
});

final parameterRegistryProvider = Provider<ParameterRegistry?>((ref) {
  final engineNotifier = ref.watch(engineProvider.notifier);
  return engineNotifier.parameters;
});
