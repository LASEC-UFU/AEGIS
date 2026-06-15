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

double IndividualEvaluator::compute_no_input_penalty(
    const Chromosome& chrom, int output_col
) const noexcept {
    for (const auto& r : chrom.regressors)
        for (const auto& t : r.terms)
            if (t.variable != output_col) return 0.0;
    return 1.0;
}

double IndividualEvaluator::compute_input_contribution_ratio(
    const Chromosome& chrom, int output_col
) const noexcept {
    if (chrom.err.empty() || chrom.err.size() != chrom.regressors.size())
        return std::numeric_limits<double>::quiet_NaN();

    double total = 0.0, input_sum = 0.0;
    for (size_t j = 0; j < chrom.regressors.size(); ++j) {
        double e = chrom.err[j];
        total += e;
        bool depends_on_input = false;
        for (const auto& t : chrom.regressors[j].terms)
            if (t.variable != output_col) { depends_on_input = true; break; }
        if (depends_on_input) input_sum += e;
    }
    if (total < 1e-30) return 0.0;
    return clamp(input_sum / total, 0.0, 1.0);
}

double IndividualEvaluator::compute_residual_input_corr(
    const std::vector<double>& residuals,
    const double* data, int rows, int cols, int output_col, int max_delay
) const noexcept {
    (void)rows;
    if (residuals.empty()) return std::numeric_limits<double>::quiet_NaN();
    const int n = static_cast<int>(residuals.size());

    double r_mean = 0.0;
    for (double v : residuals) r_mean += v;
    r_mean /= n;
    double r_var = 0.0;
    for (double v : residuals) r_var += (v - r_mean) * (v - r_mean);

    double max_abs_corr = 0.0;
    for (int var = 0; var < cols; ++var) {
        if (var == output_col) continue;

        double x_mean = 0.0;
        for (int i = 0; i < n; ++i) x_mean += data[(i + max_delay) * cols + var];
        x_mean /= n;

        double cov = 0.0, x_var = 0.0;
        for (int i = 0; i < n; ++i) {
            double dx = data[(i + max_delay) * cols + var] - x_mean;
            double dr = residuals[i] - r_mean;
            cov   += dx * dr;
            x_var += dx * dx;
        }
        if (x_var < 1e-30 || r_var < 1e-30) continue;
        double corr = cov / std::sqrt(x_var * r_var);
        max_abs_corr = std::max(max_abs_corr, std::abs(corr));
    }
    return max_abs_corr;
}

