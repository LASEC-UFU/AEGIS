#pragma once
#include "regressor_library.hpp"
#include <vector>
#include <complex>

namespace aegis {

/**
 * Stability / well-posedness analysis for (rational) NARX models.
 * See StabilityDiagnostics (metrics.hpp) for the definition of each field.
 */
class StabilityAnalyzer {
public:
    /** Denominator margin below which the singularity penalty starts. */
    static constexpr double kDenominatorMargin = 0.1;

    /**
     * Fill the penalty and is_stable flag of `d` from the observed
     * denominator statistics and free-run divergence:
     *   P = P_sing + P_div, with
     *   P_sing = 1 if D(k) changes sign along the data, else
     *            max(0, (δ − min|D|)/δ) with δ = kDenominatorMargin
     *            (0 for polynomial models),
     *   P_div  = 1 if the free-run simulation diverged.
     */
    static void finalize(StabilityDiagnostics& d, bool is_rational);

    /**
     * Spectral radius of the purely linear autoregressive part of the model
     * (numerator regressors made of a single output factor with exponent 1):
     *   y(k) = Σ_d a_d y(k−d) + …  →  z^n − a_1 z^{n−1} − … − a_n = 0.
     * Returns 0 if the model has no linear AR terms.
     */
    static double linear_spectral_radius(const Chromosome& chrom, int output_col);

    /**
     * Roots of the monic polynomial z^n + c[0] z^{n−1} + … + c[n−1]
     * (Durand–Kerner / Weierstrass iteration).
     */
    static std::vector<std::complex<double>> monic_roots(const std::vector<double>& c);
};

} // namespace aegis
