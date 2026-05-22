#include "aegis/regressor_library.hpp"
#include "aegis/safe_power.hpp"
#include <cmath>
#include <cstring>
#include <vector>
#include <stdexcept>
#include <algorithm>

namespace aegis {

// ── Term::evaluate (unused; Regressor::evaluate is used) ─────────────────

double Regressor::evaluate(const double* data, int k, int rows, int cols,
                            bool use_signed_power) const noexcept {
    double val = 1.0;
    for (const auto& t : terms) {
        int ki = k - t.delay;
        if (ki < 0) return 0.0; // guard (max_delay check should prevent this)
        double x = data[ki * cols + t.variable];
        val *= use_signed_power
            ? signed_power(x, t.exponent)
            : safe_power(x, t.exponent);
    }
    return val;
}

// ── Chromosome helpers ────────────────────────────────────────────────────

bool Chromosome::is_rational() const noexcept {
    for (const auto& r : regressors)
        if (r.is_denominator()) return true;
    return false;
}

int Chromosome::max_delay() const noexcept {
    int md = 0;
    for (const auto& r : regressors) md = std::max(md, r.max_delay());
    return md;
}

double Chromosome::max_exponent() const noexcept {
    double me = 0.0;
    for (const auto& r : regressors) me = std::max(me, r.max_exponent());
    return me;
}

uint32_t Chromosome::structural_hash() const noexcept {
    uint32_t h = 0;
    for (const auto& r : regressors) h = h * 37u + r.structural_hash();
    return h;
}

// ── build_psi_matrix ─────────────────────────────────────────────────────

bool build_psi_matrix(
    const Chromosome&    chrom,
    const double*        data,
    int                  rows,
    int                  cols,
    std::vector<double>& psi,
    int&                 usable_rows
) {
    const int md  = chrom.max_delay();
    const int nr  = chrom.num_regressors();
    usable_rows   = rows - md;

    if (usable_rows <= 0 || nr == 0) return false;

    psi.assign(static_cast<size_t>(usable_rows) * nr, 0.0);

    for (int j = 0; j < nr; ++j) {
        const auto& reg = chrom.regressors[j];
        for (int i = 0; i < usable_rows; ++i) {
            int k = i + md; // actual sample index (0-based)
            psi[static_cast<size_t>(i) * nr + j] =
                reg.evaluate(data, k, rows, cols, /*signed=*/true);
        }
    }
    return true;
}

// ── pseudo_linearize ─────────────────────────────────────────────────────

void pseudo_linearize(
    const Chromosome& chrom,
    const double*     y_col,
    double*           psi,
    int               usable_rows,
    int               num_regressors
) {
    for (int j = 0; j < num_regressors && j < chrom.num_regressors(); ++j) {
        if (!chrom.regressors[j].is_denominator()) continue;
        for (int i = 0; i < usable_rows; ++i) {
            psi[static_cast<size_t>(i) * num_regressors + j] *= -y_col[i];
        }
    }
}

// ── Householder QR least-squares solver ──────────────────────────────────

bool qr_solve(const double* A, int m, int n, const double* b, double* x) {
    if (m < n || n <= 0) return false;

    // Work copies
    std::vector<double> R(A, A + static_cast<size_t>(m) * n);
    std::vector<double> Qb(b, b + m);

    // Householder QR factorisation (in-place on R)
    for (int j = 0; j < n; ++j) {
        // Build Householder vector for column j below diagonal
        double norm = 0.0;
        for (int i = j; i < m; ++i)
            norm += R[static_cast<size_t>(i) * n + j] * R[static_cast<size_t>(i) * n + j];
        norm = std::sqrt(norm);
        if (norm < 1e-30) return false; // rank deficient

        double alpha = -std::copysign(norm, R[static_cast<size_t>(j) * n + j]);
        std::vector<double> v(m - j, 0.0);
        for (int i = 0; i < m - j; ++i)
            v[i] = R[static_cast<size_t>(j + i) * n + j];
        v[0] -= alpha;

        double vNorm2 = 0.0;
        for (double vi : v) vNorm2 += vi * vi;
        if (vNorm2 < 1e-30) continue;

        double beta = 2.0 / vNorm2;

        // Apply H = I - beta * v * v^T to columns [j..n-1] of R
        for (int k = j; k < n; ++k) {
            double dot = 0.0;
            for (int i = 0; i < m - j; ++i)
                dot += v[i] * R[static_cast<size_t>(j + i) * n + k];
            dot *= beta;
            for (int i = 0; i < m - j; ++i)
                R[static_cast<size_t>(j + i) * n + k] -= dot * v[i];
        }

        // Apply H to Qb
        {
            double dot = 0.0;
            for (int i = 0; i < m - j; ++i) dot += v[i] * Qb[j + i];
            dot *= beta;
            for (int i = 0; i < m - j; ++i) Qb[j + i] -= dot * v[i];
        }
    }

    // Back-substitution: R·x = Qb[0..n-1]
    for (int i = n - 1; i >= 0; --i) {
        double s = Qb[i];
        for (int k = i + 1; k < n; ++k)
            s -= R[static_cast<size_t>(i) * n + k] * x[k];
        double diag = R[static_cast<size_t>(i) * n + i];
        if (std::abs(diag) < 1e-30) return false;
        x[i] = s / diag;
    }

    return true;
}

} // namespace aegis