bool IndividualEvaluator::rescore(Chromosome& chrom, int output_col) const {
    if (!chrom.evaluated) return false;

    const double fit_rmse = std::isfinite(chrom.metrics.rmse_val)
        ? chrom.metrics.rmse_val
        : chrom.metrics.rmse_train;
    if (!std::isfinite(fit_rmse)) return false;

    const double bic_score =
        std::isfinite(chrom.metrics.bic) && chrom.metrics.n_train > 0
        ? chrom.metrics.bic / static_cast<double>(chrom.metrics.n_train)
        : 1e6;
    const double denom_pen     = compute_denom_penalty(chrom);
    const double complex_p     = compute_complexity_penalty(chrom);
    const double exp_pen       = compute_exponent_penalty(chrom, 0.5, 5.0);
    const double stab_pen      = stability_analyzer_.analyze(chrom).penalty;
    const double input_ratio = chrom.metrics.input_contribution_ratio;
    const double target = std::max(weights_.input_contribution_target, 1e-12);
    const double no_input_pen = std::isfinite(input_ratio)
        ? std::max(0.0, target - clamp(input_ratio, 0.0, 1.0)) / target
        : compute_no_input_penalty(chrom, output_col);
    const double free_run_rmse = chrom.metrics.rmse_free_run;

    chrom.fitness = Metrics::composite_fitness(
        fit_rmse,
        bic_score,
        denom_pen, complex_p, exp_pen, stab_pen, no_input_pen, free_run_rmse,
        weights_.alpha, weights_.beta, weights_.gamma,
        weights_.delta, weights_.eta, weights_.zeta, weights_.theta
    );
    chrom.fitness_breakdown.rmse            = fit_rmse;
    chrom.fitness_breakdown.bic_term        = weights_.alpha * bic_score;
    chrom.fitness_breakdown.denom_term      = weights_.beta  * denom_pen;
    chrom.fitness_breakdown.complexity_term = weights_.gamma * complex_p;
    chrom.fitness_breakdown.exponent_term   = weights_.delta * exp_pen;
    chrom.fitness_breakdown.stability_term  = weights_.eta   * stab_pen;
    chrom.fitness_breakdown.no_input_term   = weights_.zeta  * no_input_pen;
    chrom.fitness_breakdown.free_run_term =
        std::isfinite(free_run_rmse) ? weights_.theta * free_run_rmse : 0.0;
    return std::isfinite(chrom.fitness);
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
    chrom.intercept    = model.chromosome().intercept;

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

    const int k = chrom.num_regressors() + 1; // regressors plus intercept
    double bic_v = Metrics::bic(sse_train, n_train_usable, k);

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
    chrom.metrics = result.metrics;

    // Grade input usage by explanatory contribution, not merely by the
    // presence of an input term whose fitted coefficient may be negligible.
    result.err_values = compute_err(chrom, train_data, train_rows, cols, output_col);
    chrom.err         = result.err_values;
    result.metrics.input_contribution_ratio =
        compute_input_contribution_ratio(chrom, output_col);
    chrom.metrics = result.metrics;

    // ── Stability ─────────────────────────────────────────────────────
    result.stability = stability_analyzer_.analyze(chrom);
    double stab_pen  = result.stability.penalty;

    // ── Penalties ─────────────────────────────────────────────────────
    double denom_pen   = compute_denom_penalty(chrom);
    double complex_p   = compute_complexity_penalty(chrom);
    double exp_pen     = compute_exponent_penalty(chrom, 0.5, 5.0);
    const double input_target =
        std::max(weights_.input_contribution_target, 1e-12);
    double no_input_pen = std::isfinite(result.metrics.input_contribution_ratio)
        ? std::max(0.0, input_target - clamp(
              result.metrics.input_contribution_ratio, 0.0, 1.0
          )) / input_target
        : compute_no_input_penalty(chrom, output_col);

    // ── Free-run (simulation) RMSE ──────────────────────────────────────
    // Simulated on the validation split when available (else training),
    // limited to free_run_horizon samples to bound cost and focus on
    // near-term divergence.
    double free_run_rmse = std::numeric_limits<double>::quiet_NaN();
    {
        const double* sim_data = val_data && val_rows > md ? val_data : train_data;
        int           sim_rows = val_data && val_rows > md ? val_rows  : train_rows;
        std::vector<double> yhat_free = model.predict_free_run(
            sim_data, sim_rows, cols, output_col, weights_.free_run_horizon
        );
        int n_sim = std::min(static_cast<int>(yhat_free.size()), weights_.free_run_horizon);
        if (n_sim > 0) {
            std::vector<double> y_sim(n_sim);
            for (int i = 0; i < n_sim; ++i)
                y_sim[i] = sim_data[(i + md) * cols + output_col];
            free_run_rmse = Metrics::rmse(y_sim.data(), yhat_free.data(), n_sim);
        }
    }

    // ── Composite fitness ─────────────────────────────────────────────
    double fit_rmse = std::isfinite(rmse_val) ? rmse_val
                    : Metrics::rmse(y_train.data(), yhat_train.data(), n_train_usable);
    double bic_score = std::isfinite(bic_v)
        ? bic_v / static_cast<double>(n_train_usable)
        : 1e6;
    double fitness = Metrics::composite_fitness(
        fit_rmse,
        bic_score,
        denom_pen, complex_p, exp_pen, stab_pen, no_input_pen, free_run_rmse,
        weights_.alpha, weights_.beta, weights_.gamma,
        weights_.delta, weights_.eta, weights_.zeta, weights_.theta
    );

    chrom.fitness   = fitness;
    chrom.evaluated = true;

    // ── Fitness breakdown (diagnostics for the hierarchical agent) ─────
    chrom.fitness_breakdown.rmse            = fit_rmse;
    chrom.fitness_breakdown.bic_term        = weights_.alpha * bic_score;
    chrom.fitness_breakdown.denom_term      = weights_.beta  * denom_pen;
    chrom.fitness_breakdown.complexity_term = weights_.gamma * complex_p;
    chrom.fitness_breakdown.exponent_term   = weights_.delta * exp_pen;
    chrom.fitness_breakdown.stability_term  = weights_.eta   * stab_pen;
    chrom.fitness_breakdown.no_input_term   = weights_.zeta  * no_input_pen;
    chrom.fitness_breakdown.free_run_term   = std::isfinite(free_run_rmse) ? weights_.theta * free_run_rmse : 0.0;

    result.metrics.rmse_free_run = free_run_rmse;

    // ── ERR ───────────────────────────────────────────────────────────
    // ── Residual stats ────────────────────────────────────────────────
    std::vector<double> residuals(n_train_usable);
    for (int i = 0; i < n_train_usable; ++i)
        residuals[i] = y_train[i] - yhat_train[i];
    ResidualAnalyzer ra;
    result.residuals = ra.analyze(residuals.data(), n_train_usable);

    result.metrics.residual_input_corr = compute_residual_input_corr(
        residuals, train_data, train_rows, cols, output_col, md
    );

    chrom.metrics = result.metrics;

    result.valid   = true;
    result.fitness = fitness;
    return result;
}

} // namespace aegis
