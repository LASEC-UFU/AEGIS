#pragma once
#include <vector>
#include <cstdint>
#include <functional>
#include "safe_power.hpp"

namespace aegis {

/** A single factor in a regressor: variable_idx^exponent(k - delay). */
struct Term {
    int    variable;      // 0-based column index into data matrix
    int    delay;         // time delay ≥ 1
    double exponent;      // real exponent in [pmin, pmax]
    bool   is_denominator;// true → belongs to denominator of rational model

    uint32_t encoded() const noexcept {
        return ((is_denominator ? 1u : 0u) << 22) |
               ((static_cast<uint32_t>(variable) & 0x7FFu) << 11) |
               (static_cast<uint32_t>(delay) & 0x7FFu);
    }
};

/**
 * A regressor is a product of Terms (each raised to its own exponent).
 *   value(k) = ∏ sign(x_i(k-d_i)) * (|x_i(k-d_i)| + ε)^{p_i}
 */
struct Regressor {
    std::vector<Term> terms;

    bool is_denominator() const noexcept {
        for (const auto& t : terms) if (t.is_denominator) return true;
        return false;
    }

    int max_delay() const noexcept {
        int md = 0;
        for (const auto& t : terms) md = std::max(md, t.delay);
        return md;
    }

    double max_exponent() const noexcept {
        double me = 0.0;
        for (const auto& t : terms) me = std::max(me, t.exponent);
        return me;
    }

    uint32_t structural_hash() const noexcept {
        uint32_t h = 0;
        for (const auto& t : terms) h = h * 31u + t.encoded();
        return h;
    }

    /**
     * Evaluate this regressor at sample k given the full data matrix.
     *   data    : row-major, rows × cols
     *   k       : current sample index (0-based)
     *   rows    : total rows in data
     *   use_signed_power : if true use signed_power (default false → safe_power)
     */
    double evaluate(const double* data, int k, int rows, int cols,
                    bool use_signed_power = true) const noexcept;
};

/** A model chromosome: ordered list of Regressors + optional coefficient array. */
struct Chromosome {
    std::vector<Regressor> regressors;
    std::vector<double>    coefficients; // empty → not yet fitted
    std::vector<double>    err;          // ERR per regressor (empty → not computed)
    double                 fitness    = std::numeric_limits<double>::infinity();
    double                 sse        = std::numeric_limits<double>::infinity();
    bool                   evaluated  = false;

    int  num_regressors() const noexcept { return static_cast<int>(regressors.size()); }
    bool is_rational()    const noexcept;
    int  max_delay()      const noexcept;
    double max_exponent() const noexcept;
    uint32_t structural_hash() const noexcept;
};

/**
 * Build the regressor (Ψ) matrix for one chromosome.
 *
 * Output layout: row-major, (rows - max_delay) × num_regressors.
 * Denominator columns are NOT pseudo-linearized here; that is done by the
 * evaluator if needed.
 *
 * Returns false if the chromosome has no valid regressors or data is too short.
 */
bool build_psi_matrix(
    const Chromosome&  chrom,
    const double*      data,   // row-major, rows × cols
    int                rows,
    int                cols,
    std::vector<double>& psi,  // output: (usable_rows) × num_regressors, row-major
    int&               usable_rows
);

/**
 * Apply pseudo-linearization for rational models.
 * Denominator columns ψ_j(k) → −y(k) * ψ_j(k).
 * Modifies psi in-place.
 */
void pseudo_linearize(
    const Chromosome&  chrom,
    const double*      y_col,  // output column, length usable_rows
    double*            psi,    // row-major, usable_rows × num_regressors
    int                usable_rows,
    int                num_regressors
);

/**
 * Householder QR least-squares solver: min ||A·x - b||₂
 *   A : m × n  (row-major)
 *   b : m × 1
 *   x : n × 1  (output)
 * Returns false if system is degenerate (rank deficient).
 */
bool qr_solve(
    const double* A, int m, int n,
    const double* b,
    double*       x
);

} // namespace aegis
