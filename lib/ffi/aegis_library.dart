// Conditional export: native FFI on dart:io platforms, WASM bridge on web.
export 'aegis_library_native.dart'
    if (dart.library.js_interop) 'aegis_library_web.dart';
