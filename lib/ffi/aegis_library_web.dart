// Web implementation of AegisLibrary — backed by the WASM bridge loaded by
// aegis_wasm_loader.js.  isAvailable is true once window.AegisWasmReady fires.

import 'dart:async';
import 'dart:js_interop';

@JS('AegisWasm.isReady')
external bool _jsIsReady();

class AegisLibrary {
  static AegisLibrary? _instance;

  static AegisLibrary? get instance {
    if (_instance == null && isAvailable) _instance = AegisLibrary._();
    return _instance;
  }

  static bool get isAvailable {
    try {
      return _jsIsReady();
    } catch (_) {
      return false;
    }
  }

  /// Attempt to initialise.  Returns true if WASM is ready.
  static bool tryLoad() {
    if (isAvailable) {
      _instance ??= AegisLibrary._();
      return true;
    }
    return false;
  }

  /// Wait for the AegisWasmReady DOM event then resolve the instance.
  static Future<bool> waitForWasm() {
    final completer = Completer<bool>();
    if (isAvailable) {
      _instance ??= AegisLibrary._();
      return Future.value(true);
    }
    // Listen once for the custom event dispatched by aegis_wasm_loader.js
    _listenOnce(completer);
    return completer.future;
  }

  AegisLibrary._();
}

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

void _listenOnce(Completer<bool> completer) {
  late JSFunction handler;
  handler = (JSAny? _) {
    AegisLibrary._instance ??= AegisLibrary._();
    if (!completer.isCompleted) completer.complete(true);
  }.toJS;
  _addEventListener('AegisWasmReady'.toJS, handler);
}
