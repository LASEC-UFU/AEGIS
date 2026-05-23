// Conditional export: native dart:ffi on native, WASM bridge on web.
export 'aegis_ffi_service_native.dart'
    if (dart.library.js_interop) 'aegis_wasm_service.dart';
