// phase0_core.hpp — Phase 0 building blocks (experiments/phase0/PHASE0_PREREG.md):
// free-run simulation with the core's exact conventions, forward output
// sensitivities, Levenberg–Marquardt on the training simulation error, and a
// univariate FROLS/ERR selector. Polynomial models in the hybrid power basis
// only; rational models are reported as "not run" by the caller.
#pragma once
#include "aegis/regressor_library.hpp"
#include "aegis/safe_power.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace phase0 {

using aegis::Chromosome;
using aegis::PowerMode;
using aegis::Regressor;
using aegis::Term;

/** d/dx power_basis(x, p, Hybrid). `ok` is cleared when the derivative does
 *  not exist (non-integer p < 1 at |x| < 1e-12). */
inline double dpower_hybrid(double x, double p, bool& ok) noexcept {
    if (p == 1.0) return 1.0;
    int n = 0;
    if (aegis::is_integer_exponent(p, &n)) return n == 0 ? 0.0 : n * aegis::int_power(x, n - 1);
    const double ax = std::abs(x);
    if (ax < 1e-12) {
        if (p < 1.0) ok = false;
        return 0.0;
    }
    return p * std::pow(ax, p - 1.0);
}

/** A model is supported by the simulator/LM when it is polynomial (no
 *  denominator) in the hybrid basis. */
inline bool supported(const Chromosome& c, std::string* why = nullptr) {
    if (c.is_rational()) { if (why) *why = "rational model"; return false; }
    if (c.power_mode != PowerMode::Hybrid) { if (why) *why = "non-hybrid power basis"; return false; }
    if (c.regressors.empty()) { if (why) *why = "no regressors"; return false; }
    return true;
}

/** Training-segment problem in normalized coordinates, with the evaluator's
 *  conventions: simulation starts at the model's own maximum delay (measured
 *  outputs before it), scoring from max(score_start, md) to seg_end-1. */
struct Problem {
    const double* data = nullptr; // normalized, row-major [rows x cols]
    int rows = 0, cols = 0, out = 0;
    int seg_end = 0;      // exclusive
    int score_start = 40; // AEGIS maxDelay context
    double bound = 10.0;  // divergence bound (kDivergenceFactor * max|y_train|)
};

/** Parameter vector layout: theta[0] = intercept, theta[1+j] = coefficient j. */
inline std::vector<double> pack(const Chromosome& c) {
    std::vector<double> t(1 + c.coefficients.size());
    t[0] = c.intercept;
    for (size_t j = 0; j < c.coefficients.size(); ++j) t[1 + j] = c.coefficients[j];
    return t;
}
inline void unpack(const std::vector<double>& t, Chromosome& c) {
    c.intercept = t[0];
    c.coefficients.assign(t.begin() + 1, t.end());
}

struct SimResult {
    std::vector<double> yhat;   // full length seg_end; measured values before md
    double sse = std::numeric_limits<double>::quiet_NaN();
    int n = 0;
    bool diverged = false;
    bool nondifferentiable = false;
};

/** Free-run simulation of the training segment. Divergence (non-finite or
 *  |yhat| > bound) stops the simulation and flags the result. */
inline SimResult simulate(const Chromosome& c, const std::vector<double>& theta, const Problem& pb) {
    SimResult r;
    const int md = c.max_delay();
    const int end = pb.seg_end;
    r.yhat.resize(static_cast<size_t>(end));
    std::vector<double> buf(pb.data, pb.data + static_cast<size_t>(end) * pb.cols);
    for (int k = 0; k < std::min(md, end); ++k) r.yhat[k] = buf[static_cast<size_t>(k) * pb.cols + pb.out];
    const int score = std::max(pb.score_start, md);
    double sse = 0.0;
    int n = 0;
    for (int k = md; k < end; ++k) {
        double y = theta[0];
        for (size_t j = 0; j < c.regressors.size(); ++j) {
            const Regressor& reg = c.regressors[j];
            double v = 1.0;
            for (const Term& t : reg.terms) {
                const double x = buf[static_cast<size_t>(k - t.delay) * pb.cols + t.variable];
                if (!(t.exponent == 1.0) && t.exponent < 1.0 && std::abs(x) < 1e-12 &&
                    !aegis::is_integer_exponent(t.exponent))
                    r.nondifferentiable = true;
                v *= aegis::power_basis(x, t.exponent, PowerMode::Hybrid);
            }
            y += theta[1 + j] * v;
        }
        if (!std::isfinite(y) || std::abs(y) > pb.bound) { r.diverged = true; return r; }
        r.yhat[k] = y;
        buf[static_cast<size_t>(k) * pb.cols + pb.out] = y;
        if (k >= score) {
            const double e = pb.data[static_cast<size_t>(k) * pb.cols + pb.out] - y;
            sse += e * e;
            ++n;
        }
    }
    r.sse = sse;
    r.n = n;
    return r;
}

