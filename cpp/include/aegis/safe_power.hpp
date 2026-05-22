#pragma once
#include <cmath>
#include <algorithm>
#include <limits>

namespace aegis {

constexpr double kEpsilon = 1e-6;

/**
 * Safe power for strictly non-negative base: pow(max(x, ε), p).
 * Avoids NaN/Inf from negative bases with fractional exponents.
 */
inline double safe_power(double x, double p, double eps = kEpsilon) noexcept {
    const double base = std::max(x, eps);
    const double result = std::pow(base, p);
    if (!std::isfinite(result)) return std::numeric_limits<double>::max() * 1e-10;
    return result;
}

/**
 * Signed power: sign(x) * pow(|x| + ε, p).
 * Preserves sign and allows negative inputs.
 */
inline double signed_power(double x, double p, double eps = kEpsilon) noexcept {
    const double sign = (x >= 0.0) ? 1.0 : -1.0;
    const double result = sign * std::pow(std::abs(x) + eps, p);
    if (!std::isfinite(result)) return sign * std::numeric_limits<double>::max() * 1e-10;
    return result;
}

/** Clamp value to [lo, hi]. */
inline double clamp(double v, double lo, double hi) noexcept {
    return std::max(lo, std::min(hi, v));
}

/** Quantize p to the nearest multiple of step in [pmin, pmax]. */
inline double quantize_exponent(double p, double pmin, double pmax,
                                double step = 0.0) noexcept {
    p = clamp(p, pmin, pmax);
    if (step > 0.0) p = std::round(p / step) * step;
    return clamp(p, pmin, pmax);
}

/** Returns true if v is a usable finite number. */
inline bool is_valid(double v) noexcept {
    return std::isfinite(v) && !std::isnan(v);
}

} // namespace aegis
