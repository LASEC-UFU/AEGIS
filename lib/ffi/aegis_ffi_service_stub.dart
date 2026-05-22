// Web stub for AegisFfiService — never instantiated on web because
// AegisLibrary.isAvailable == false guards all call sites.

import '../core/math/matrix.dart';
import '../agent/generation_snapshot.dart';
import '../agent/generation_history.dart';
import '../agent/tunable_parameter.dart';
import '../engine/de/de_engine.dart' show EngineState;
import 'aegis_library.dart';

class AegisFfiService {
  AegisFfiService(AegisLibrary lib);

  EngineState state = EngineState.idle;
  final GenerationHistory history = GenerationHistory();
  final ParameterRegistry parameters = ParameterRegistry();

  void Function(GenerationSnapshot)? onGenerationComplete;
  void Function(EngineState)?        onStateChanged;

  bool initialize({
    required Matrix normalizedData,
    Matrix? validationData,
    required int outputCol,
    required int numVariables,
    int numIslands = 3,
  }) => false;

  bool start()   => false;
  void pause()   {}
  void resume()  {}
  void stop()    {}
  void dispose() {}

  void applyTuning(String param, double value, {String? reason}) {}

  GenerationSnapshot? pollSnapshot() => null;
  Map<String, dynamic>? pollStatus()    => null;
  Map<String, dynamic>? getBestModel()  => null;
}
