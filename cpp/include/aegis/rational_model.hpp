#pragma once
#include "regressor_library.hpp"
#include <vector>
#include <string>

namespace aegis {

/**
 * Rational NARX model:
 *   y_hat(k) = N(k) / D(k)
 *   N(k) = Σ_{j∈ℕ} θ_j · φ_j(k)
 *   D(k) = 1 + Σ_{j∈𝒟} θ_j · φ_j(k)
 *
 * Fitting uses pseudo-linearization + Householder QR.
 */
class RationalModel {
public:
    RationalModel() = default;
    explicit RationalModel(const Chromosome& chrom) : chrom_(chrom) {}

    /**
     * Fit the model on training data (row-major, rows × cols).
     * Computes coefficients via pseudo-linearized least squares.
     * Returns false on degenerate systems.
     */
    bool fit(
        const double* data, int rows, int cols, int output_col
    );

    /**
     * One-step-ahead prediction (uses actual y for denominator evaluation).
     * Returns a vector of length (rows - max_delay).
     */
    std::vector<double> predict_one_step(
        const double* data, int rows, int cols, int output_col
    ) const;

    /**
     * Free-run (simulation) prediction — uses predicted y for future samples.
     * Returns a vector of length (rows - max_delay).
     */
    std::vector<double> predict_free_run(
        const double* data, int rows, int cols, int output_col
    ) const;

    /**
     * Evaluate the rational formula at a single time step k.
     * Requires all delayed values to be available (k ≥ max_delay).
     *
     * y_prev : length = max_delay, y_prev[0] = y(k-1), …
     *          (used for denominator terms referencing the output)
     */
    double evaluate_at(
        const double* data, int k, int rows, int cols,
        const double* y_prev, int output_col
    ) const noexcept;

    const Chromosome& chromosome()       const noexcept { return chrom_; }
    Chromosome&       chromosome_mut()         noexcept { return chrom_; }

    /** LaTeX-style equation string for display. */
    std::string equation_string() const;

private:
    Chromosome chrom_;

    double eval_numerator  (const double* data, int k, int rows, int cols,
                             const double* y_buf, int output_col) const noexcept;
    double eval_denominator(const double* data, int k, int rows, int cols,
                             const double* y_buf, int output_col) const noexcept;
};

} // namespace aegis
