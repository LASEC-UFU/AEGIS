// Conditional export: native dart:io on Windows/Linux/macOS,
// browser File API on web (WASM).
export 'file_io_native.dart'
    if (dart.library.js_interop) 'file_io_web.dart';
