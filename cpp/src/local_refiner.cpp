#include "aegis/local_refiner.hpp"
#include "aegis/rational_model.hpp"
#include "aegis/safe_power.hpp"
#include <cmath>
#include <algorithm>
#include <numeric>
#include <sstream>

namespace aegis {

// ── Numerical Jacobian ────────────────────────────────────────────────────

void LocalRefiner::compute_jacobian(
    const std::vector<double>& theta,
    const Chromosome&          chrom,
    const double*              data, int rows, int cols, int output_col,
    std::vector<double>&       J,
    std::vector<double>&       r
) const {
    int md  = chrom.max_delay();
    int n   = rows - md;
    int np  = static_cast<int>(theta.size());
    J.assign((size_t)n * np, 0.0);
    r.resize(n);

    const double h = 1e-6; // finite difference step

    // Evaluate at theta
    Chromosome c0 = chrom;
    c0.coefficients = theta;
    RationalModel m0(c0);
    auto yhat0 = m0.predict_one_step(data, rows, cols, output_col);

    for (int i = 0; i < n; ++i)
        r[i] = data[(i + md) * cols + output_col] - yhat0[i];

    // Perturb each coefficient
    for (int p = 0; p < np; ++p) {
        std::vector<double> theta_p = theta;
        theta_p[p] += h;
        Chromosome cp = chrom;
        cp.coefficients = theta_p;
        RationalModel mp(cp);
        auto yhat_p = mp.predict_one_step(data, rows, cols, output_col);

        for (int i = 0; i < n; ++i)
            J[i * np + p] = (yhat_p[i] - yhat0[i]) / h; // ∂yhat/∂θ_p
    }
}

// ── Trust Region Reflective (simplified) ─────────────────────────────────

RefineResult LocalRefiner::refine_trf(
    const Chromosome& chrom,
    const double* data, int rows, int cols, int output_col
) const {
    RefineResult res;
    if (chrom.coefficients.empty()) {
        res.message = "No coefficients to refine";
        return res;
    }

    // Polynomial model with QR: already the global optimum for linear coeff
    if (!chrom.is_rational()) {
        res.coefficients = chrom.coefficients;
        res.converged    = true;
        res.message      = "Polynomial: QR solution is exact";
        // Compute SSE
        RationalModel m(chrom);
        int md = chrom.max_delay();
        int n  = rows - md;
        auto yhat = m.predict_one_step(data, rows, cols, output_col);
        double s = 0.0;
        for (int i = 0; i < n; ++i) {
            double e = data[(i + md) * cols + output_col] - yhat[i];
            s += e * e;
        }
        res.initial_sse = s;
        res.final_sse   = s;
        res.iterations  = 0;
        return res;
    }

    // Rational model: iterative TRF
    std::vector<double> theta = chrom.coefficients;
    int np = static_cast<int>(theta.size());

    std::vector<double> J, r;
    compute_jacobian(theta, chrom, data, rows, cols, output_col, J, r);

    double sse_prev = 0.0;
    for (double ri : r) sse_prev += ri * ri;
    res.initial_sse = sse_prev;

    double delta = cfg_.initial_delta; // trust region radius

    for (int iter = 0; iter < cfg_.max_iter; ++iter) {
        // Normal equations: (J^T J + lambda * I) * step = J^T r
        int n = static_cast<int>(r.size());
        std::vector<double> JtJ((size_t)np * np, 0.0);
        std::vector<double> Jtr(np, 0.0);
        for (int i = 0; i < n; ++i) {
            for (int p = 0; p < np; ++p) {
                Jtr[p] += J[i * np + p] * r[i];
                for (int q = 0; q <= p; ++q)
                    JtJ[p * np + q] += J[i * np + p] * J[i * np + q];
            }
        }
        for (int p = 0; p < np; ++p)
            for (int q = p + 1; q < np; ++q)
                JtJ[p * np + q] = JtJ[q * np + p];

        // Add Tikhonov regularisation scaled by trust region
        double lambda = 1.0 / (delta + 1e-30);
        for (int p = 0; p < np; ++p) JtJ[p * np + p] += lambda;

        // Solve via Cholesky (small system)
        std::vector<double> step = Jtr;
        // Simple Gauss elimination
        std::vector<double> A_aug((size_t)np * (np + 1));
        for (int i = 0; i < np; ++i) {
            for (int j = 0; j < np; ++j) A_aug[i * (np + 1) + j] = JtJ[i * np + j];
            A_aug[i * (np + 1) + np] = Jtr[i];
        }
        for (int col = 0; col < np; ++col) {
            double piv = A_aug[col * (np + 1) + col];
            if (std::abs(piv) < 1e-30) goto next_iter;
            for (int j = col; j <= np; ++j) A_aug[col * (np + 1) + j] /= piv;
            for (int row = 0; row < np; ++row) {
                if (row == col) continue;
                double f = A_aug[row * (np + 1) + col];
                for (int j = col; j <= np; ++j)
                    A_aug[row * (np + 1) + j] -= f * A_aug[col * (np + 1) + j];
            }
        }
        for (int i = 0; i < np; ++i) step[i] = A_aug[i * (np + 1) + np];

        {
            // Trial point
            std::vector<double> theta_new(np);
            for (int p = 0; p < np; ++p) theta_new[p] = theta[p] + step[p];

            compute_jacobian(theta_new, chrom, data, rows, cols, output_col, J, r);
            double sse_new = 0.0;
            for (double ri : r) sse_new += ri * ri;

            if (sse_new < sse_prev) {
                // Accept step
                double rho = (sse_prev - sse_new) / (std::max(1e-30, sse_prev - sse_new) + 1e-30);
                if (rho > 0.75) delta *= 2.0;
                else if (rho < 0.25) delta *= 0.5;
                theta     = theta_new;
                sse_prev  = sse_new;
            } else {
                delta *= 0.5;
                // Recompute r at current theta
                compute_jacobian(theta, chrom, data, rows, cols, output_col, J, r);
            }

            res.iterations = iter + 1;
            if (sse_prev < cfg_.ftol || delta < cfg_.xtol) {
                res.converged = true;
                break;
            }
        }
        next_iter:;
    }

    res.coefficients = theta;
    res.final_sse    = sse_prev;
    res.message      = res.converged ? "Converged" : "Max iterations reached";
    return res;
}

RefineResult LocalRefiner::refine_lm(
    const Chromosome& chrom,
    const double* data, int rows, int cols, int output_col
) const {
    // LM is similar to TRF with fixed trust region adaptation
    // Delegate to TRF with adjusted config
    RefineConfig lm_cfg = cfg_;
    lm_cfg.initial_delta = 1.0 / lm_cfg.lambda_init;
    LocalRefiner lm(lm_cfg);
    return lm.refine_trf(chrom, data, rows, cols, output_col);
}

RefineResult LocalRefiner::refine(
    const Chromosome& chrom,
    const double* data, int rows, int cols, int output_col
) const {
    switch (cfg_.method) {
        case RefineMethod::LevenbergMarquardt:
            return refine_lm(chrom, data, rows, cols, output_col);
        default:
            return refine_trf(chrom, data, rows, cols, output_col);
    }
}

} // namespace aegis
