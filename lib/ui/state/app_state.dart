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
import '../../services/llm_agent.dart';

// ─── Data providers ───────────────────────────────────────────

final loadedDataProvider = StateProvider<DataLoadResult?>((ref) => null);
final variableNamesProvider = StateProvider<List<String>>((ref) => []);
final inputIndicesProvider = StateProvider<List<int>>((ref) => []);
final outputIndexProvider = StateProvider<int>((ref) => 0);

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

  // ── LLM agent (Claude API, active only when C++ engine is running) ───────
  LlmAgent? _agent;

  EngineNotifier(this._ref) : super(const EngineUiState());

  bool get _usingCpp => _ffiService != null;

  DEEngine? get engine => _engine;

  GenerationHistory? get history =>
      _usingCpp ? _ffiService!.history : _engine?.history;

  ParameterRegistry? get parameters =>
      _usingCpp ? _ffiService!.parameters : _engine?.parameters;

  // ── Initialize ─────────────────────────────────────────────────────────

  void initialize({int numIslands = 3}) {
    final data = _ref.read(loadedDataProvider);
    if (data == null) return;

    final outputCol = _ref.read(outputIndexProvider);

    // Normalize
    final normalized = DataNormalizer.normalize(data.data);

    // Split
    final split = DataSplitter.split(normalized.data);

    // Try C++ backend first (available on Windows with native build)
    if (AegisLibrary.isAvailable) {
      _ffiService?.dispose();
      _ffiService = AegisFfiService(AegisLibrary.instance!);
      _ffiService!.onGenerationComplete = _onGeneration;
      _ffiService!.onStateChanged = _onStateChanged;
      final ok = _ffiService!.initialize(
        normalizedData: split.training,
        validationData: split.validation,
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
    if (_usingCpp) {
      _ffiService!.start();
      _agent ??= LlmAgent()
        ..onSuggestion = (p, v, r) => applyTuning(p, v, reason: r);
      // Poll the C++ engine every ~16 ms for snapshots
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
      return;
    }

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
    start();
  }

  // ── Agent tuning ───────────────────────────────────────────────────────

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

    _agent?.processSnapshot(snapshot);

    state = EngineUiState(
      state: engineState,
      generation: snapshot.generation,
      latestSnapshot: snapshot,
      bestFitness: snapshot.bestFitness,
      elapsed: snapshot.elapsed,
      statusMessage: 'Gen ${snapshot.generation} | '
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
