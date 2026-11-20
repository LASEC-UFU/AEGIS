import 'dart:math' as math;

/// Power basis shared with the C++ core (PowerMode::Hybrid, see
/// cpp/include/aegis/safe_power.hpp):
///   integer p     → x^p exactly (even powers are even functions)
///   non-integer p → sign(x)·|x|^p (odd extension, real for x < 0)
double powerBasis(double x, double p) {
  if (p == 1.0) return x;
  final r = p.roundToDouble();
  if ((p - r).abs() <= 1e-9 && r >= 0 && r <= 64) {
    var n = r.toInt();
    var result = 1.0, b = x;
    while (n > 0) {
      if (n & 1 == 1) result *= b;
      b *= b;
      n >>= 1;
    }
    return result;
  }
  final a = math.pow(x.abs(), p).toDouble();
  return x < 0 ? -a : a;
}
