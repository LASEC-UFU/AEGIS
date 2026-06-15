#pragma once
#include <vector>
#include <cmath>
#include <limits>

namespace aegis {

struct ModelMetrics {
    double rmse_train    = std::numeric_limits<double>::quiet_NaN();
    double rmse_val      = std::numeric_limits<double>::quiet_NaN();
    double rmse_test     = std::numeric_limits<double>::quiet_NaN();
    double rmse_original = std::numeric_limits<double>::quiet_NaN();
    double r2_train      = std::numeric_limits<double>::quiet_NaN();
    double r2_val        = std::numeric_limits<double>::quiet_NaN();
    double r2_test       = std::numeric_limits<double>::quiet_NaN();
    double sse           = std::numeric_limits<double>::quiet_NaN();
    double aic           = std::numeric_limits<double>::quiet_NaN();
    double bic           = std::numeric_limits<double>::quiet_NaN();
    double fpe           = std::numeric_limits<double>::quiet_NaN();
    double mdl           = std::numeric_limits<double>::quiet_NaN();
    int    n_train       = 0;
    int    n_params      = 0;

    // ── AEGIS Curriculum indicators ──────────────────────────────────────
    double rmse_free_run            = std::numeric_limits<double>::quiet_NaN();
    double input_contribution_ratio = std::numeric_limits<double>::quiet_NaN();
    double residual_input_corr      = std::numeric_limits<double>::quiet_NaN();
};

/** Decomposed fitness terms (before/after weighting), for diagnostics shown
 *  to the hierarchical agent and the UI ("fitness_breakdown"). */
struct FitnessBreakdown {
    double rmse            = 0.0; // base RMSE term (validation or train)
    double bic_term        = 0.0; // alpha * max(0, bic)
    double denom_term      = 0.0; // beta  * denom_penalty
    double complexity_term = 0.0; // gamma * complexity
    double exponent_term   = 0.0; // delta * exp_penalty
    double stability_term  = 0.0; // eta   * stability_penalty
    double no_input_term   = 0.0; // zeta  * no_input_penalty
    double free_run_term   = 0.0; // theta * free_run_rmse
};

class Metrics {
public:
    /** SSE = sum (y - y_hat)^2 */
    static double sse(const double* y, const double* y_hat, int n) noexcept;

    /** RMSE = sqrt(SSE/n) */
    static double rmse(const double* y, const double* y_hat, int n) noexcept;

    /** R2 = 1 - SSE/SST */
    static double r2(const double* y, const double* y_hat, int n) noexcept;

    /** AIC = n*ln(SSE/n) + 2k */
    static double aic(double sse_val, int n, int k) noexcept;

    /** BIC = n*ln(SSE/n) + k*ln(n) */
    static double bic(double sse_val, int n, int k) noexcept;

    /** FPE (Final Prediction Error) = SSE/n * (n+k)/(n-k) */
    static double fpe(double sse_val, int n, int k) noexcept;

    /**
     * MDL (Minimum Description Length):
     *   MDL = (n/2)*ln(SSE/n) + (k/2)*ln(n)
     */
    static double mdl(double sse_val, int n, int k) noexcept;

    /**
     * Compute full metric set for a fitted model given predictions on each split.
     *
     * y_train / y_hat_train : training targets and predictions
     * y_val   / y_hat_val   : validation targets and predictions
     * y_test  / y_hat_test  : test targets and predictions (may be null)
     * k                     : number of model parameters
     */
    static ModelMetrics compute(
        const double* y_train,     const double* y_hat_train,     int n_train,
        const double* y_val,       const double* y_hat_val,       int n_val,
        const double* y_test,      const double* y_hat_test,      int n_test,
        int k
    );

    /**
     * Composite fitness used by DE:
     *   fitness = RMSE_val + alpha*BIC + beta*denom_penalty + gamma*complexity
     *           + delta*exp_penalty + eta*stability_penalty + zeta*no_input_penalty
     *           + theta*free_run_rmse
     */
    static double composite_fitness(
        double rmse_val,
        double bic_val,
        double denom_penalty,
        double complexity,
        double exp_penalty,
        double stability_penalty,
        double no_input_penalty,
        double free_run_rmse,
        double alpha, double beta, double gamma, double delta, double eta, double zeta, double theta
    ) noexcept;
};

} // namespace aegis
