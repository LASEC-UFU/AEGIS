#include "aegis/sim_refiner.hpp"
#include "aegis/rational_model.hpp"
#include "aegis/safe_power.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>

namespace aegis {

// ── admissibility ────────────────────────────────────────────────────────

bool free_run_admissible(const Chromosome& c, const double* train, int train_rows,
                         const double* val, int val_rows, int cols, int out, double bound) {
    if (c.coefficients.size() != c.regressors.size()) return false;
    RationalModel model(c);
    auto check = [&](const double* d, int rows) {
        if (!d || rows <= c.max_delay() + 1) return true;
        const FreeRunResult fr = model.simulate(d, rows, cols, out, -1, bound);
        if (fr.yhat.empty() || fr.diverged) return false;
        if (c.is_rational() && fr.den.samples > 0 && fr.den.min_abs < kMinDenominator) return false;
        return true;
    };
    return check(train, train_rows) && check(val, val_rows);
}

// ── simulation, sensitivities and LM (ported from the validated P6 tool) ──

namespace {

struct Seg { const double* data; int rows, cols, out; double bound; };

struct Sim {
    std::vector<double> yhat;
    bool diverged = false, clamped = false, nondiff = false;
    double min_abs_den = std::numeric_limits<double>::infinity();
    int sign_changes = 0;
    double rmse(const Seg& s, int a, int b) const {
        double sse = 0.0;
        for (int k = a; k < b; ++k) {
            const double e = s.data[static_cast<size_t>(k) * s.cols + s.out] - yhat[k];
            sse += e * e;
        }
        return b > a ? std::sqrt(sse / (b - a)) : std::numeric_limits<double>::quiet_NaN();
    }
};

double dpower_hybrid(double x, double p, bool& ok) noexcept {
    if (p == 1.0) return 1.0;
    int n = 0;
    if (is_integer_exponent(p, &n)) return n == 0 ? 0.0 : n * int_power(x, n - 1);
    const double ax = std::abs(x);
    if (ax < 1e-12) { if (p < 1.0) ok = false; return 0.0; }
    return p * std::pow(ax, p - 1.0);
}

// Same arithmetic order as RationalModel::num_den_at / Regressor::evaluate.
Sim simulate(const Chromosome& c, const std::vector<double>& th, const Seg& s) {
    Sim r;
    const int md = c.max_delay();
    const bool rational = c.is_rational();
    r.yhat.assign(static_cast<size_t>(s.rows), 0.0);
    std::vector<double> buf(s.data, s.data + static_cast<size_t>(s.rows) * s.cols);
    for (int k = 0; k < std::min(md, s.rows); ++k) r.yhat[k] = buf[static_cast<size_t>(k) * s.cols + s.out];
    double prev = std::numeric_limits<double>::quiet_NaN();
    for (int k = md; k < s.rows; ++k) {
        double num = th[0], den = 1.0;
        for (size_t j = 0; j < c.regressors.size(); ++j) {
            const Regressor& reg = c.regressors[j];
            double v = 1.0;
            for (const Term& t : reg.terms) {
                const double x = buf[static_cast<size_t>(k - t.delay) * s.cols + t.variable];
                if (t.variable == s.out && t.exponent < 1.0 && std::abs(x) < 1e-12 && !is_integer_exponent(t.exponent))
                    r.nondiff = true;
                v *= power_basis(x, t.exponent, PowerMode::Hybrid);
            }
            if (reg.is_denominator()) den += th[1 + j] * v;
            else                      num += th[1 + j] * v;
        }
        if (rational) {
            r.min_abs_den = std::min(r.min_abs_den, std::abs(den));
            if (std::isfinite(prev) && ((prev > 0) != (den > 0))) ++r.sign_changes;
            prev = den;
        }
        if (std::abs(den) < kMinDenominator) { den = std::copysign(kMinDenominator, den); r.clamped = true; }
        const double y = num / den;
        if (!std::isfinite(y) || std::abs(y) > s.bound) { r.diverged = true; return r; }
        r.yhat[k] = y;
        buf[static_cast<size_t>(k) * s.cols + s.out] = y;
    }
    return r;
}

bool sensitivities(const Chromosome& c, const std::vector<double>& th, const Seg& s, const Sim& sim,
                   std::vector<double>& S) {
    const int md = c.max_delay();
    const int q = static_cast<int>(th.size());
    S.assign(static_cast<size_t>(s.rows) * q, 0.0);
    auto x_at = [&](int row, int var) {
        return var == s.out ? sim.yhat[row] : s.data[static_cast<size_t>(row) * s.cols + var];
    };
    bool ok = true;
    std::vector<double> vals, gN(q), gD(q);
    for (int k = md; k < s.rows; ++k) {
        std::fill(gN.begin(), gN.end(), 0.0);
        std::fill(gD.begin(), gD.end(), 0.0);
        gN[0] = 1.0;
        double den = 1.0;
        for (size_t j = 0; j < c.regressors.size(); ++j) {
            const Regressor& reg = c.regressors[j];
            const bool isd = reg.is_denominator();
            const size_t nt = reg.terms.size();
            vals.assign(nt, 0.0);
            double phi = 1.0;
            for (size_t f = 0; f < nt; ++f) {
                const Term& t = reg.terms[f];
                vals[f] = power_basis(x_at(k - t.delay, t.variable), t.exponent, PowerMode::Hybrid);
                phi *= vals[f];
            }
            if (isd) { gD[1 + j] += phi; den += th[1 + j] * phi; }
            else     { gN[1 + j] += phi; }
            std::vector<double>& g = isd ? gD : gN;
            for (size_t f = 0; f < nt; ++f) {
                const Term& t = reg.terms[f];
                if (t.variable != s.out) continue;
                const int src = k - t.delay;
                if (src < md) continue;
                double others = 1.0;
                for (size_t h = 0; h < nt; ++h) if (h != f) others *= vals[h];
                const double w = th[1 + j] * dpower_hybrid(x_at(src, t.variable), t.exponent, ok) * others;
                if (w == 0.0) continue;
                const double* ss = &S[static_cast<size_t>(src) * q];
                for (int i = 0; i < q; ++i) g[i] += w * ss[i];
            }
        }
        if (std::abs(den) < kMinDenominator) return false;
        const double y = sim.yhat[k];
        double* sk = &S[static_cast<size_t>(k) * q];
        for (int i = 0; i < q; ++i) sk[i] = (gN[i] - y * gD[i]) / den;
    }
    return ok;
}

bool cholesky_solve(std::vector<double> A, std::vector<double> b, int n, std::vector<double>& x) {
    for (int j = 0; j < n; ++j) {
        double d = A[static_cast<size_t>(j) * n + j];
        for (int k = 0; k < j; ++k) d -= A[static_cast<size_t>(j) * n + k] * A[static_cast<size_t>(j) * n + k];
        if (!(d > 0.0) || !std::isfinite(d)) return false;
        const double L = std::sqrt(d);
        A[static_cast<size_t>(j) * n + j] = L;
        for (int i = j + 1; i < n; ++i) {
            double s = A[static_cast<size_t>(i) * n + j];
            for (int k = 0; k < j; ++k) s -= A[static_cast<size_t>(i) * n + k] * A[static_cast<size_t>(j) * n + k];
            A[static_cast<size_t>(i) * n + j] = s / L;
        }
    }
    for (int i = 0; i < n; ++i) {
        double s = b[i];
        for (int k = 0; k < i; ++k) s -= A[static_cast<size_t>(i) * n + k] * b[k];
        b[i] = s / A[static_cast<size_t>(i) * n + i];
    }
    for (int i = n - 1; i >= 0; --i) {
        double s = b[i];
        for (int k = i + 1; k < n; ++k) s -= A[static_cast<size_t>(k) * n + i] * b[k];
        b[i] = s / A[static_cast<size_t>(i) * n + i];
    }
    x = std::move(b);
    for (double v : x) if (!std::isfinite(v)) return false;
    return true;
}

struct LMOut {
    std::vector<std::vector<double>> accepted;
    std::string status;
    int iterations = 0;
};

// Same settings and step rule as the E2/P6 LM: 100 iterations, λ0 = 1e-3,
// ×10 / ÷3, Marquardt scaling, 10 consecutive rejections, tolerances 1e-10.
LMOut levenberg_marquardt(const Chromosome& c, std::vector<double> theta, const Seg& s, int score) {
    const int max_iter = 100, max_rejects = 10;
    const double up = 10.0, down = 3.0, rel_tol = 1e-10, step_tol = 1e-10;
    LMOut res;
    res.accepted.push_back(theta);
    auto ok_sim = [](const Sim& m) { return !m.diverged && !m.clamped && !m.nondiff; };
    auto loss_of = [&](const Sim& m) {
        double sse = 0.0;
        for (int k = score; k < s.rows; ++k) {
            const double e = s.data[static_cast<size_t>(k) * s.cols + s.out] - m.yhat[k];
            sse += e * e;
        }
        return sse;
    };
    Sim sim = simulate(c, theta, s);
    if (!ok_sim(sim)) { res.status = "init_not_differentiable_or_diverged"; return res; }
    std::vector<double> S;
    if (!sensitivities(c, theta, s, sim, S)) { res.status = "init_not_differentiable"; return res; }
    double loss = loss_of(sim);
    const int q = static_cast<int>(theta.size());
    double lambda = 1e-3;
    std::vector<double> A(static_cast<size_t>(q) * q), g(q), M, delta;
    for (int it = 0; it < max_iter; ++it) {
        res.iterations = it + 1;
        std::fill(A.begin(), A.end(), 0.0);
        std::fill(g.begin(), g.end(), 0.0);
        for (int k = score; k < s.rows; ++k) {
            const double* sk = &S[static_cast<size_t>(k) * q];
            const double r = s.data[static_cast<size_t>(k) * s.cols + s.out] - sim.yhat[k];
            for (int i = 0; i < q; ++i) {
                g[i] += sk[i] * r;
                for (int j = 0; j <= i; ++j) A[static_cast<size_t>(i) * q + j] += sk[i] * sk[j];
            }
        }
        double dmax = 0.0;
        for (int i = 0; i < q; ++i) {
            for (int j = 0; j < i; ++j) A[static_cast<size_t>(j) * q + i] = A[static_cast<size_t>(i) * q + j];
            dmax = std::max(dmax, A[static_cast<size_t>(i) * q + i]);
        }
        int consecutive = 0;
        double rel = 0.0, step_norm = 0.0;
        for (;;) {
            M = A;
            for (int i = 0; i < q; ++i)
                M[static_cast<size_t>(i) * q + i] += lambda * std::max(A[static_cast<size_t>(i) * q + i], 1e-12 * std::max(dmax, 1e-300));
            bool ok = cholesky_solve(M, g, q, delta);
            Sim trial;
            std::vector<double> tt;
            double tl = 0.0;
            if (ok) {
                tt = res.accepted.back();
                step_norm = 0.0;
                for (int i = 0; i < q; ++i) { tt[i] += delta[i]; step_norm += delta[i] * delta[i]; }
                step_norm = std::sqrt(step_norm);
                trial = simulate(c, tt, s);
                ok = ok_sim(trial);
                if (ok) { tl = loss_of(trial); ok = std::isfinite(tl) && tl < loss; }
            }
            if (!ok) {
                lambda *= up;
                if (++consecutive >= max_rejects) { res.status = "max_rejects"; return res; }
                continue;
            }
            rel = (loss - tl) / std::max(loss, 1e-300);
            loss = tl;
            res.accepted.push_back(tt);
            sim = std::move(trial);
            lambda /= down;
            break;
        }
        double tn = 0.0;
        for (double v : res.accepted.back()) tn += v * v;
        if (rel < rel_tol || step_norm <= step_tol * (std::sqrt(tn) + step_tol)) { res.status = "converged"; return res; }
        if (!sensitivities(c, res.accepted.back(), s, sim, S)) { res.status = "not_differentiable"; return res; }
    }
    res.status = "max_iter";
    return res;
}

struct Scores { bool traj_ok = false; double train = 0, va = 0, vb = 0, min_abs_den = 0; int sign_changes = 0; };

Scores score(const Chromosome& c, const std::vector<double>& th, const Seg& tr, const Seg& va,
             int ctx, int split) {
    Scores r;
    const Sim a = simulate(c, th, tr), b = simulate(c, th, va);
    r.traj_ok = !a.diverged && !b.diverged && !a.clamped && !b.clamped;
    if (!r.traj_ok) return r;
    r.train = a.rmse(tr, std::max(ctx, c.max_delay()), tr.rows);
    r.va = b.rmse(va, ctx, split);
    r.vb = b.rmse(va, split, va.rows);
    if (c.is_rational()) {
        r.min_abs_den = std::min(a.min_abs_den, b.min_abs_den);
        r.sign_changes = a.sign_changes + b.sign_changes;
    }
    return r;
}

} // namespace

SimRefineResult refine_by_simulation(const Chromosome& c, const double* data, int cols, int out,
                                     int train_end, int val_end, int ctx, double bound) {
    SimRefineResult res;
    res.coefficients = c.coefficients;
    res.intercept = c.intercept;
    if (c.power_mode != PowerMode::Hybrid) { res.status = "skipped_power_mode"; return res; }
    if (c.coefficients.size() != c.regressors.size() || c.regressors.empty()) { res.status = "skipped_unfitted"; return res; }
    if (c.max_delay() > ctx || train_end - ctx <= 0 || val_end - train_end < 4) { res.status = "skipped_split"; return res; }
    const auto t0 = std::chrono::steady_clock::now();
    const Seg tr{data, train_end, cols, out, bound};
    const Seg va{data + static_cast<size_t>(train_end - ctx) * cols, val_end - (train_end - ctx), cols, out, bound};
    const int split = ctx + (val_end - train_end) / 2;
    std::vector<double> th0(1 + c.coefficients.size());
    th0[0] = c.intercept;
    for (size_t j = 0; j < c.coefficients.size(); ++j) th0[1 + j] = c.coefficients[j];
    const Scores s0 = score(c, th0, tr, va, ctx, split);
    if (!s0.traj_ok) { res.status = "skipped_original_inadmissible"; return res; }
    res.ran = true;
    res.tau = c.is_rational() ? std::min(0.01, 0.5 * s0.min_abs_den) : 0.0;
    const LMOut lm = levenberg_marquardt(c, th0, tr, std::max(ctx, c.max_delay()));
    res.status = lm.status;
    res.iterations = lm.iterations;
    res.accepted = static_cast<int>(lm.accepted.size()) - 1;
    Scores best = s0;
    int bi = 0;
    for (size_t it = 0; it < lm.accepted.size(); ++it) {
        const Scores si = it == 0 ? s0 : score(c, lm.accepted[it], tr, va, ctx, split);
        bool adm = si.traj_ok;
        if (adm && c.is_rational()) adm = si.sign_changes <= s0.sign_changes && si.min_abs_den >= res.tau;
        if (!adm) continue;
        ++res.admissible_iterates;
        if (si.va < best.va) { best = si; bi = static_cast<int>(it); }
    }
    res.chosen_iterate = bi;
    res.train0 = s0.train; res.va0 = s0.va; res.vb0 = s0.vb;
    res.train = best.train; res.va = best.va; res.vb = best.vb;
    res.intercept = lm.accepted[bi][0];
    res.coefficients.assign(lm.accepted[bi].begin() + 1, lm.accepted[bi].end());
    res.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return res;
}

} // namespace aegis
