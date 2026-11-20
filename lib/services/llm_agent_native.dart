import 'dart:io';


import 'llm_agent_core.dart';

/// Claude-backed supervisor (native platforms).
///
/// API key resolution order (the key is never logged or written anywhere):
///   1. constructor argument
///   2. ANTHROPIC_API_KEY environment variable
///   3. file `anthropic_api_key.txt` next to the executable (git-ignored)
class LlmAgent extends LlmAgentCore {
  LlmAgent({
    String? apiKey,
    super.client,
    super.model,
    super.effort,
    super.consultEvery,
    super.timeout,
    super.maxCalls,
    super.maxCostUsd,
    super.serverSideFallback,
  }) : super(
         apiKeyProvider: _resolver(apiKey),

       );

  static String Function() _resolver(String? explicit) {
    String? cached;
    return () => cached ??= explicit ?? Platform.environment['ANTHROPIC_API_KEY'] ?? _readKeyFile();
  }

  static String _readKeyFile() {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final f = File('$dir/anthropic_api_key.txt');
      if (f.existsSync()) return f.readAsStringSync().trim();
    } catch (_) {}
    return '';
  }
}
