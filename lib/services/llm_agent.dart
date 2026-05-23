// Conditional export: native (dart:io + http) on native, web (localStorage + http) on web.
export 'llm_agent_native.dart'
    if (dart.library.js_interop) 'llm_agent_web.dart';
