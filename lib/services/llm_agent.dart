// Conditional export: native implementation (dart:io + http) on native platforms,
// no-op stub on web.
export 'llm_agent_native.dart'
    if (dart.library.js_interop) 'llm_agent_stub.dart';
