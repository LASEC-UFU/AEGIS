// Web stub for AegisLibrary — no dart:ffi / dart:io available on web.
// All operations are no-ops; isAvailable always returns false.

class AegisLibrary {
  static AegisLibrary? get instance => null;
  static bool get isAvailable => false;

  /// Always returns false on web.
  static bool tryLoad() => false;

  /// Never called on web (isAvailable == false guards all call sites).
  String callStringFn(Function fn) => '';
}
