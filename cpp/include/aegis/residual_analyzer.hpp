#pragma once
#include <vector>

namespace aegis {

struct ResidualStats {
    double mean      = 0.0;
    double variance  = 0.0;
    double std_dev   = 0.0;
    std::vector<double> autocorr;  // lags 0..max_lag
    std::vector<double> cross_corr; // residual vs. each input
    bool whiteness_ok = false;     // true if autocorr within 95% CI
    bool independence_ok = false;  // true if cross_corr within 95% CI
};

class ResidualAnalyzer {
public:
    explicit ResidualAnalyzer(int max_lag = 20) : max_lag_(max_lag) {}

    /**
     * Compute full residual statistics.
     *   residuals : e(k) = y(k) - y_hat(k), length n
     *   inputs    : input variables matrix, row-major n × n_inputs (may be null)
     */
    ResidualStats analyze(
        const double* residuals, int n,
        const double* inputs = nullptr, int n_inputs = 0
    ) const;

    /** Normalized autocorrelation at lag τ: ρ(τ) = R(τ)/R(0) */
    static std::vector<double> autocorrelation(
        const double* x, int n, int max_lag
    );

    /** Cross-correlation between residuals and one input signal. */
    static std::vector<double> cross_correlation(
        const double* e, const double* u, int n, int max_lag
    );

private:
    int max_lag_;
};

} // namespace aegis
