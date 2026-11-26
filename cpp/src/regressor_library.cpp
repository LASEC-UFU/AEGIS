#include "aegis/regressor_library.hpp"
#include "aegis/safe_power.hpp"
#include <cmath>
#include <cstring>
#include <vector>
#include <stdexcept>
#include <algorithm>
#include <unordered_set>

namespace aegis {

// ── factor-series cache (P1) ─────────────────────────────────────────────
//
// A factor column of Ψ is g_p(x_v(k − d)): the same series g_p(x_v) shifted.
// Each thread keeps, per data block (pointer, rows, cols, content
// fingerprint), the series g_p(x_v(r)) for r = 0..rows−1, computed with
// exactly the expression build_psi_matrix used before. The fingerprint is
// recomputed on every call, so a reused pointer with different content can
// never serve stale values.
namespace detail {

struct SeriesBlock {
    const double* data = nullptr;
    int rows = 0, cols = 0;
    uint64_t fp = 0, last_use = 0, call = 0;
    struct Entry { int var; uint64_t pbits; int mode; std::vector<double> v; uint64_t used; };
    std::vector<Entry> entries;
    static constexpr size_t kMaxEntries = 96;

    const double* series(int var, double p, PowerMode mode) {
        uint64_t pbits;
        std::memcpy(&pbits, &p, sizeof pbits);
        const int m = static_cast<int>(mode);
        for (auto& e : entries)
            if (e.var == var && e.pbits == pbits && e.mode == m) { e.used = call; return e.v.data(); }
        if (entries.size() >= kMaxEntries) {
            // Evict least recently used entries not needed by the current call.
            std::vector<size_t> idx;
            for (size_t i = 0; i < entries.size(); ++i) if (entries[i].used < call) idx.push_back(i);
            std::sort(idx.begin(), idx.end(), [&](size_t a, size_t b) { return entries[a].used < entries[b].used; });
            const size_t drop = std::min(idx.size(), entries.size() - kMaxEntries / 2);
            std::vector<char> kill(entries.size(), 0);
            for (size_t i = 0; i < drop; ++i) kill[idx[i]] = 1;
            size_t w = 0;
            for (size_t i = 0; i < entries.size(); ++i)
                if (!kill[i]) { if (w != i) entries[w] = std::move(entries[i]); ++w; }
            entries.resize(w);
        }
        Entry e{var, pbits, m, std::vector<double>(static_cast<size_t>(rows)), call};
        int n_int = 0;
        const bool is_int = is_integer_exponent(p, &n_int);
        const double* col = data + var;
        for (int r = 0; r < rows; ++r) {
            const double x = col[static_cast<size_t>(r) * cols];
            double v;
            if (mode != PowerMode::Legacy && p == 1.0) v = x;
            else if (mode == PowerMode::Hybrid && is_int) v = int_power(x, n_int);
            else v = power_basis(x, p, mode);
            e.v[r] = v;
        }
        entries.push_back(std::move(e));
        return entries.back().v.data();
    }
};

static uint64_t block_fingerprint(const double* data, size_t n) noexcept {
    uint64_t h = 1469598103934665603ULL ^ n;
    for (size_t i = 0; i < n; ++i) {
        uint64_t w;
        std::memcpy(&w, data + i, sizeof w);
        h = (h ^ w) * 1099511628211ULL;
        h ^= h >> 29;
    }
    return h;
}

SeriesBlock& series_block(const double* data, int rows, int cols) {
    thread_local std::vector<SeriesBlock> blocks;
    thread_local uint64_t clock = 0;
    ++clock;
    const uint64_t fp = block_fingerprint(data, static_cast<size_t>(rows) * cols);
    for (auto& b : blocks) {
        if (b.data == data && b.rows == rows && b.cols == cols) {
            if (b.fp != fp) { b.entries.clear(); b.fp = fp; }
            b.last_use = clock;
            ++b.call;
            return b;
        }
    }
    if (blocks.size() >= 4) {
        auto it = std::min_element(blocks.begin(), blocks.end(),
            [](const SeriesBlock& a, const SeriesBlock& b) { return a.last_use < b.last_use; });
        blocks.erase(it);
    }
    blocks.emplace_back();
    SeriesBlock& b = blocks.back();
    b.data = data; b.rows = rows; b.cols = cols; b.fp = fp; b.last_use = clock; b.call = 1;
    return b;
}

} // namespace detail

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

    // P1 (docs/architecture/13_P0_PROFILING.md): every factor value comes from
    // a cached series g_p(x_v(r)) over all rows r of this data block, computed
    // by the same expression as before; Ψ is then filled row by row with the
    // factors multiplied in the same order (1.0·v1·v2…). Bit-identical to the
    // former column-wise construction, without recomputing powers per
    // candidate and without strided writes.
    struct Factor { const double* s; int off; };
    std::vector<Factor> fac;
    std::vector<int> first(nr + 1, 0);
    detail::SeriesBlock& blk = detail::series_block(data, rows, cols);
    for (int j = 0; j < nr; ++j) {
        first[j] = static_cast<int>(fac.size());
        for (const auto& t : chrom.regressors[j].terms) {
            const int off = md - t.delay; // row offset of x(k - delay) for k = i + md
            if (off < 0) return false;
            fac.push_back({nullptr, off});
        }
    }
    first[nr] = static_cast<int>(fac.size());
    {
        int f = 0;
        for (int j = 0; j < nr; ++j)
            for (const auto& t : chrom.regressors[j].terms)
                fac[f++].s = blk.series(t.variable, t.exponent, chrom.power_mode);
    }

    psi.resize(static_cast<size_t>(usable_rows) * nr);
    double* out = psi.data();
    for (int i = 0; i < usable_rows; ++i) {
        for (int j = 0; j < nr; ++j) {
            double val = 1.0;
            for (int f = first[j]; f < first[j + 1]; ++f) val *= fac[f].s[i + fac[f].off];
            *out++ = val;
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
    std::vector<double> dots(n);

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
        // P1: row-major sweep. For every column k the products are summed in
        // the same order (i ascending from 0.0) and each update is the same
        // expression, so the result is bit-identical to the former
        // column-by-column loop, with contiguous memory access.
        for (int k = j; k < n; ++k) dots[k] = 0.0;
        for (int i = 0; i < len; ++i) {
            const double vi = v[i];
            const double* Ri = R.data() + static_cast<size_t>(row + i) * n;
            for (int k = j; k < n; ++k) dots[k] += vi * Ri[k];
        }
        for (int k = j; k < n; ++k) dots[k] *= beta;
        for (int i = 0; i < len; ++i) {
            const double vi = v[i];
            double* Ri = R.data() + static_cast<size_t>(row + i) * n;
            for (int k = j; k < n; ++k) Ri[k] -= dots[k] * vi;
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
