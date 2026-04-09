import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/data_loader.dart';
import '../../engine/de/de_engine.dart';
import '../../engine/identification/data_normalizer.dart';
import '../../engine/identification/data_splitter.dart';
import '../../agent/generation_snapshot.dart';
import '../../agent/generation_history.dart';
import '../../agent/tunable_parameter.dart';

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
  DEEngine? _engine;
  Timer? _runTimer;

  EngineNotifier(this._ref) : super(const EngineUiState());

  DEEngine? get engine => _engine;
  GenerationHistory? get history => _engine?.history;
  ParameterRegistry? get parameters => _engine?.parameters;

  void initialize({int numIslands = 3}) {
    final data = _ref.read(loadedDataProvider);
    if (data == null) return;

    final outputCol = _ref.read(outputIndexProvider);

    // Normalize
    final normalized = DataNormalizer.normalize(data.data);

    // Split
    final split = DataSplitter.split(normalized.data);

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

  void start() {
    if (_engine == null) return;
    // Use a periodic timer to yield frames for UI updates
    _runTimer?.cancel();
    _runTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_engine!.state == EngineState.paused ||
          _engine!.state == EngineState.stopped ||
          _engine!.state == EngineState.completed) {
        _runTimer?.cancel();
        return;
      }
      final shouldContinue = _engine!.runBatch();
      if (!shouldContinue) {
        _runTimer?.cancel();
      }
    });
  }

  void pause() {
    _engine?.pause();
    _runTimer?.cancel();
  }

  void stop() {
    _engine?.stop();
    _runTimer?.cancel();
  }

  void resume() {
    start();
  }

  void applyTuning(String param, double value, {String? reason}) {
    _engine?.applyTuning(param, value, reason: reason);
  }

  void _onGeneration(GenerationSnapshot snapshot) {
    state = EngineUiState(
      state: _engine?.state ?? EngineState.idle,
      generation: snapshot.generation,
      latestSnapshot: snapshot,
      bestFitness: snapshot.bestFitness,
      elapsed: snapshot.elapsed,
      statusMessage:
          'Gen ${snapshot.generation} | Best: ${snapshot.bestFitness.toStringAsFixed(4)} | R²: ${snapshot.bestModelR2.toStringAsFixed(4)}',
    );
  }

  void _onStateChanged(EngineState engineState) {
    state = state.copyWith(state: engineState);
  }

  @override
  void dispose() {
    _runTimer?.cancel();
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
