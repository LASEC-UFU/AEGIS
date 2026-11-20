// Web variant of LlmAgent: same logic as the native agent (llm_agent_core),
// only the API-key source differs (browser localStorage, set by the user in
// the UI). Calling the API from a browser exposes the key to that browser
// session, which is why the Anthropic API requires the explicit header
// `anthropic-dangerous-direct-browser-access`. Use only with your own key on
// your own machine.

import 'dart:js_interop';


import 'llm_agent_core.dart';

@JS('aegisGetLocalStorage')
external JSString _jsGetLocalStorage(JSString key);

@JS('aegisSetLocalStorage')
external void _jsSetLocalStorage(JSString key, JSString value);

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
         apiKeyProvider: () => apiKey ?? _readKeyFromStorage(),
         extraHeaders: const {'anthropic-dangerous-direct-browser-access': 'true'},
       );

  static String _readKeyFromStorage() {
    try {
      return _jsGetLocalStorage('ANTHROPIC_API_KEY'.toJS).toDart;
    } catch (_) {
      return '';
    }
  }

  /// Persist the key so it survives page reloads.
  static void saveKeyToStorage(String key) {
    try {
      _jsSetLocalStorage('ANTHROPIC_API_KEY'.toJS, key.toJS);
    } catch (_) {}
  }
}