/** Forward sensitivities S[k*q + j] = d yhat(k) / d theta_j along a
 *  non-diverged trajectory `yhat` (from simulate). Rows before md are zero. */
inline bool sensitivities(const Chromosome& c, const std::vector<double>& theta, const Problem& pb,
                          const std::vector<double>& yhat, std::vector<double>& S) {
    const int md = c.max_delay();
    const int end = pb.seg_end;
    const int q = static_cast<int>(theta.size());
    S.assign(static_cast<size_t>(end) * q, 0.0);
    auto x_at = [&](int row, int var) {
        return var == pb.out ? yhat[row] : pb.data[static_cast<size_t>(row) * pb.cols + var];
    };
    bool ok = true;
    std::vector<double> vals;
    for (int k = md; k < end; ++k) {
        double* sk = &S[static_cast<size_t>(k) * q];
        sk[0] = 1.0;
        for (size_t j = 0; j < c.regressors.size(); ++j) {
            const Regressor& reg = c.regressors[j];
            const size_t nt = reg.terms.size();
            vals.assign(nt, 0.0);
            double phi = 1.0;
            for (size_t f = 0; f < nt; ++f) {
                const Term& t = reg.terms[f];
                vals[f] = aegis::power_basis(x_at(k - t.delay, t.variable), t.exponent, PowerMode::Hybrid);
                phi *= vals[f];
            }
            sk[1 + j] += phi;
            // Indirect dependence through simulated outputs.
            for (size_t f = 0; f < nt; ++f) {
                const Term& t = reg.terms[f];
                if (t.variable != pb.out) continue;
                const int src = k - t.delay;
                if (src < md) continue; // measured initial context: zero sensitivity
                double others = 1.0;
                for (size_t g = 0; g < nt; ++g) if (g != f) others *= vals[g];
                const double dphi = dpower_hybrid(x_at(src, t.variable), t.exponent, ok) * others;
                const double w = theta[1 + j] * dphi;
                if (w == 0.0) continue;
                const double* ss = &S[static_cast<size_t>(src) * q];
                for (int i = 0; i < q; ++i) sk[i] += w * ss[i];
            }
        }
    }
    return ok;
}

/** In-place Cholesky solve of A x = b (A symmetric, row-major n x n).
 *  Returns false when A is not numerically positive definite. */
