// Web stub — LlmAgent is never instantiated on web (C++ engine unavailable).
import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

class LlmAgent implements OptimizationAgent {
  @override
  TuningSuggestion? onSuggestion;

  LlmAgent({String? apiKey});

  bool get hasApiKey => false;

  @override
  String get name => 'Claude remoto';

  @override
  bool get available => false;

  @override
  void processSnapshot(GenerationSnapshot snap) {}

  @override
  void dispose() {}
}
