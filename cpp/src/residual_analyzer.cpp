#include "aegis/residual_analyzer.hpp"
#include <cmath>
#include <numeric>
#include <algorithm>

namespace aegis {

std::vector<double> ResidualAnalyzer::autocorrelation(
    const double* x, int n, int max_lag
) {
    if (n <= 0) return {};
    double mean = 0.0;
    for (int i = 0; i < n; ++i) mean += x[i];
    mean /= n;

    double r0 = 0.0;
    for (int i = 0; i < n; ++i) { double d = x[i] - mean; r0 += d * d; }

    std::vector<double> acf(max_lag + 1, 0.0);
    acf[0] = 1.0;
    if (r0 < 1e-30) return acf;

    for (int lag = 1; lag <= max_lag && lag < n; ++lag) {
        double s = 0.0;
        for (int i = lag; i < n; ++i)
            s += (x[i] - mean) * (x[i - lag] - mean);
        acf[lag] = s / r0;
    }
    return acf;
}

std::vector<double> ResidualAnalyzer::cross_correlation(
    const double* e, const double* u, int n, int max_lag
) {
    if (n <= 0) return {};
    double me = 0.0, mu_v = 0.0;
    for (int i = 0; i < n; ++i) { me += e[i]; mu_v += u[i]; }
    me /= n; mu_v /= n;

    double re = 0.0, ru = 0.0;
    for (int i = 0; i < n; ++i) {
        re += (e[i] - me) * (e[i] - me);
        ru += (u[i] - mu_v) * (u[i] - mu_v);
    }
    double norm = std::sqrt(re * ru);
    if (norm < 1e-30) return std::vector<double>(2 * max_lag + 1, 0.0);

    std::vector<double> ccf(2 * max_lag + 1, 0.0);
    for (int lag = -max_lag; lag <= max_lag; ++lag) {
        double s = 0.0;
        int start = std::max(0, -lag);
        int end   = std::min(n, n - lag);
        for (int i = start; i < end; ++i)
            s += (e[i] - me) * (u[i + lag] - mu_v);
        ccf[lag + max_lag] = s / norm;
    }
    return ccf;
}

ResidualStats ResidualAnalyzer::analyze(
    const double* residuals, int n,
    const double* inputs, int n_inputs
) const {
    ResidualStats s;
    if (n <= 0) return s;

    double sum = 0.0;
    for (int i = 0; i < n; ++i) sum += residuals[i];
    s.mean = sum / n;

    double var = 0.0;
    for (int i = 0; i < n; ++i) {
        double d = residuals[i] - s.mean;
        var += d * d;
    }
    s.variance = var / n;
    s.std_dev  = std::sqrt(s.variance);

    s.autocorr = autocorrelation(residuals, n, max_lag_);

    // Whiteness check: |ρ(τ)| < 2/sqrt(n) for τ > 0 (95% CI)
    double ci = 2.0 / std::sqrt(static_cast<double>(n));
    s.whiteness_ok = true;
    for (int lag = 1; lag < (int)s.autocorr.size(); ++lag) {
        if (std::abs(s.autocorr[lag]) > ci) { s.whiteness_ok = false; break; }
    }

    if (inputs && n_inputs > 0) {
        s.cross_corr.resize(n_inputs);
        s.independence_ok = true;
        for (int j = 0; j < n_inputs; ++j) {
            std::vector<double> u_col(n);
            for (int i = 0; i < n; ++i) u_col[i] = inputs[i * n_inputs + j];
            auto cc = cross_correlation(residuals, u_col.data(), n, max_lag_);
            // Store max abs cross-corr for this input
            double max_cc = 0.0;
            for (double v : cc) max_cc = std::max(max_cc, std::abs(v));
            s.cross_corr[j] = max_cc;
            if (max_cc > ci) s.independence_ok = false;
        }
    }
    return s;
}

} // namespace aegis
