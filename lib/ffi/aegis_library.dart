// Conditional export: native FFI implementation on dart:io platforms,
// no-op stub on web (dart.library.js_interop is only available on web).
export 'aegis_library_native.dart'
    if (dart.library.js_interop) 'aegis_library_stub.dart';
