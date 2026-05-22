#pragma once
#include "regressor_library.hpp"
#include "metrics.hpp"
#include "residual_analyzer.hpp"
#include "stability_analyzer.hpp"

namespace aegis {

struct FitnessWeights {
    double alpha = 1.0;   // BIC penalty weight
    double beta  = 0.1;   // denominator-term penalty
    double gamma = 0.01;  // complexity penalty (regressors count)
    double delta = 0.01;  // exponent-range penalty
    double eta   = 1.0;   // stability penalty
};

struct EvalResult {
    bool          valid         = false;
    double        fitness       = std::numeric_limits<double>::infinity();
    ModelMetrics  metrics;
    ResidualStats residuals;
    StabilityResult stability;
    std::vector<double> err_values;
    bool          has_nan_inf   = false;
};

/**
 * Evaluates one Chromosome on training + optional validation data.
 *
 * Steps:
 *   1. Build Ψ matrix
 *   2. Apply pseudo-linearization (rational models)
 *   3. QR solve → coefficients
 *   4. Compute SSE, AIC, BIC, FPE, MDL
 *   5. RMSE on training + validation splits
 *   6. Compute ERR values
 *   7. Stability analysis
 *   8. Assemble composite fitness
 */
class IndividualEvaluator {
public:
    explicit IndividualEvaluator(const FitnessWeights& w = FitnessWeights())
        : weights_(w) {}

    EvalResult evaluate(
        Chromosome&   chrom,               // modified in-place: coefficients stored
        const double* train_data,          // row-major, train_rows × cols
        int           train_rows,
        const double* val_data,            // row-major, val_rows × cols (may be null)
        int           val_rows,
        int           cols,
        int           output_col
    ) const;

    /** Evaluate ERR for an already-fitted chromosome. */
    std::vector<double> compute_err(
        const Chromosome& chrom,
        const double* data, int rows, int cols, int output_col
    ) const;

    FitnessWeights& weights() noexcept { return weights_; }

private:
    FitnessWeights  weights_;
    StabilityAnalyzer stability_analyzer_;

    double compute_denom_penalty(const Chromosome& chrom) const noexcept;
    double compute_complexity_penalty(const Chromosome& chrom) const noexcept;
    double compute_exponent_penalty(const Chromosome& chrom,
                                    double pmin, double pmax) const noexcept;
};

} // namespace aegis
