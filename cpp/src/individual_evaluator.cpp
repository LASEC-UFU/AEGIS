#include "aegis/individual_evaluator.hpp"
#include "aegis/rational_model.hpp"
#include "aegis/safe_power.hpp"
#include "aegis/overfitting_detector.hpp"
#include "aegis/underfitting_detector.hpp"
#include "perf_probe.hpp"
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <thread>
#include <cmath>
#include <algorithm>
#include <numeric>

namespace aegis {

// ── Penalty helpers ───────────────────────────────────────────────────────

static double count_denominator_regressors(const Chromosome& chrom) noexcept {
    int denom_count = 0;
    for (const auto& r : chrom.regressors)
        if (r.is_denominator()) ++denom_count;
    return static_cast<double>(denom_count);
}

double IndividualEvaluator::compute_complexity_penalty(const Chromosome& chrom) const noexcept {
    return static_cast<double>(chrom.num_terms());
}

double IndividualEvaluator::compute_exponent_penalty(const Chromosome& chrom) const noexcept {
    double p = 0.0;
    for (const auto& r : chrom.regressors)
        for (const auto& t : r.terms)
            p += std::abs(t.exponent - 1.0); // penalise non-unity exponents
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
        for (int i = 0; i < n; ++i) x_mean += data[static_cast<size_t>(i + max_delay) * cols + var];
        x_mean /= n;
        double cov = 0.0, x_var = 0.0;
        for (int i = 0; i < n; ++i) {
            double dx = data[static_cast<size_t>(i + max_delay) * cols + var] - x_mean;
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

// ── composite fitness ─────────────────────────────────────────────────────

void IndividualEvaluator::assemble_fitness(Chromosome& chrom, int output_col) const {
    const auto& m = chrom.metrics;
    const bool simulation = weights_.error_mode == 1 && std::isfinite(m.rmse_free_run) && m.n_free_run > 0;
    double fit_rmse, bic_score;
    if (simulation) {
        // Simulation objective: free-run error over the whole validation split,
        // BIC/n on the simulation residuals (k = regressors + intercept).
        const double n = static_cast<double>(m.n_free_run);
        fit_rmse = m.rmse_free_run;
        const double mse = std::max(m.rmse_free_run * m.rmse_free_run, 1e-300);
        bic_score = std::log(mse) + m.n_params * std::log(n) / n;
    } else {
        fit_rmse = std::isfinite(m.rmse_val) ? m.rmse_val : m.rmse_train;
        bic_score = (std::isfinite(m.bic) && m.n_train > 0)
            ? m.bic / static_cast<double>(m.n_train) : 1e6;
    }
    const double denom_pen = count_denominator_regressors(chrom);
    const double complex_p = compute_complexity_penalty(chrom);
    const double exp_pen   = compute_exponent_penalty(chrom);
    const double stab_pen  = chrom.stability.penalty;
    const double input_ratio = m.input_contribution_ratio;
    const double target = std::max(weights_.input_contribution_target, 1e-12);
    const double no_input_pen = std::isfinite(input_ratio)
        ? std::max(0.0, target - clamp(input_ratio, 0.0, 1.0)) / target
        : compute_no_input_penalty(chrom, output_col);
    const double free_run_rmse = simulation ? std::numeric_limits<double>::quiet_NaN() : m.rmse_free_run;

    chrom.fitness = Metrics::composite_fitness(
        fit_rmse, bic_score,
        denom_pen, complex_p, exp_pen, stab_pen, no_input_pen, free_run_rmse,
        weights_.alpha, weights_.beta, weights_.gamma,
        weights_.delta, weights_.eta, weights_.zeta, weights_.theta
    );
    auto& fb = chrom.fitness_breakdown;
    fb.rmse            = fit_rmse;
    fb.bic_term        = weights_.alpha * bic_score;
    fb.denom_term      = weights_.beta  * denom_pen;
    fb.complexity_term = weights_.gamma * complex_p;
    fb.exponent_term   = weights_.delta * exp_pen;
    fb.stability_term  = weights_.eta   * stab_pen;
    fb.no_input_term   = weights_.zeta  * no_input_pen;
    fb.free_run_term   = std::isfinite(free_run_rmse) ? weights_.theta * free_run_rmse : 0.0;
}

bool IndividualEvaluator::rescore(Chromosome& chrom, int output_col) const {
    if (!chrom.evaluated) return false;
    const auto& m = chrom.metrics;
    if (!std::isfinite(m.rmse_val) && !std::isfinite(m.rmse_train)) return false;
    assemble_fitness(chrom, output_col);
    return std::isfinite(chrom.fitness);
}

// ── ERR computation (forward-greedy, centred) ─────────────────────────────

std::vector<double> IndividualEvaluator::compute_err_from_psi(
    const std::vector<double>& psi_lin, int usable, int nr, const double* y
) {
    return compute_err_grouped(psi_lin, usable, nr, y, std::vector<int>(nr, 0));
}

double IndividualEvaluator::input_contribution_from_psi(
    const Chromosome& chrom, const std::vector<double>& psi_lin, int usable, const double* y,
    int output_col
) {
    const int nr = chrom.num_regressors();
    std::vector<int> group(nr, 0);
    bool any_input = false;
    for (int j = 0; j < nr; ++j) {
        for (const auto& t : chrom.regressors[j].terms)
            if (t.variable != output_col) { group[j] = 1; any_input = true; break; }
    }
    if (!any_input) return 0.0;
    const std::vector<double> e = compute_err_grouped(psi_lin, usable, nr, y, group);
    double ar = 0.0, in = 0.0;
    for (int j = 0; j < nr; ++j) (group[j] ? in : ar) += e[j];
    const double remaining = 1.0 - ar;
    if (remaining < 1e-12) return 0.0;
    return clamp(in / remaining, 0.0, 1.0);
}

std::vector<double> IndividualEvaluator::compute_err_grouped(
    const std::vector<double>& psi_lin, int usable, int nr, const double* y,
    const std::vector<int>& group
) {
    std::vector<double> err(nr, 0.0);
    if (usable <= 1 || nr <= 0) return err;

    // Centre y and the columns (equivalent to orthogonalising against the
    // intercept, which is always part of the model).
    double ym = 0.0;
    for (int i = 0; i < usable; ++i) ym += y[i];
    ym /= usable;
    std::vector<double> yc(usable);
    double sigma = 0.0;
    for (int i = 0; i < usable; ++i) { yc[i] = y[i] - ym; sigma += yc[i] * yc[i]; }
    if (sigma < 1e-30) return err;

    // Column-major working copy W (nr × usable).
    std::vector<double> W(static_cast<size_t>(nr) * usable);
    std::vector<double> norm0(nr, 0.0);
    for (int j = 0; j < nr; ++j) {
        double m = 0.0;
        for (int i = 0; i < usable; ++i) m += psi_lin[static_cast<size_t>(i) * nr + j];
        m /= usable;
        double* w = W.data() + static_cast<size_t>(j) * usable;
        double s = 0.0;
        for (int i = 0; i < usable; ++i) {
            w[i] = psi_lin[static_cast<size_t>(i) * nr + j] - m;
            s += w[i] * w[i];
        }
        norm0[j] = s;
    }

    std::vector<char> active(nr, 1);
    for (int step = 0; step < 2 * nr + 1; ++step) {
        // Columns enter group by group (ascending), greedily within a group.
        int cur_group = std::numeric_limits<int>::max();
        for (int j = 0; j < nr; ++j)
            if (active[j]) cur_group = std::min(cur_group, group[j]);
        int best = -1;
        double best_err = -1.0;
        for (int j = 0; j < nr; ++j) {
            if (!active[j] || group[j] != cur_group) continue;
            const double* w = W.data() + static_cast<size_t>(j) * usable;
            double ww = 0.0, wy = 0.0;
            for (int i = 0; i < usable; ++i) { ww += w[i] * w[i]; wy += w[i] * yc[i]; }
            if (ww <= 1e-12 * std::max(norm0[j], 1e-300)) { active[j] = 0; continue; } // dependent
            const double e = (wy * wy) / (ww * sigma);
            if (e > best_err) { best_err = e; best = j; }
        }
        if (best < 0) {
            bool any = false;
            for (int j = 0; j < nr; ++j) any = any || active[j];
            if (!any) break;
            continue; // the current group only had dependent columns
        }
        err[best] = std::max(0.0, best_err);
        active[best] = 0;
        // Orthogonalise the remaining active columns against the selected one.
        const double* q = W.data() + static_cast<size_t>(best) * usable;
        double qq = 0.0;
        for (int i = 0; i < usable; ++i) qq += q[i] * q[i];
        if (qq < 1e-300) continue;
        for (int j = 0; j < nr; ++j) {
            if (!active[j]) continue;
            double* w = W.data() + static_cast<size_t>(j) * usable;
            double dot = 0.0;
            for (int i = 0; i < usable; ++i) dot += q[i] * w[i];
            const double a = dot / qq;
            for (int i = 0; i < usable; ++i) w[i] -= a * q[i];
        }
    }
    return err;
}

std::vector<double> IndividualEvaluator::compute_err(
    const Chromosome& chrom,
    const double* data, int rows, int cols, int output_col
) const {
    std::vector<double> psi;
    int usable;
    if (!build_psi_matrix(chrom, data, rows, cols, psi, usable)) return {};
    const int nr = chrom.num_regressors();
    const int md = chrom.max_delay();
    std::vector<double> y(usable);
    for (int i = 0; i < usable; ++i) y[i] = data[static_cast<size_t>(i + md) * cols + output_col];
    if (chrom.is_rational()) pseudo_linearize(chrom, y.data(), psi.data(), usable, nr);
    return compute_err_from_psi(psi, usable, nr, y.data());
}

// ── P2'a: fit and grouped ERR from the centred Gram matrix ────────────────
//
// Same least-squares problem as fit_from_psi (pseudo-linearised columns,
// intercept) and the same greedy grouped ERR as compute_err_grouped, solved
// in the K×K space: one pass for the means, one pass for the centred Gram
// matrix (½·N·K² multiply-adds, contiguous), then Cholesky with columns
// dropped in order (as the QR drops dependent columns) and the greedy ERR by
// rank-one updates of the Gram matrix. Not bit-identical to the QR path.
// Fallback (returns false) when a pivot or an ERR residual falls in the zone
// the Gram matrix cannot resolve: reason 1 = fit pivot, 2 = ERR residual,
// 3 = non-finite result.
namespace {
constexpr double kDropRel     = 1e-12; // ≤ → column dependent (same threshold as compute_err_grouped)
constexpr double kAmbiguousRel = 1e-8; // (kDropRel, kAmbiguousRel) → Gram cannot decide → fallback
}

bool IndividualEvaluator::fast_fit_and_ratio(
    Chromosome& chrom, const std::vector<double>& psi, int n, const double* y, int output_col,
    double& input_ratio, int& reason
) const {
    const int nr = chrom.num_regressors();
    reason = 0;
    std::vector<char> is_den(nr, 0);
    for (int j = 0; j < nr; ++j) is_den[j] = chrom.regressors[j].is_denominator() ? 1 : 0;

    // Pass 1: means of the pseudo-linearised columns and of y.
    std::vector<double> m(nr, 0.0);
    double ym = 0.0;
    for (int i = 0; i < n; ++i) {
        const double* row = psi.data() + static_cast<size_t>(i) * nr;
        const double yi = y[i];
        ym += yi;
        for (int j = 0; j < nr; ++j) m[j] += is_den[j] ? -yi * row[j] : row[j];
    }
    for (int j = 0; j < nr; ++j) m[j] /= n;
    ym /= n;

    // Pass 2: centred Gram (upper triangle), cross terms with y, Σ yc².
    std::vector<double> G(static_cast<size_t>(nr) * nr, 0.0), cy(nr, 0.0), r(nr);
    double syy = 0.0;
    for (int i = 0; i < n; ++i) {
        const double* row = psi.data() + static_cast<size_t>(i) * nr;
        const double yi = y[i];
        const double yc = yi - ym;
        syy += yc * yc;
        for (int j = 0; j < nr; ++j) r[j] = (is_den[j] ? -yi * row[j] : row[j]) - m[j];
        for (int j = 0; j < nr; ++j) {
            const double rj = r[j];
            cy[j] += rj * yc;
            double* Gj = G.data() + static_cast<size_t>(j) * nr;
            for (int k = j; k < nr; ++k) Gj[k] += rj * r[k];
        }
    }
    for (int j = 0; j < nr; ++j)
        for (int k = 0; k < j; ++k) G[static_cast<size_t>(j) * nr + k] = G[static_cast<size_t>(k) * nr + j];

    // Fit: Cholesky in column order; dependent columns get θ = 0.
    std::vector<double> L(static_cast<size_t>(nr) * nr, 0.0);
    std::vector<int> acc;
    acc.reserve(nr);
    for (int j = 0; j < nr; ++j) {
        const double gjj = G[static_cast<size_t>(j) * nr + j];
        double d = gjj;
        for (int k : acc) { const double l = L[static_cast<size_t>(j) * nr + k]; d -= l * l; }
        if (!(gjj > 0.0) || d <= kDropRel * gjj) continue;          // dependent: dropped
        if (d < kAmbiguousRel * gjj) { reason = 1; return false; }    // unresolvable
        const double ljj = std::sqrt(d);
        L[static_cast<size_t>(j) * nr + j] = ljj;
        for (int i = j + 1; i < nr; ++i) {
            double s = G[static_cast<size_t>(i) * nr + j];
            for (int k : acc) s -= L[static_cast<size_t>(i) * nr + k] * L[static_cast<size_t>(j) * nr + k];
            L[static_cast<size_t>(i) * nr + j] = s / ljj;
        }
        acc.push_back(j);
    }
    std::vector<double> z(nr, 0.0), theta(nr, 0.0);
    for (size_t a = 0; a < acc.size(); ++a) {
        const int j = acc[a];
        double s = cy[j];
        for (size_t b = 0; b < a; ++b) s -= L[static_cast<size_t>(j) * nr + acc[b]] * z[acc[b]];
        z[j] = s / L[static_cast<size_t>(j) * nr + j];
    }
    for (size_t a = acc.size(); a-- > 0;) {
        const int j = acc[a];
        double s = z[j];
        for (size_t b = a + 1; b < acc.size(); ++b) s -= L[static_cast<size_t>(acc[b]) * nr + j] * theta[acc[b]];
        theta[j] = s / L[static_cast<size_t>(j) * nr + j];
    }
    double c0 = ym;
    for (int j = 0; j < nr; ++j) c0 -= m[j] * theta[j];
    for (double v : theta) if (!std::isfinite(v)) { reason = 3; return false; }
    if (!std::isfinite(c0) || acc.empty()) { reason = 3; return false; }

    // Grouped ERR on the centred Gram matrix (same greedy rule as compute_err_grouped).
    double ratio = 0.0;
    std::vector<int> group(nr, 0);
    bool any_input = false;
    for (int j = 0; j < nr; ++j)
        for (const auto& t : chrom.regressors[j].terms)
            if (t.variable != output_col) { group[j] = 1; any_input = true; break; }
    if (any_input && n > 1 && syy >= 1e-30) {
        std::vector<double> C = G, c = cy, err(nr, 0.0), norm0(nr);
        for (int j = 0; j < nr; ++j) norm0[j] = G[static_cast<size_t>(j) * nr + j];
        std::vector<char> active(nr, 1);
        for (int step = 0; step < 2 * nr + 1; ++step) {
            int cur_group = std::numeric_limits<int>::max();
            for (int j = 0; j < nr; ++j) if (active[j]) cur_group = std::min(cur_group, group[j]);
            int best = -1;
            double best_err = -1.0;
            for (int j = 0; j < nr; ++j) {
                if (!active[j] || group[j] != cur_group) continue;
                const double ww = C[static_cast<size_t>(j) * nr + j], wy = c[j];
                const double ref = std::max(norm0[j], 1e-300);
                if (ww <= kDropRel * ref) { active[j] = 0; continue; }
                if (ww < kAmbiguousRel * ref) { reason = 2; return false; }
                const double e = (wy * wy) / (ww * syy);
                if (e > best_err) { best_err = e; best = j; }
            }
            if (best < 0) {
                bool any = false;
                for (int j = 0; j < nr; ++j) any = any || active[j];
                if (!any) break;
                continue;
            }
            err[best] = std::max(0.0, best_err);
            active[best] = 0;
            const double qq = C[static_cast<size_t>(best) * nr + best];
            if (qq < 1e-300) continue;
            const double cb = c[best];
            std::vector<double> col(nr);
            for (int j = 0; j < nr; ++j) col[j] = C[static_cast<size_t>(j) * nr + best];
            for (int j = 0; j < nr; ++j) {
                if (!active[j]) continue;
                const double a = col[j] / qq;
                c[j] -= a * cb;
                double* Cj = C.data() + static_cast<size_t>(j) * nr;
                for (int k = 0; k < nr; ++k) if (active[k]) Cj[k] -= a * col[k];
            }
        }
        double ar = 0.0, in = 0.0;
        for (int j = 0; j < nr; ++j) (group[j] ? in : ar) += err[j];
        const double remaining = 1.0 - ar;
        ratio = remaining < 1e-12 ? 0.0 : clamp(in / remaining, 0.0, 1.0);
    }
    if (!std::isfinite(ratio)) { reason = 3; return false; }

    chrom.coefficients = std::move(theta);
    chrom.intercept = c0;
    input_ratio = ratio;
    return true;
}

// P2'a audit (only when AEGIS_P2A_AUDIT is set): one line per inner-loop
// candidate with the fallback reason and, when the fast path was used, its
// agreement with the exact Householder path on the same candidate.
void IndividualEvaluator::p2a_audit(
    const Chromosome& chrom, const std::vector<double>& psi, int n, const double* y, int output_col,
    bool fast, int reason, double ratio_fast
) const {
    struct Sink {
        std::FILE* f = nullptr;
        Sink() {
            const char* base = std::getenv("AEGIS_P2A_AUDIT");
            if (!base || !*base) return;
            const size_t tid = std::hash<std::thread::id>{}(std::this_thread::get_id());
            f = std::fopen((std::string(base) + "." + std::to_string(tid % 1000000007u) + ".tsv").c_str(), "w");
        }
        ~Sink() { if (f) std::fclose(f); }
    };
    static thread_local Sink sink;
    if (!sink.f) return;
    const int nr = chrom.num_regressors();
    int nden = 0;
    for (const auto& rg : chrom.regressors) nden += rg.is_denominator() ? 1 : 0;
    if (!fast) {
        std::fprintf(sink.f, "%d\t%d\t0\t%d\n", nr + 1, nden, reason);
        return;
    }
    Chromosome q = chrom;
    std::vector<double> psi_q = psi;
    if (!RationalModel::fit_from_psi(q, psi_q, n, y)) {
        std::fprintf(sink.f, "%d\t%d\t1\t0\tqr_failed\n", nr + 1, nden);
        return;
    }
    double cmax = std::abs(q.intercept), dmax = std::abs(q.intercept - chrom.intercept);
    int zq = 0, zn = 0;
    for (int j = 0; j < nr; ++j) {
        cmax = std::max(cmax, std::abs(q.coefficients[j]));
        dmax = std::max(dmax, std::abs(q.coefficients[j] - chrom.coefficients[j]));
        zq += q.coefficients[j] == 0.0;
        zn += chrom.coefficients[j] == 0.0;
    }
    std::vector<double> yq, yn;
    RationalModel::predict_from_psi(q, psi, n, yq, nullptr);
    RationalModel::predict_from_psi(chrom, psi, n, yn, nullptr);
    const double sq = Metrics::sse(y, yq.data(), n), sn = Metrics::sse(y, yn.data(), n);
    if (chrom.is_rational()) pseudo_linearize(chrom, y, psi_q.data(), n, nr);
    const double rq = input_contribution_from_psi(chrom, psi_q, n, y, output_col);
    std::fprintf(sink.f, "%d\t%d\t1\t0\t%.3e\t%.3e\t%.3e\t%d\t%d\n", nr + 1, nden,
                 dmax / std::max(cmax, 1e-300), (sn - sq) / std::max(sq, 1e-300), ratio_fast - rq, zq, zn);
}

// ── evaluate ──────────────────────────────────────────────────────────────

EvalResult IndividualEvaluator::evaluate(
    Chromosome&   chrom,
    const double* train_data, int train_rows,
    const double* val_data,   int val_rows,
    int cols, int output_col, bool refit
) const {
    EvalResult result;
    AEGIS_PROBE_BEGIN(chrom, result.valid);
    ++evaluations_;
    const bool keep_coefficients = !refit &&
        chrom.coefficients.size() == chrom.regressors.size() && !chrom.coefficients.empty();
    chrom.evaluated = false;
    chrom.fitness = std::numeric_limits<double>::infinity();
    chrom.stability = StabilityDiagnostics();

    if (chrom.num_regressors() == 0) return result;
    const int md = chrom.max_delay();
    const int nr = chrom.num_regressors();
    const bool rational = chrom.is_rational();

    // ── Ψ on the training split (built once) ───────────────────────────
    std::vector<double> psi_train;
    int n_train_usable = 0;
    if (!build_psi_matrix(chrom, train_data, train_rows, cols, psi_train, n_train_usable))
        return result;
    if (n_train_usable <= nr + 1) return result;
    AEGIS_PROBE_MARK(PSI);

    std::vector<double> y_train(n_train_usable);
    double y_absmax = 0.0;
    for (int i = 0; i < n_train_usable; ++i) {
        y_train[i] = train_data[static_cast<size_t>(i + md) * cols + output_col];
        y_absmax = std::max(y_absmax, std::abs(y_train[i]));
    }
    const double bound = kDivergenceFactor * std::max(y_absmax, 1e-6);

    // P2'a: in the island inner loop (fit_method_ == 1) the fit and the
    // grouped ERR come from the centred Gram matrix; ill-conditioned
    // candidates fall back to the exact Householder path below.
    bool fast_done = false;
    double input_ratio = 0.0;
    if (fit_method_ == 1 && !keep_coefficients && !full_err_) {
        int reason = 0;
        fast_done = fast_fit_and_ratio(chrom, psi_train, n_train_usable, y_train.data(), output_col,
                                       input_ratio, reason);
        p2a_audit(chrom, psi_train, n_train_usable, y_train.data(), output_col, fast_done, reason, input_ratio);
    }
    if (!fast_done && !keep_coefficients &&
        !RationalModel::fit_from_psi(chrom, psi_train, n_train_usable, y_train.data())) {
        result.has_nan_inf = true;
        return result;
    }

    AEGIS_PROBE_MARK(FIT);
    // ── One-step predictions on training ──────────────────────────────
    DenominatorStats den_stats;
    std::vector<double> yhat_train;
    RationalModel::predict_from_psi(chrom, psi_train, n_train_usable, yhat_train,
                                    rational ? &den_stats : nullptr);
    const double sse_train = Metrics::sse(y_train.data(), yhat_train.data(), n_train_usable);
    if (!std::isfinite(sse_train)) { result.has_nan_inf = true; return result; }
    chrom.sse = sse_train;
    const int k = nr + 1; // regressors plus intercept

    AEGIS_PROBE_MARK(PRED);
    // ── ERR (Ψ pseudo-linearised in place; not needed afterwards) ─────
    if (fast_done) {
        chrom.err.clear();
    } else {
        if (rational) pseudo_linearize(chrom, y_train.data(), psi_train.data(), n_train_usable, nr);
        if (full_err_) chrom.err = compute_err_from_psi(psi_train, n_train_usable, nr, y_train.data());
        else chrom.err.clear();
        AEGIS_PROBE_MARK(ERRF);
        input_ratio = input_contribution_from_psi(chrom, psi_train, n_train_usable,
                                                  y_train.data(), output_col);
    }
    AEGIS_PROBE_MARK(RATIO);
    psi_train.clear();
    psi_train.shrink_to_fit();
    // ── One-step predictions on validation ────────────────────────────
    // All candidates are scored from the same row (score_start ≥ md) so that
    // models with different maximum delays are compared on identical samples.
    const int val_skip = std::max(0, weights_.score_start - md); // rows of yhat to drop
    std::vector<double> y_val_vec, yhat_val;
    if (val_data && val_rows > md + val_skip + 1) {
        std::vector<double> psi_val;
        int n_val_usable = 0;
        if (build_psi_matrix(chrom, val_data, val_rows, cols, psi_val, n_val_usable)) {
            std::vector<double> yh;
            RationalModel::predict_from_psi(chrom, psi_val, n_val_usable, yh,
                                            rational ? &den_stats : nullptr);
            for (int i = val_skip; i < n_val_usable; ++i) {
                yhat_val.push_back(yh[i]);
                y_val_vec.push_back(val_data[static_cast<size_t>(i + md) * cols + output_col]);
            }
        }
    }

    AEGIS_PROBE_MARK(VAL);
    result.metrics = Metrics::compute(
        y_train.data(), yhat_train.data(), n_train_usable,
        y_val_vec.empty() ? nullptr : y_val_vec.data(),
        yhat_val.empty()  ? nullptr : yhat_val.data(),
        static_cast<int>(y_val_vec.size()),
        nullptr, nullptr, 0,
        k
    );
    result.metrics.n_val = static_cast<int>(y_val_vec.size());

    // ── Horizon-limited free-run on validation (training if absent) ───
    double free_run_rmse = std::numeric_limits<double>::quiet_NaN();
    bool diverged = false;
    int div_step = -1;
    {
        const bool use_val = val_data && val_rows > md + 1;
        const double* sim_data = use_val ? val_data : train_data;
        const int     sim_rows = use_val ? val_rows : train_rows;
        RationalModel model(chrom);
        const int skip = std::max(0, weights_.score_start - md);
        const int horizon = (weights_.error_mode == 1 || weights_.free_run_horizon <= 0)
                                ? -1 : skip + weights_.free_run_horizon;
        FreeRunResult fr = model.simulate(sim_data, sim_rows, cols, output_col, horizon, bound);
        const int n_sim = static_cast<int>(fr.yhat.size()) - skip;
        if (n_sim > 0) {
            std::vector<double> y_sim(n_sim);
            for (int i = 0; i < n_sim; ++i)
                y_sim[i] = sim_data[static_cast<size_t>(i + skip + md) * cols + output_col];
            free_run_rmse = Metrics::rmse(y_sim.data(), fr.yhat.data() + skip, n_sim);
            result.metrics.n_free_run = n_sim;
        }
        diverged = fr.diverged;
        div_step = fr.divergence_step;
        if (rational && fr.den.samples > 0) {
            den_stats.min_abs = std::min(den_stats.min_abs, fr.den.min_abs);
        }
    }
    AEGIS_PROBE_MARK(SIM);
    result.metrics.rmse_free_run = free_run_rmse;

    // ── Stability diagnostics ─────────────────────────────────────────
    chrom.stability.min_abs_denominator = rational ? den_stats.min_abs
                                                   : std::numeric_limits<double>::quiet_NaN();
    chrom.stability.denominator_sign_changes = rational ? den_stats.sign_changes : 0;
    chrom.stability.free_run_diverged = diverged;
    chrom.stability.free_run_divergence_step = div_step;
    StabilityAnalyzer::finalize(chrom.stability, rational);

    // ── Residual–input correlation (training, lag 0) ──────────────────
    {
        std::vector<double> residuals(n_train_usable);
        for (int i = 0; i < n_train_usable; ++i) residuals[i] = y_train[i] - yhat_train[i];
        result.metrics.residual_input_corr = compute_residual_input_corr(
            residuals, train_data, train_rows, cols, output_col, md);
    }

    chrom.metrics = result.metrics;
    chrom.metrics.input_contribution_ratio = input_ratio;
    result.metrics.input_contribution_ratio = chrom.metrics.input_contribution_ratio;
    result.err_values = chrom.err;

    chrom.evaluated = true;
    assemble_fitness(chrom, output_col);
    if (!std::isfinite(chrom.fitness)) { chrom.evaluated = false; return result; }

    result.valid   = true;
    result.fitness = chrom.fitness;
    return result;
}

// ── diagnose ──────────────────────────────────────────────────────────────

ModelDiagnostics IndividualEvaluator::diagnose(
    const Chromosome& chrom,
    const double* train_data, int train_rows,
    const double* val_data,   int val_rows,
    int cols, int output_col, int max_lag
) const {
    ModelDiagnostics d;
    if (!chrom.evaluated || chrom.coefficients.size() != chrom.regressors.size()) return d;
    const int md = chrom.max_delay();
    const bool use_val = val_data && val_rows > md + max_lag + 2;
    const double* data = use_val ? val_data : train_data;
    const int rows = use_val ? val_rows : train_rows;
    d.residual_split = use_val ? "validation" : "training";

    RationalModel model(chrom);
    std::vector<double> yhat = model.predict_one_step(data, rows, cols, output_col);
    const int n = static_cast<int>(yhat.size());
    if (n <= max_lag + 2) return d;
    std::vector<double> res(n);
    for (int i = 0; i < n; ++i)
        res[i] = data[static_cast<size_t>(i + md) * cols + output_col] - yhat[i];

    d.residual_acf = ResidualAnalyzer::autocorrelation(res.data(), n, max_lag);
    d.residual_acf_bound = 1.96 / std::sqrt(static_cast<double>(n));
    int exceed = 0;
    double mx = 0.0;
    for (int l = 1; l < static_cast<int>(d.residual_acf.size()); ++l) {
        const double a = std::abs(d.residual_acf[l]);
        mx = std::max(mx, a);
        if (a > d.residual_acf_bound) ++exceed;
    }
    d.residual_acf_max_abs = mx;
    // White if at most one of max_lag lags falls outside the 95% band.
    d.residual_white = exceed <= 1;

    double ccf_max = 0.0;
    int ccf_exceed = 0, ccf_total = 0;
    for (int var = 0; var < cols; ++var) {
        if (var == output_col) continue;
        std::vector<double> u(n);
        for (int i = 0; i < n; ++i) u[i] = data[static_cast<size_t>(i + md) * cols + var];
        auto cc = ResidualAnalyzer::cross_correlation(res.data(), u.data(), n, max_lag);
        for (double v : cc) {
            ccf_max = std::max(ccf_max, std::abs(v));
            if (std::abs(v) > d.residual_acf_bound) ++ccf_exceed;
            ++ccf_total;
        }
    }
    d.residual_input_ccf_max = ccf_total > 0 ? ccf_max : std::numeric_limits<double>::quiet_NaN();
    d.residual_independent = ccf_total == 0 || ccf_exceed <= std::max(1, ccf_total / 20);

    if (val_data && val_rows > md + 1) {
        double y_absmax = 0.0;
        for (int i = 0; i < train_rows; ++i)
            y_absmax = std::max(y_absmax, std::abs(train_data[static_cast<size_t>(i) * cols + output_col]));
        FreeRunResult fr = model.simulate(val_data, val_rows, cols, output_col, -1,
                                          kDivergenceFactor * std::max(y_absmax, 1e-6));
        const int ns = static_cast<int>(fr.yhat.size());
        if (ns > 1) {
            std::vector<double> ys(ns);
            for (int i = 0; i < ns; ++i) ys[i] = val_data[static_cast<size_t>(i + md) * cols + output_col];
            d.free_run_rmse_val_full = Metrics::rmse(ys.data(), fr.yhat.data(), ns);
            d.free_run_r2_val_full   = Metrics::r2(ys.data(), fr.yhat.data(), ns);
        }
        d.free_run_val_diverged = fr.diverged;
    }

    d.linear_spectral_radius = StabilityAnalyzer::linear_spectral_radius(chrom, output_col);

    const auto& m = chrom.metrics;
    if (std::isfinite(m.rmse_train) && std::isfinite(m.rmse_val)) {
        OverfittingDetector od;
        auto r = od.detect(m.rmse_train, m.rmse_val, m.n_params, m.n_train);
        d.overfit_gap_ratio = r.gap_ratio;
        d.overfitting = r.detected;
    }
    if (std::isfinite(m.rmse_train)) {
        // output std on the training split
        double mean = 0.0;
        for (int i = 0; i < train_rows; ++i) mean += train_data[static_cast<size_t>(i) * cols + output_col];
        mean /= std::max(1, train_rows);
        double var = 0.0;
        for (int i = 0; i < train_rows; ++i) {
            const double e = train_data[static_cast<size_t>(i) * cols + output_col] - mean;
            var += e * e;
        }
        const double ystd = std::sqrt(var / std::max(1, train_rows));
        UnderfittingDetector ud;
        d.underfitting = ud.detect(m.rmse_train, ystd, m.r2_train).detected;
    }
    d.valid = true;
    return d;
}

} // namespace aegis