inline bool cholesky_solve(std::vector<double> A, std::vector<double> b, int n, std::vector<double>& x) {
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

struct LMSettings {
    int max_iter = 100;
    int max_consecutive_rejects = 10;
    double lambda0 = 1e-3;
    double up = 10.0, down = 3.0;
    double rel_loss_tol = 1e-10;
    double step_tol = 1e-10;
};

struct LMResult {
    std::vector<double> theta;  // last accepted parameters (never fabricated)
    double loss0 = std::numeric_limits<double>::quiet_NaN();
    double loss  = std::numeric_limits<double>::quiet_NaN();
    int iterations = 0, accepted = 0, rejected = 0;
    std::string status;         // converged | max_iter | max_rejects | init_diverged | nondifferentiable_init
};

/** Levenberg–Marquardt on the training free-run SSE (Marquardt scaling). */
inline LMResult levenberg_marquardt(const Chromosome& c, std::vector<double> theta, const Problem& pb,
                                    const LMSettings& st = {}) {
    LMResult res;
    res.theta = theta;
    SimResult sim = simulate(c, theta, pb);
    if (sim.diverged || !std::isfinite(sim.sse)) { res.status = "init_diverged"; return res; }
    if (sim.nondifferentiable) { res.status = "nondifferentiable_init"; return res; }
    std::vector<double> S;
    if (!sensitivities(c, theta, pb, sim.yhat, S)) { res.status = "nondifferentiable_init"; return res; }
    res.loss0 = res.loss = sim.sse;
    const int q = static_cast<int>(theta.size());
    const int md = c.max_delay();
    const int score = std::max(pb.score_start, md);
    double lambda = st.lambda0;
    std::vector<double> A(static_cast<size_t>(q) * q), g(q), M, delta;
    for (int it = 0; it < st.max_iter; ++it) {
        res.iterations = it + 1;
        std::fill(A.begin(), A.end(), 0.0);
        std::fill(g.begin(), g.end(), 0.0);
        for (int k = score; k < pb.seg_end; ++k) {
            const double* sk = &S[static_cast<size_t>(k) * q];
            const double r = pb.data[static_cast<size_t>(k) * pb.cols + pb.out] - sim.yhat[k];
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
        bool accepted = false;
        double rel = 0.0, step_norm = 0.0;
        SimResult trial;
        std::vector<double> trial_theta;
        while (!accepted) {
            M = A;
            for (int i = 0; i < q; ++i)
                M[static_cast<size_t>(i) * q + i] += lambda * std::max(A[static_cast<size_t>(i) * q + i], 1e-12 * std::max(dmax, 1e-300));
            bool ok = cholesky_solve(M, g, q, delta);
            if (ok) {
                trial_theta = res.theta;
                step_norm = 0.0;
                for (int i = 0; i < q; ++i) { trial_theta[i] += delta[i]; step_norm += delta[i] * delta[i]; }
                step_norm = std::sqrt(step_norm);
                trial = simulate(c, trial_theta, pb);
                ok = !trial.diverged && !trial.nondifferentiable && std::isfinite(trial.sse) && trial.sse < res.loss;
            }
            if (!ok) {
                ++res.rejected;
                lambda *= st.up;
                if (++consecutive >= st.max_consecutive_rejects) { res.status = "max_rejects"; return res; }
                continue;
            }
            accepted = true;
            ++res.accepted;
            rel = (res.loss - trial.sse) / std::max(res.loss, 1e-300);
            res.theta = trial_theta;
            res.loss = trial.sse;
            sim = std::move(trial);
            lambda /= st.down;
        }
        double tn = 0.0;
        for (double v : res.theta) tn += v * v;
        if (rel < st.rel_loss_tol || step_norm <= st.step_tol * (std::sqrt(tn) + st.step_tol)) {
            res.status = "converged";
            return res;
        }
        if (!sensitivities(c, res.theta, pb, sim.yhat, S)) {
            // Accepted trajectories are checked for non-differentiable points
            // in simulate(); reaching here would be an internal inconsistency.
            res.status = "nondifferentiable_internal";
            return res;
        }
    }
    res.status = "max_iter";
    return res;
}

// ── Univariate FROLS / ERR selector (training one-step, centred) ─────────────

struct Candidate { int var; int delay; int power; };

inline std::string label(const Candidate& c, int out) {
    std::ostringstream s;
    s << (c.var == out ? "y" : "u" + std::to_string(c.var)) << "(k-" << c.delay << ")";
    if (c.power != 1) s << "^" << c.power;
    return s.str();
}

/** Orthogonal forward selection. `forced` candidates (indices into cands) are
 *  orthogonalized first, in order; then `n_select` more are chosen by ERR
 *  (ties: lowest index). Rows k in [first_row, end) of normalized data. */
inline std::vector<int> frols_select(const std::vector<Candidate>& cands, const std::vector<int>& forced,
                                     int n_select, const double* data, int cols, int out,
                                     int first_row, int end, std::vector<double>* err_out = nullptr) {
    const int M = static_cast<int>(cands.size());
    const int N = end - first_row;
    std::vector<double> W(static_cast<size_t>(M) * N), y(N);
    double ym = 0.0;
    for (int i = 0; i < N; ++i) { y[i] = data[static_cast<size_t>(i + first_row) * cols + out]; ym += y[i]; }
    ym /= N;
    double sigma = 0.0;
    for (int i = 0; i < N; ++i) { y[i] -= ym; sigma += y[i] * y[i]; }
    std::vector<double> norm0(M);
    for (int j = 0; j < M; ++j) {
        double* w = &W[static_cast<size_t>(j) * N];
        double mean = 0.0;
        for (int i = 0; i < N; ++i) {
            const int k = i + first_row;
            w[i] = aegis::int_power(data[static_cast<size_t>(k - cands[j].delay) * cols + cands[j].var], cands[j].power);
            mean += w[i];
        }
        mean /= N;
        double s = 0.0;
        for (int i = 0; i < N; ++i) { w[i] -= mean; s += w[i] * w[i]; }
        norm0[j] = s;
    }
    std::vector<char> active(M, 1);
    std::vector<int> chosen;
    auto orthogonalize_against = [&](int best) {
        const double* q = &W[static_cast<size_t>(best) * N];
        double qq = 0.0;
        for (int i = 0; i < N; ++i) qq += q[i] * q[i];
        if (qq <= 0.0) return;
        for (int j = 0; j < M; ++j) {
            if (!active[j]) continue;
            double* w = &W[static_cast<size_t>(j) * N];
            double dot = 0.0;
            for (int i = 0; i < N; ++i) dot += q[i] * w[i];
            const double a = dot / qq;
            for (int i = 0; i < N; ++i) w[i] -= a * q[i];
        }
    };
    for (int f : forced) {
        if (f < 0 || f >= M || !active[f]) continue;
        active[f] = 0;
        chosen.push_back(f);
        if (err_out) err_out->push_back(std::numeric_limits<double>::quiet_NaN());
        orthogonalize_against(f);
    }
    for (int step = 0; step < n_select; ++step) {
        int best = -1;
        double best_err = -1.0;
        for (int j = 0; j < M; ++j) {
            if (!active[j]) continue;
            const double* w = &W[static_cast<size_t>(j) * N];
            double ww = 0.0, wy = 0.0;
            for (int i = 0; i < N; ++i) { ww += w[i] * w[i]; wy += w[i] * y[i]; }
            if (ww <= 1e-10 * std::max(norm0[j], 1e-300)) { active[j] = 0; continue; }
            const double e = wy * wy / (ww * sigma);
            if (e > best_err) { best_err = e; best = j; }
        }
        if (best < 0) break;
        active[best] = 0;
        chosen.push_back(best);
        if (err_out) err_out->push_back(best_err);
        orthogonalize_against(best);
    }
    return chosen;
}

/** Model JSON for the evaluator (hybrid basis, numerator only). */
inline std::string model_json(const std::vector<Candidate>& regs, const std::vector<double>* theta = nullptr) {
    std::ostringstream j;
    j.precision(17);
    j << "{\"powerMode\":\"hybrid\",\"regressors\":[";
    for (size_t i = 0; i < regs.size(); ++i) {
        if (i) j << ",";
        j << "{\"terms\":[{\"variable\":" << regs[i].var << ",\"delay\":" << regs[i].delay
          << ",\"exponent\":" << regs[i].power << ",\"isDenominator\":false}]}";
    }
    j << "]";
    if (theta) {
        j << ",\"intercept\":" << (*theta)[0] << ",\"coefficients\":[";
        for (size_t i = 1; i < theta->size(); ++i) { if (i > 1) j << ","; j << (*theta)[i]; }
        j << "]";
    }
    j << "}";
    return j.str();
}

/** Canonical identity of a structure: sorted regressors with sorted factors. */
inline std::string canonical_key(const Chromosome& c) {
    std::vector<std::string> regs;
    for (const Regressor& r : c.regressors) {
        std::vector<std::string> ts;
        for (const Term& t : r.terms) {
            std::ostringstream s;
            s.precision(6);
            s << (t.is_denominator ? "D" : "N") << t.variable << ":" << t.delay << "^" << t.exponent;
            ts.push_back(s.str());
        }
        std::sort(ts.begin(), ts.end());
        std::string joined;
        for (const auto& s : ts) joined += s + "*";
        regs.push_back(joined);
    }
    std::sort(regs.begin(), regs.end());
    std::string key;
    for (const auto& s : regs) key += s + "|";
    return key;
}

} // namespace phase0
