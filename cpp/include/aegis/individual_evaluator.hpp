#pragma once
#include "regressor_library.hpp"
#include "metrics.hpp"
#include "residual_analyzer.hpp"
#include "stability_analyzer.hpp"

namespace aegis {

struct FitnessWeights {
    double alpha = 0.05;  // normalized BIC regularization weight
    double beta  = 0.1;   // denominator-term penalty
    double gamma = 0.01;  // complexity penalty (regressors count)
    double delta = 0.01;  // exponent-range penalty
    double eta   = 1.0;   // stability penalty
    double zeta  = 0.5;   // input-contribution deficit penalty
    double theta = 0.0;   // free-run (simulation) RMSE penalty weight
    int    free_run_horizon = 50; // samples used for free-run RMSE
    double input_contribution_target = 0.3;
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

    /** Recompute only the composite fitness after objective weights change. */
    bool rescore(Chromosome& chrom, int output_col) const;

    /** Evaluate ERR for an already-fitted chromosome. */
    std::vector<double> compute_err(
        const Chromosome& chrom,
        const double* data, int rows, int cols, int output_col
    ) const;

    FitnessWeights& weights() noexcept { return weights_; }
    const FitnessWeights& weights() const noexcept { return weights_; }

private:
    FitnessWeights  weights_;
    StabilityAnalyzer stability_analyzer_;

    double compute_denom_penalty(const Chromosome& chrom) const noexcept;
    double compute_complexity_penalty(const Chromosome& chrom) const noexcept;
    double compute_exponent_penalty(const Chromosome& chrom,
                                    double pmin, double pmax) const noexcept;
    /** Returns 1.0 if no regressor depends on an input variable (model is
     *  purely autoregressive in the output), 0.0 otherwise. */
    double compute_no_input_penalty(const Chromosome& chrom, int output_col) const noexcept;

    /** Fraction of ERR mass attributed to regressors that depend on at
     *  least one input variable (variable != output_col). In [0,1]. */
    double compute_input_contribution_ratio(const Chromosome& chrom, int output_col) const noexcept;

    /** Max |Pearson correlation| between residuals and each input variable
     *  (lag 0), used to detect unmodeled input-dependent structure. */
    double compute_residual_input_corr(
        const std::vector<double>& residuals,
        const double* data, int rows, int cols, int output_col, int max_delay
    ) const noexcept;
};

} // namespace aegis
