// Stub LlmAgent for platforms without network access (never instantiated).
import '../agent/generation_snapshot.dart';
import 'optimization_agent.dart';

class LlmAgent extends OptimizationAgent {
  LlmAgent({String? apiKey});

  bool get hasApiKey => false;

  @override
  String get id => 'llm';

  @override
  String get name => 'Claude remoto';

  @override
  bool get available => false;

  @override
  void processSnapshot(GenerationSnapshot snapshot) {}

  @override
  void dispose() {}
}
