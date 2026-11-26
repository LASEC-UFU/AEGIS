// p6_core.hpp — P6 (experiments/p6/P6_PREREG.md): free-run simulation of
// RATIONAL models with the core's conventions (RationalModel::simulate),
// exact forward sensitivities for numerator and denominator coefficients,
// and Levenberg–Marquardt on the training free-run SSE that records every
// accepted iterate (the caller applies the admissibility veto and chooses on
// V_A). Hybrid power basis only.
#pragma once
#include "aegis/regressor_library.hpp"
#include "aegis/safe_power.hpp"
#include "phase0_core.hpp"   // dpower_hybrid, cholesky_solve, pack/unpack, LMSettings

#include <cmath>
#include <limits>
#include <vector>

namespace p6 {

using aegis::Chromosome;
using aegis::PowerMode;
using aegis::Regressor;
using aegis::Term;

constexpr double kMinDen = 1e-12; // RationalModel kMinDenominator

/** A contiguous block of normalized data. Rows before the model's maximum
 *  delay are measured context; scoring windows are given in block rows. */
struct Seg {
    const double* data = nullptr;
    int rows = 0, cols = 0, out = 1;
    double bound = 10.0;
};

struct Sim {
    std::vector<double> yhat;  // block length; measured values before md
    std::vector<double> den;   // raw D(k) (rational only), NaN before md
    bool diverged = false;     // stopped at the first divergent step
    bool clamped = false;      // |D| < kMinDen happened (non-differentiable)
    bool nondiff = false;      // non-integer p < 1 at |x| < 1e-12
    double min_abs_den = std::numeric_limits<double>::infinity();
    int sign_changes = 0;
    double sse(int a, int b, const double* data, int cols, int out, int& n) const {
        double s = 0.0; n = 0;
        for (int k = a; k < b; ++k) {
            const double e = data[static_cast<size_t>(k) * cols + out] - yhat[k];
            s += e * e; ++n;
        }
        return s;
    }
};

/** Same arithmetic order as RationalModel::num_den_at / Regressor::evaluate. */
inline Sim simulate(const Chromosome& c, const std::vector<double>& th, const Seg& s) {
    Sim r;
    const int md = c.max_delay();
    const bool rational = c.is_rational();
    r.yhat.assign(static_cast<size_t>(s.rows), 0.0);
    r.den.assign(static_cast<size_t>(s.rows), std::numeric_limits<double>::quiet_NaN());
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
                // Only factors of the simulated output need d/dx (inputs do not depend on θ).
                if (t.variable == s.out && t.exponent < 1.0 && std::abs(x) < 1e-12 &&
                    !aegis::is_integer_exponent(t.exponent))
                    r.nondiff = true;
                v *= aegis::power_basis(x, t.exponent, PowerMode::Hybrid);
            }
            if (reg.is_denominator()) den += th[1 + j] * v;
            else                      num += th[1 + j] * v;
        }
        if (rational) {
            r.den[k] = den;
            r.min_abs_den = std::min(r.min_abs_den, std::abs(den));
            if (std::isfinite(prev) && ((prev > 0) != (den > 0))) ++r.sign_changes;
            prev = den;
        }
        if (std::abs(den) < kMinDen) { den = std::copysign(kMinDen, den); r.clamped = true; }
        const double y = num / den;
        if (!std::isfinite(y) || std::abs(y) > s.bound) { r.diverged = true; return r; }
        r.yhat[k] = y;
        buf[static_cast<size_t>(k) * s.cols + s.out] = y;
    }
    return r;
}

/** Forward sensitivities S[k*q + i] = d yhat(k) / d theta_i, theta = [c, θ_1..θ_K].
 *  yhat(k) = N(k)/D(k); dN and dD include the dependence through past
 *  simulated outputs. Rows before md are zero (measured context). */
inline bool sensitivities(const Chromosome& c, const std::vector<double>& th, const Seg& s,
                          const Sim& sim, std::vector<double>& S) {
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
                vals[f] = aegis::power_basis(x_at(k - t.delay, t.variable), t.exponent, PowerMode::Hybrid);
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
                const double w = th[1 + j] * phase0::dpower_hybrid(x_at(src, t.variable), t.exponent, ok) * others;
                if (w == 0.0) continue;
                const double* ss = &S[static_cast<size_t>(src) * q];
                for (int i = 0; i < q; ++i) g[i] += w * ss[i];
            }
        }
        if (std::abs(den) < kMinDen) return false;
        const double y = sim.yhat[k];
        double* sk = &S[static_cast<size_t>(k) * q];
        for (int i = 0; i < q; ++i) sk[i] = (gN[i] - y * gD[i]) / den;
    }
    return ok;
}

struct LMOut {
    std::vector<std::vector<double>> accepted; // iterate 0 first, then each accepted step
    std::string status;
    int iterations = 0, rejected = 0;
    double loss0 = std::numeric_limits<double>::quiet_NaN(), loss = loss0;
};

/** LM on the training free-run SSE, scored on block rows [score, rows).
 *  Same settings and step rule as phase0::levenberg_marquardt (E2). */
inline LMOut levenberg_marquardt(const Chromosome& c, std::vector<double> theta, const Seg& s, int score,
                                 const phase0::LMSettings& st = {}) {
    LMOut res;
    res.accepted.push_back(theta);
    auto ok_sim = [](const Sim& m) { return !m.diverged && !m.clamped && !m.nondiff; };
    auto loss_of = [&](const Sim& m) { int n; return m.sse(score, s.rows, s.data, s.cols, s.out, n); };
    Sim sim = simulate(c, theta, s);
    if (!ok_sim(sim)) { res.status = "init_not_differentiable_or_diverged"; return res; }
    std::vector<double> S;
    if (!sensitivities(c, theta, s, sim, S)) { res.status = "init_not_differentiable"; return res; }
    res.loss0 = res.loss = loss_of(sim);
    const int q = static_cast<int>(theta.size());
    double lambda = st.lambda0;
    std::vector<double> A(static_cast<size_t>(q) * q), g(q), M, delta;
    for (int it = 0; it < st.max_iter; ++it) {
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
            bool ok = phase0::cholesky_solve(M, g, q, delta);
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
                if (ok) { tl = loss_of(trial); ok = std::isfinite(tl) && tl < res.loss; }
            }
            if (!ok) {
                ++res.rejected;
                lambda *= st.up;
                if (++consecutive >= st.max_consecutive_rejects) { res.status = "max_rejects"; return res; }
                continue;
            }
            rel = (res.loss - tl) / std::max(res.loss, 1e-300);
            res.loss = tl;
            res.accepted.push_back(tt);
            sim = std::move(trial);
            lambda /= st.down;
            break;
        }
        double tn = 0.0;
        for (double v : res.accepted.back()) tn += v * v;
        if (rel < st.rel_loss_tol || step_norm <= st.step_tol * (std::sqrt(tn) + st.step_tol)) {
            res.status = "converged";
            return res;
        }
        if (!sensitivities(c, res.accepted.back(), s, sim, S)) { res.status = "not_differentiable"; return res; }
    }
    res.status = "max_iter";
    return res;
}

} // namespace p6
