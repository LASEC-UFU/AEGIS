#pragma once
#include "regressor_library.hpp"
#include "metrics.hpp"
#include "residual_analyzer.hpp"
#include "stability_analyzer.hpp"
#include <cstdint>

namespace aegis {

struct FitnessWeights {
    double alpha = 0.05;  // normalized BIC regularization weight
    double beta  = 0.1;   // denominator-term penalty
    double gamma = 0.01;  // complexity penalty (number of factors)
    double delta = 0.01;  // exponent-range penalty
    double eta   = 1.0;   // stability penalty (singularity + free-run divergence)
    double zeta  = 0.5;   // input-contribution deficit penalty
    double theta = 0.0;   // free-run (simulation) RMSE penalty weight
    int    free_run_horizon = 50; // samples used for the in-loop free-run RMSE (0 = whole split)
    // 0 = one-step objective (original composite): base term = one-step RMSE_val,
    //     BIC on training one-step residuals, theta·RMSE_free-run as an extra term.
    // 1 = simulation objective: base term = free-run RMSE over the WHOLE
    //     validation split; BIC computed on those simulation residuals; the
    //     theta term is not added (it would double-count the same error).
    int    error_mode = 0;
    // First row (in each split) where errors are scored; set to the configured
    // maxDelay so that every candidate is scored on the same samples.
    int    score_start = 0;
    double input_contribution_target = 0.3;
};

struct EvalResult {
    bool          valid         = false;
    double        fitness       = std::numeric_limits<double>::infinity();
    ModelMetrics  metrics;
    std::vector<double> err_values;
    bool          has_nan_inf   = false;
};

/** Full diagnostics of one (champion) model; not computed in the inner loop. */
struct ModelDiagnostics {
    bool   valid = false;
    // One-step residuals on the validation split (or training if absent)
    std::vector<double> residual_acf;      // lags 0..max_lag
    double residual_acf_max_abs = std::numeric_limits<double>::quiet_NaN(); // over lags ≥ 1
    double residual_acf_bound   = std::numeric_limits<double>::quiet_NaN(); // 1.96/sqrt(N)
    bool   residual_white       = false;
    double residual_input_ccf_max = std::numeric_limits<double>::quiet_NaN(); // max |ccf| over inputs/lags
    bool   residual_independent = false;
    std::string residual_split;            // "validation" | "training"
    // Full-length free-run simulation on the validation split
    double free_run_rmse_val_full = std::numeric_limits<double>::quiet_NaN();
    double free_run_r2_val_full   = std::numeric_limits<double>::quiet_NaN();
    bool   free_run_val_diverged  = false;
    // Structure / conditioning
    double linear_spectral_radius = std::numeric_limits<double>::quiet_NaN();
    // Over/under-fitting heuristics (one-step RMSE)
    double overfit_gap_ratio = std::numeric_limits<double>::quiet_NaN(); // (val−train)/train
    bool   overfitting  = false;
    bool   underfitting = false;
};

/**
 * Evaluates one Chromosome on training + optional validation data.
 *
 * Steps (Ψ is built once per split and reused):
 *   1. Ψ_train, pseudo-linearised least squares with intercept (QR)
 *   2. one-step predictions on train (and validation)
 *   3. SSE, AIC, BIC, FPE, MDL; RMSE/R² on both splits
 *   4. ERR in forward-greedy (FROLS) order on centred data
 *   5. horizon-limited free-run RMSE on validation with divergence detection
 *   6. stability diagnostics (denominator singularity + divergence)
 *   7. composite fitness
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
        int           output_col,
        bool          refit = true         // false: keep existing coefficients (if present)
    ) const;

    /** Recompute only the composite fitness after objective weights change. */
    bool rescore(Chromosome& chrom, int output_col) const;

    /** ERR (forward-greedy order, centred) for a Ψ already pseudo-linearised. */
    static std::vector<double> compute_err_from_psi(
        const std::vector<double>& psi_lin, int usable, int nr, const double* y);

    /** ERR with columns entering group by group (ascending group id),
     *  forward-greedy within each group. */
    static std::vector<double> compute_err_grouped(
        const std::vector<double>& psi_lin, int usable, int nr, const double* y,
        const std::vector<int>& group);

    /**
     * Input contribution: share of the variance NOT explained by the purely
     * autoregressive regressors that is explained by the input-dependent
     * regressors (AR terms enter first). 0 for purely autoregressive models;
     * equals the ERR sum of the inputs for models without AR terms.
     */
    static double input_contribution_from_psi(
        const Chromosome& chrom, const std::vector<double>& psi_lin, int usable,
        const double* y, int output_col);

    /** Evaluate ERR for an already-structured chromosome on data. */
    std::vector<double> compute_err(
        const Chromosome& chrom,
        const double* data, int rows, int cols, int output_col
    ) const;

    /** Full diagnostics for a fitted chromosome (champion reporting). */
    ModelDiagnostics diagnose(
        const Chromosome& chrom,
        const double* train_data, int train_rows,
        const double* val_data,   int val_rows,
        int cols, int output_col, int max_lag = 20
    ) const;

    FitnessWeights& weights() noexcept { return weights_; }
    const FitnessWeights& weights() const noexcept { return weights_; }

    /** Number of objective-function evaluations performed by this evaluator. */
    /** P1: the full ERR (chrom.err) does not enter the fitness; inner-loop
     *  evaluators may skip it. Default on, so every reporting path keeps it. */
    void set_compute_full_err(bool on) noexcept { full_err_ = on; }
    bool compute_full_err() const noexcept { return full_err_; }

    /** P2'a: 0 = Householder QR (default, exact), 1 = centred Gram matrix with
     *  Cholesky and K×K grouped ERR, falling back to QR when ill-conditioned.
     *  Used only by the island (inner-loop) evaluators. */
    void set_fit_method(int m) noexcept { fit_method_ = m; }
    int fit_method() const noexcept { return fit_method_; }

    long long evaluations() const noexcept { return evaluations_; }
    void reset_evaluations() noexcept { evaluations_ = 0; }

    /** Free-run divergence envelope = factor × max |y_train|. */
    static constexpr double kDivergenceFactor = 10.0;

private:
    FitnessWeights  weights_;
    mutable long long evaluations_ = 0;
    bool            full_err_ = true;
    int             fit_method_ = 0;

    double compute_complexity_penalty(const Chromosome& chrom) const noexcept;
    double compute_exponent_penalty(const Chromosome& chrom) const noexcept;
    double compute_no_input_penalty(const Chromosome& chrom, int output_col) const noexcept;
    double compute_input_contribution_ratio(const Chromosome& chrom, int output_col) const noexcept;
    double compute_residual_input_corr(
        const std::vector<double>& residuals,
        const double* data, int rows, int cols, int output_col, int max_delay
    ) const noexcept;
    void assemble_fitness(Chromosome& chrom, int output_col) const;
    bool fast_fit_and_ratio(Chromosome& chrom, const std::vector<double>& psi, int n, const double* y,
                            int output_col, double& input_ratio, int& reason) const;
    void p2a_audit(const Chromosome& chrom, const std::vector<double>& psi, int n, const double* y,
                   int output_col, bool fast, int reason, double ratio_fast) const;
};

} // namespace aegis
