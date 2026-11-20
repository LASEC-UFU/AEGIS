#pragma once
#include "regressor_library.hpp"
#include <vector>
#include <string>
#include <limits>

namespace aegis {

/** Denominator statistics gathered while predicting with a rational model. */
struct DenominatorStats {
    double min_abs     = std::numeric_limits<double>::infinity();
    int    sign_changes = 0;
    int    samples      = 0;
    void add(double d, double& prev) noexcept {
        const double a = std::abs(d);
        if (a < min_abs) min_abs = a;
        if (samples > 0 && ((d < 0.0) != (prev < 0.0))) ++sign_changes;
        prev = d;
        ++samples;
    }
};

/** Result of a free-run (simulation) prediction. */
struct FreeRunResult {
    std::vector<double> yhat;           // predictions for k = first_k .. first_k+n-1
    bool   diverged        = false;     // non-finite or |ŷ| > bound at some step
    int    divergence_step = -1;        // index into yhat of the first divergent step
    DenominatorStats den;
};

/**
 * Rational NARX model:
 *   y_hat(k) = N(k) / D(k)
 *   N(k) = c + Σ_{j∈ℕ} θ_j · φ_j(k)
 *   D(k) = 1 + Σ_{j∈𝒟} θ_j · φ_j(k)
 *
 * Fitting uses pseudo-linearization + Householder QR (an equation-error
 * estimator; biased under output noise for rational models).
 */
class RationalModel {
public:
    RationalModel() = default;
    explicit RationalModel(const Chromosome& chrom) : chrom_(chrom) {}

    /** Fit on training data (row-major, rows × cols). Returns false on degenerate systems. */
    bool fit(const double* data, int rows, int cols, int output_col);

    /**
     * Fit from a precomputed (non-linearized) Ψ and target vector.
     * psi: usable × nr, row-major. Stores coefficients/intercept in chrom.
     */
    static bool fit_from_psi(Chromosome& chrom, const std::vector<double>& psi,
                             int usable, const double* y);

    /**
     * One-step-ahead predictions from a precomputed (non-linearized) Ψ.
     * Writes usable predictions into yhat.
     */
    static void predict_from_psi(const Chromosome& chrom, const std::vector<double>& psi,
                                 int usable, std::vector<double>& yhat,
                                 DenominatorStats* den = nullptr);

    /**
     * One-step-ahead prediction (measured y in the regressors).
     * Returns a vector of length (rows - max_delay).
     */
    std::vector<double> predict_one_step(
        const double* data, int rows, int cols, int output_col,
        DenominatorStats* den = nullptr
    ) const;

    /**
     * Free-run simulation over data rows [0, rows): the first max_delay
     * outputs are taken from the data as initial conditions, afterwards the
     * model's own predictions are fed back. At most `horizon` steps are
     * simulated (horizon ≤ 0 → all). Divergence is detected when a prediction
     * is non-finite or |ŷ| > bound; from then on predictions are saturated
     * at ±bound so error metrics stay finite and comparable.
     */
    FreeRunResult simulate(
        const double* data, int rows, int cols, int output_col,
        int horizon = -1,
        double bound = std::numeric_limits<double>::infinity()
    ) const;

    /** Backward-compatible wrapper around simulate(). */
    std::vector<double> predict_free_run(
        const double* data, int rows, int cols, int output_col,
        int horizon = -1
    ) const { return simulate(data, rows, cols, output_col, horizon).yhat; }

    /** Evaluate the rational formula at a single time step k ≥ max_delay. */
    double evaluate_at(
        const double* data, int k, int rows, int cols,
        const double* y_prev, int output_col
    ) const noexcept;

    /** Numerator and denominator at time step k. */
    void num_den_at(const double* data, int k, int rows, int cols,
                    double& num, double& den) const noexcept;

    const Chromosome& chromosome()       const noexcept { return chrom_; }
    Chromosome&       chromosome_mut()         noexcept { return chrom_; }

    /** Human-readable equation string (variable indices, basis noted). */
    std::string equation_string() const;

private:
    Chromosome chrom_;
};

/** Smallest denominator magnitude that is still divided by (guard). */
constexpr double kMinDenominator = 1e-12;

} // namespace aegis
