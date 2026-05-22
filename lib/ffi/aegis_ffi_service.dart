// Conditional export: native dart:ffi implementation on native platforms,
// no-op stub on web.
export 'aegis_ffi_service_native.dart'
    if (dart.library.js_interop) 'aegis_ffi_service_stub.dart';
