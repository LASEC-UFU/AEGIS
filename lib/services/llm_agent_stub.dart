// Web stub — LlmAgent is never instantiated on web (C++ engine unavailable).
import '../agent/generation_snapshot.dart';

typedef TuningSuggestion = void Function(
    String param, double value, String reason);

class LlmAgent {
  TuningSuggestion? onSuggestion;

  LlmAgent({String? apiKey});

  bool get hasApiKey => false;

  void processSnapshot(GenerationSnapshot snap) {}
  void dispose() {}
}
