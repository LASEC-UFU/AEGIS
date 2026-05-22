#include "aegis/individual_evaluator.hpp"
#include "aegis/rational_model.hpp"
#include "aegis/safe_power.hpp"
#include <cmath>
#include <algorithm>
#include <numeric>

namespace aegis {

// ── Penalty helpers ───────────────────────────────────────────────────────

double IndividualEvaluator::compute_denom_penalty(const Chromosome& chrom) const noexcept {
    int denom_count = 0;
    for (const auto& r : chrom.regressors)
        if (r.is_denominator()) ++denom_count;
    return static_cast<double>(denom_count);
}

double IndividualEvaluator::compute_complexity_penalty(const Chromosome& chrom) const noexcept {
    double c = 0.0;
    for (const auto& r : chrom.regressors) c += static_cast<double>(r.terms.size());
    return c;
}

double IndividualEvaluator::compute_exponent_penalty(
    const Chromosome& chrom, double pmin, double pmax
) const noexcept {
    double p = 0.0;
    for (const auto& r : chrom.regressors)
        for (const auto& t : r.terms)
            p += std::abs(t.exponent - 1.0); // penalise non-unity exponents
    (void)pmin; (void)pmax;
    return p;
}

// ── ERR computation ───────────────────────────────────────────────────────

std::vector<double> IndividualEvaluator::compute_err(
    const Chromosome& chrom,
    const double* data, int rows, int cols, int output_col
) const {
    std::vector<double> psi;
    int usable;
    if (!build_psi_matrix(chrom, data, rows, cols, psi, usable))
        return {};

    const int nr = chrom.num_regressors();
    const int md = chrom.max_delay();

    std::vector<double> y(usable);
    for (int i = 0; i < usable; ++i)
        y[i] = data[(i + md) * cols + output_col];

    // Apply pseudo-linearization
    std::vector<double> psi_lin = psi;
    if (chrom.is_rational())
        pseudo_linearize(chrom, y.data(), psi_lin.data(), usable, nr);

    // Total output energy
    double y_energy = 0.0;
    for (double v : y) y_energy += v * v;
    if (y_energy < 1e-30) return std::vector<double>(nr, 0.0);

    // Modified Gram-Schmidt ERR
    std::vector<double> W = psi_lin; // working copy
    std::vector<double> err(nr, 0.0);

    for (int j = 0; j < nr; ++j) {
        // Orthogonalise column j against all previous columns
        for (int k = 0; k < j; ++k) {
            double dot_kj = 0.0, dot_kk = 0.0;
            for (int i = 0; i < usable; ++i) {
                dot_kj += W[i * nr + k] * psi_lin[i * nr + j];
                dot_kk += W[i * nr + k] * W[i * nr + k];
            }
            if (dot_kk < 1e-30) continue;
            double alpha = dot_kj / dot_kk;
            for (int i = 0; i < usable; ++i)
                W[i * nr + j] -= alpha * W[i * nr + k];
        }

        // ERR_j = <w_j, y>² / (<w_j, w_j> * ||y||²)
        double wjy = 0.0, wjwj = 0.0;
        for (int i = 0; i < usable; ++i) {
            wjy  += W[i * nr + j] * y[i];
            wjwj += W[i * nr + j] * W[i * nr + j];
        }
        if (wjwj < 1e-30) continue;
        err[j] = (wjy * wjy) / (wjwj * y_energy);
    }
    return err;
}

// ── evaluate ──────────────────────────────────────────────────────────────

EvalResult IndividualEvaluator::evaluate(
    Chromosome&   chrom,
    const double* train_data, int train_rows,
    const double* val_data,   int val_rows,
    int cols, int output_col
) const {
    EvalResult result;
    result.valid = false;

    if (chrom.num_regressors() == 0) return result;

    // ── Fit on training data ───────────────────────────────────────────
    RationalModel model(chrom);
    if (!model.fit(train_data, train_rows, cols, output_col)) return result;

    chrom.coefficients = model.chromosome().coefficients;

    // Check for NaN/Inf in coefficients
    for (double c : chrom.coefficients) {
        if (!is_valid(c)) { result.has_nan_inf = true; return result; }
    }

    // ── Training predictions ───────────────────────────────────────────
    const int md = chrom.max_delay();
    const int n_train_usable = train_rows - md;
    if (n_train_usable <= 0) return result;

    std::vector<double> yhat_train = model.predict_one_step(
        train_data, train_rows, cols, output_col
    );

    std::vector<double> y_train(n_train_usable);
    for (int i = 0; i < n_train_usable; ++i)
        y_train[i] = train_data[(i + md) * cols + output_col];

    double sse_train = Metrics::sse(y_train.data(), yhat_train.data(), n_train_usable);
    if (!std::isfinite(sse_train)) { result.has_nan_inf = true; return result; }
    chrom.sse = sse_train;

    const int k = chrom.num_regressors();
    double bic_v = Metrics::bic(sse_train, n_train_usable, k);
    double aic_v = Metrics::aic(sse_train, n_train_usable, k);

    // ── Validation predictions ─────────────────────────────────────────
    double rmse_val = std::numeric_limits<double>::infinity();
    std::vector<double> y_val_vec, yhat_val;
    if (val_data && val_rows > md) {
        const int n_val_usable = val_rows - md;
        yhat_val = model.predict_one_step(val_data, val_rows, cols, output_col);
        y_val_vec.resize(n_val_usable);
        for (int i = 0; i < n_val_usable; ++i)
            y_val_vec[i] = val_data[(i + md) * cols + output_col];
        rmse_val = Metrics::rmse(y_val_vec.data(), yhat_val.data(), n_val_usable);
    }

    // ── Metrics ──────────────────────────────────────────────────────
    result.metrics = Metrics::compute(
        y_train.data(), yhat_train.data(), n_train_usable,
        y_val_vec.empty() ? nullptr : y_val_vec.data(),
        yhat_val.empty()  ? nullptr : yhat_val.data(),
        static_cast<int>(y_val_vec.size()),
        nullptr, nullptr, 0,
        k
    );

    // ── Stability ─────────────────────────────────────────────────────
    result.stability = stability_analyzer_.analyze(chrom);
    double stab_pen  = result.stability.penalty;

    // ── Penalties ─────────────────────────────────────────────────────
    double denom_pen = compute_denom_penalty(chrom);
    double complex_p = compute_complexity_penalty(chrom);
    double exp_pen   = compute_exponent_penalty(chrom, 0.5, 5.0);

    // ── Composite fitness ─────────────────────────────────────────────
    double fit_rmse = std::isfinite(rmse_val) ? rmse_val
                    : Metrics::rmse(y_train.data(), yhat_train.data(), n_train_usable);
    double fitness = Metrics::composite_fitness(
        fit_rmse,
        std::isfinite(bic_v) ? bic_v : 1e6,
        denom_pen, complex_p, exp_pen, stab_pen,
        weights_.alpha, weights_.beta, weights_.gamma,
        weights_.delta, weights_.eta
    );

    chrom.fitness   = fitness;
    chrom.evaluated = true;

    // ── ERR ───────────────────────────────────────────────────────────
    result.err_values = compute_err(chrom, train_data, train_rows, cols, output_col);
    chrom.err         = result.err_values;

    // ── Residual stats ────────────────────────────────────────────────
    std::vector<double> residuals(n_train_usable);
    for (int i = 0; i < n_train_usable; ++i)
        residuals[i] = y_train[i] - yhat_train[i];
    ResidualAnalyzer ra;
    result.residuals = ra.analyze(residuals.data(), n_train_usable);

    result.valid   = true;
    result.fitness = fitness;
    return result;
}

} // namespace aegis
