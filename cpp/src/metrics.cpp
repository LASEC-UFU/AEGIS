#include "aegis/metrics.hpp"
#include <cmath>
#include <algorithm>
#include <numeric>

namespace aegis {

double Metrics::sse(const double* y, const double* y_hat, int n) noexcept {
    double s = 0.0;
    for (int i = 0; i < n; ++i) {
        double e = y[i] - y_hat[i];
        s += e * e;
    }
    return s;
}

double Metrics::rmse(const double* y, const double* y_hat, int n) noexcept {
    if (n <= 0) return std::numeric_limits<double>::infinity();
    return std::sqrt(sse(y, y_hat, n) / n);
}

double Metrics::r2(const double* y, const double* y_hat, int n) noexcept {
    if (n <= 1) return 0.0;
    double mean = 0.0;
    for (int i = 0; i < n; ++i) mean += y[i];
    mean /= n;
    double sst = 0.0, sse_v = 0.0;
    for (int i = 0; i < n; ++i) {
        double dm = y[i] - mean;
        double de = y[i] - y_hat[i];
        sst  += dm * dm;
        sse_v += de * de;
    }
    if (sst < 1e-30) return 1.0;
    return 1.0 - sse_v / sst;
}

double Metrics::aic(double sse_val, int n, int k) noexcept {
    if (n <= 0 || sse_val <= 0) return std::numeric_limits<double>::infinity();
    return n * std::log(sse_val / n) + 2.0 * k;
}

double Metrics::bic(double sse_val, int n, int k) noexcept {
    if (n <= 0 || sse_val <= 0) return std::numeric_limits<double>::infinity();
    return n * std::log(sse_val / n) + k * std::log(static_cast<double>(n));
}

double Metrics::fpe(double sse_val, int n, int k) noexcept {
    if (n <= k || n <= 0) return std::numeric_limits<double>::infinity();
    return (sse_val / n) * static_cast<double>(n + k) / static_cast<double>(n - k);
}

double Metrics::mdl(double sse_val, int n, int k) noexcept {
    if (n <= 0 || sse_val <= 0) return std::numeric_limits<double>::infinity();
    return 0.5 * n * std::log(sse_val / n) + 0.5 * k * std::log(static_cast<double>(n));
}

ModelMetrics Metrics::compute(
    const double* y_train,     const double* y_hat_train,     int n_train,
    const double* y_val,       const double* y_hat_val,       int n_val,
    const double* y_test,      const double* y_hat_test,      int n_test,
    int k
) {
    ModelMetrics m;
    m.n_train  = n_train;
    m.n_params = k;

    if (n_train > 0 && y_train && y_hat_train) {
        double s = sse(y_train, y_hat_train, n_train);
        m.sse        = s;
        m.rmse_train = std::sqrt(s / n_train);
        m.r2_train   = r2(y_train, y_hat_train, n_train);
        m.aic        = aic(s, n_train, k);
        m.bic        = bic(s, n_train, k);
        m.fpe        = fpe(s, n_train, k);
        m.mdl        = mdl(s, n_train, k);
    }
    if (n_val > 0 && y_val && y_hat_val) {
        m.rmse_val = rmse(y_val, y_hat_val, n_val);
        m.r2_val   = r2(y_val, y_hat_val, n_val);
    }
    if (n_test > 0 && y_test && y_hat_test) {
        m.rmse_test = rmse(y_test, y_hat_test, n_test);
    }
    return m;
}

double Metrics::composite_fitness(
    double rmse_val,
    double bic_val,
    double denom_penalty,
    double complexity,
    double exp_penalty,
    double stability_penalty,
    double alpha, double beta, double gamma, double delta, double eta
) noexcept {
    double f = rmse_val
        + alpha  * std::max(0.0, bic_val)
        + beta   * denom_penalty
        + gamma  * complexity
        + delta  * exp_penalty
        + eta    * stability_penalty;
    return std::isfinite(f) ? f : std::numeric_limits<double>::max();
}

} // namespace aegis
