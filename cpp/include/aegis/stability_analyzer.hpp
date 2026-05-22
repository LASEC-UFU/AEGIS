#pragma once
#include "regressor_library.hpp"
#include <vector>
#include <complex>

namespace aegis {

struct StabilityResult {
    bool   is_stable       = true;
    double stability_margin = 1.0;  // distance of closest pole from unit circle
    std::vector<std::complex<double>> denominator_roots;
    double penalty         = 0.0;   // penalty to add to fitness
};

class StabilityAnalyzer {
public:
    /**
     * Analyse stability of a rational model.
     * For polynomial models (no denominator terms) → always stable.
     * For rational models, computes denominator polynomial roots and checks |z| < 1.
     *
     * Uses linearized denominator coefficients from fitted chromosome.
     */
    StabilityResult analyze(const Chromosome& chrom) const;

    /**
     * Compute roots of polynomial with coefficients c[0] + c[1]z + ... + c[n]z^n.
     * Uses companion matrix + eigen-decomposition (power iteration fallback).
     */
    static std::vector<std::complex<double>> poly_roots(
        const std::vector<double>& coeffs
    );

private:
    /** Build the denominator polynomial from a rational Chromosome. */
    std::vector<double> extract_denom_poly(const Chromosome& chrom) const;
};

} // namespace aegis
