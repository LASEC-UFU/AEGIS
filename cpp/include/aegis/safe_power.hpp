#pragma once
#include <cmath>
#include <algorithm>
#include <limits>
#include <string>

namespace aegis {

constexpr double kEpsilon = 1e-6;

/**
 * Basis used to raise a lagged signal x to a (possibly fractional) exponent p.
 *
 *  Hybrid (default since the 2026-11 audit):
 *      p integer      → x^p exactly (ordinary polynomial NARX term; even
 *                        powers are even functions)
 *      p non-integer  → sign(x)·|x|^p (odd extension, real-valued for x<0)
 *  Signed:
 *      sign(x)·|x|^p for every p (odd-symmetric basis; x² becomes x|x|)
 *  Legacy:
 *      sign(x)·(|x|+1e-6)^p — exact semantics of AEGIS ≤ 9e4b1d8, kept only
 *      to reproduce/import models produced by the original code.
 *
 * The mode is a property of the model and is exported with it.
 */
enum class PowerMode : int { Hybrid = 0, Signed = 1, Legacy = 2 };

inline const char* power_mode_name(PowerMode m) {
    switch (m) {
        case PowerMode::Hybrid: return "hybrid";
        case PowerMode::Signed: return "signed";
        case PowerMode::Legacy: return "legacy";
    }
    return "hybrid";
}

inline PowerMode power_mode_from_name(const std::string& s, PowerMode def = PowerMode::Hybrid) {
    if (s == "hybrid") return PowerMode::Hybrid;
    if (s == "signed") return PowerMode::Signed;
    if (s == "legacy") return PowerMode::Legacy;
    return def;
}

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
 * Legacy signed power: sign(x) * pow(|x| + ε, p).
 */
inline double signed_power(double x, double p, double eps = kEpsilon) noexcept {
    const double sign = (x >= 0.0) ? 1.0 : -1.0;
    const double result = sign * std::pow(std::abs(x) + eps, p);
    if (!std::isfinite(result)) return sign * std::numeric_limits<double>::max() * 1e-10;
    return result;
}

/** x^n for a small non-negative integer n by repeated squaring. */
inline double int_power(double x, int n) noexcept {
    double r = 1.0, b = x;
    while (n > 0) {
        if (n & 1) r *= b;
        b *= b;
        n >>= 1;
    }
    return r;
}

/** True when p is (numerically) a non-negative integer ≤ 64. */
inline bool is_integer_exponent(double p, int* n_out = nullptr) noexcept {
    const double r = std::round(p);
    if (std::abs(p - r) > 1e-9 || r < 0.0 || r > 64.0) return false;
    if (n_out) *n_out = static_cast<int>(r);
    return true;
}

/** Raise x to p under the given basis. Never returns NaN for finite x. */
inline double power_basis(double x, double p, PowerMode mode) noexcept {
    switch (mode) {
        case PowerMode::Legacy:
            return signed_power(x, p, kEpsilon);
        case PowerMode::Signed: {
            if (p == 1.0) return x;
            int n;
            if (is_integer_exponent(p, &n) && (n & 1)) return int_power(x, n); // odd: identical
            const double r = std::pow(std::abs(x), p);
            return x < 0.0 ? -r : r;
        }
        case PowerMode::Hybrid:
        default: {
            if (p == 1.0) return x;
            int n;
            if (is_integer_exponent(p, &n)) return int_power(x, n);
            const double r = std::pow(std::abs(x), p);
            return x < 0.0 ? -r : r;
        }
    }
}

/** Clamp value to [lo, hi]. */
inline double clamp(double v, double lo, double hi) noexcept {
    return std::max(lo, std::min(hi, v));
}

/**
 * Quantize p to the nearest multiple of step, then clamp to [pmin, pmax].
 * step ≤ 0 keeps the exponent continuous.
 */
inline double quantize_exponent(double p, double pmin, double pmax,
                                double step = 0.0) noexcept {
    p = clamp(p, pmin, pmax);
    if (step > 0.0) p = std::round(p / step) * step;
    return clamp(p, pmin, pmax);
}

/** Returns true if v is a usable finite number. */
inline bool is_valid(double v) noexcept {
    return std::isfinite(v);
}

} // namespace aegis
