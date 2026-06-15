import '../agent/generation_snapshot.dart';

typedef TuningSuggestion =
    void Function(String parameter, double value, String reason);

enum AgentMode { off, local, remote }

abstract class OptimizationAgent {
  TuningSuggestion? onSuggestion;

  String get name;
  bool get available;

  void processSnapshot(GenerationSnapshot snapshot);
  void dispose();
}
