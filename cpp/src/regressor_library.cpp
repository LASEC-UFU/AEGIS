#include "aegis/regressor_library.hpp"
#include "aegis/safe_power.hpp"
#include <cmath>
#include <cstring>
#include <vector>
#include <stdexcept>
#include <algorithm>
#include <unordered_set>

namespace aegis {

// ── hashing helpers ───────────────────────────────────────────────────────

static inline uint64_t mix64(uint64_t h, uint64_t v) noexcept {
    // splitmix-style combine
    h ^= v + 0x9E3779B97F4A7C15ULL + (h << 6) + (h >> 2);
    h *= 0xBF58476D1CE4E5B9ULL;
    return h ^ (h >> 31);
}

static inline uint64_t exponent_key(double p) noexcept {
    // Round to 1e-9 so that numerically identical exponents hash equally.
    return static_cast<uint64_t>(std::llround(p * 1e9));
}

uint64_t Regressor::full_hash() const noexcept {
    uint64_t h = 0x12345678ULL;
    for (const auto& t : terms) {
        h = mix64(h, t.encoded());
        h = mix64(h, exponent_key(t.exponent));
    }
    return h;
}

// ── Regressor::evaluate ───────────────────────────────────────────────────

double Regressor::evaluate(const double* data, int k, int rows, int cols,
                           PowerMode mode) const noexcept {
    (void)rows;
    double val = 1.0;
    for (const auto& t : terms) {
        const int ki = k - t.delay;
        if (ki < 0) return 0.0; // guard (max_delay check should prevent this)
        val *= power_basis(data[static_cast<size_t>(ki) * cols + t.variable], t.exponent, mode);
    }
    return val;
}

// ── Chromosome helpers ────────────────────────────────────────────────────

int Chromosome::num_terms() const noexcept {
    int n = 0;
    for (const auto& r : regressors) n += static_cast<int>(r.terms.size());
    return n;
}

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

uint64_t Chromosome::full_hash() const noexcept {
    uint64_t h = 0xABCDEF01ULL ^ static_cast<uint64_t>(power_mode);
    for (const auto& r : regressors) h = mix64(h, r.full_hash());
    return h;
}

void Chromosome::invalidate() {
    coefficients.clear();
    err.clear();
    intercept = 0.0;
    evaluated = false;
    fitness = std::numeric_limits<double>::infinity();
    sse = std::numeric_limits<double>::infinity();
    metrics = ModelMetrics();
    fitness_breakdown = FitnessBreakdown();
    stability = StabilityDiagnostics();
}

bool Chromosome::canonicalize() {
    bool changed = false;
    std::vector<Regressor> out;
    out.reserve(regressors.size());
    std::unordered_set<uint64_t> seen_regs;
    for (auto reg : regressors) {
        if (reg.terms.empty()) { changed = true; continue; }
        const bool denom = reg.is_denominator();
        std::vector<Term> terms;
        terms.reserve(reg.terms.size());
        for (auto t : reg.terms) {
            if (t.is_denominator != denom) { t.is_denominator = denom; changed = true; }
            bool dup = false;
            for (const auto& u : terms)
                if (u.variable == t.variable && u.delay == t.delay) { dup = true; break; }
            if (dup) { changed = true; continue; }
            terms.push_back(t);
        }
        reg.terms = std::move(terms);
        const uint64_t h = reg.full_hash();
        if (!seen_regs.insert(h).second) { changed = true; continue; }
        out.push_back(std::move(reg));
    }
    if (changed) {
        regressors = std::move(out);
        invalidate();
    }
    return changed;
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

    psi.assign(static_cast<size_t>(usable_rows) * nr, 1.0);

    // Column-wise construction: one pass per factor, so integer exponents
    // and the identity exponent avoid std::pow entirely.
    for (int j = 0; j < nr; ++j) {
        const auto& reg = chrom.regressors[j];
        for (const auto& t : reg.terms) {
            const int off = md - t.delay; // row offset of x(k - delay) for k = i + md
            if (off < 0) return false;
            const double* col = data + t.variable;
            const double p = t.exponent;
            int n_int = 0;
            const bool is_int = is_integer_exponent(p, &n_int);
            for (int i = 0; i < usable_rows; ++i) {
                const double x = col[static_cast<size_t>(i + off) * cols];
                double v;
                if (chrom.power_mode != PowerMode::Legacy && p == 1.0) v = x;
                else if (chrom.power_mode == PowerMode::Hybrid && is_int) v = int_power(x, n_int);
                else v = power_basis(x, p, chrom.power_mode);
                psi[static_cast<size_t>(i) * nr + j] *= v;
            }
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

bool qr_solve(const double* A, int m, int n, const double* b, double* x, int* rank_out) {
    if (m <= 0 || n <= 0) return false;
    for (int j = 0; j < n; ++j) x[j] = 0.0;

    double matrix_scale = 0.0;
    for (size_t i = 0; i < static_cast<size_t>(m) * n; ++i)
        matrix_scale = std::max(matrix_scale, std::abs(A[i]));
    if (!(matrix_scale > 1e-300) || !std::isfinite(matrix_scale)) return false;
    const double rank_tol = std::numeric_limits<double>::epsilon()
        * static_cast<double>(std::max(m, n)) * matrix_scale * 10.0;

    std::vector<double> R(A, A + static_cast<size_t>(m) * n);
    std::vector<double> Qb(b, b + m);
    std::vector<int> accepted;       // accepted column indices, in row order
    accepted.reserve(n);
    std::vector<double> v(m);

    int row = 0; // next free row of R
    for (int j = 0; j < n && row < m; ++j) {
        double norm2 = 0.0;
        for (int i = row; i < m; ++i) {
            const double a = R[static_cast<size_t>(i) * n + j];
            norm2 += a * a;
        }
        const double norm = std::sqrt(norm2);
        if (norm < rank_tol) continue; // dependent column: θ_j = 0, no row consumed

        const double rjj = R[static_cast<size_t>(row) * n + j];
        const double alpha = -std::copysign(norm, rjj);
        const int len = m - row;
        for (int i = 0; i < len; ++i) v[i] = R[static_cast<size_t>(row + i) * n + j];
        v[0] -= alpha;
        double vnorm2 = 0.0;
        for (int i = 0; i < len; ++i) vnorm2 += v[i] * v[i];
        if (vnorm2 < 1e-300) {
            // Column already in triangular form at this row.
            accepted.push_back(j);
            ++row;
            continue;
        }
        const double beta = 2.0 / vnorm2;
        for (int k = j; k < n; ++k) {
            double dot = 0.0;
            for (int i = 0; i < len; ++i) dot += v[i] * R[static_cast<size_t>(row + i) * n + k];
            dot *= beta;
            for (int i = 0; i < len; ++i) R[static_cast<size_t>(row + i) * n + k] -= dot * v[i];
        }
        double dot = 0.0;
        for (int i = 0; i < len; ++i) dot += v[i] * Qb[row + i];
        dot *= beta;
        for (int i = 0; i < len; ++i) Qb[row + i] -= dot * v[i];

        accepted.push_back(j);
        ++row;
    }

    // Back-substitution on the accepted columns (row r ↔ accepted[r]).
    const int rank = static_cast<int>(accepted.size());
    for (int r = rank - 1; r >= 0; --r) {
        const int j = accepted[r];
        double s = Qb[r];
        for (int q = r + 1; q < rank; ++q)
            s -= R[static_cast<size_t>(r) * n + accepted[q]] * x[accepted[q]];
        const double diag = R[static_cast<size_t>(r) * n + j];
        x[j] = (std::abs(diag) > 1e-300) ? s / diag : 0.0;
    }
    if (rank_out) *rank_out = rank;
    return rank > 0;
}

} // namespace aegis
