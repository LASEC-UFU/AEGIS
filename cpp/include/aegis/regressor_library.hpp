#pragma once
#include <vector>
#include <cstdint>
#include <functional>
#include "safe_power.hpp"
#include "metrics.hpp"

namespace aegis {

/** A single factor in a regressor: variable_idx^exponent(k - delay). */
struct Term {
    int    variable       = 0;     // 0-based column index into data matrix
    int    delay          = 1;     // time delay ≥ 1
    double exponent       = 1.0;   // real exponent in [pmin, pmax]
    bool   is_denominator = false; // true → belongs to denominator of rational model

    uint32_t encoded() const noexcept {
        return ((is_denominator ? 1u : 0u) << 22) |
               ((static_cast<uint32_t>(variable) & 0x7FFu) << 11) |
               (static_cast<uint32_t>(delay) & 0x7FFu);
    }
};

/**
 * A regressor is a product of Terms (each raised to its own exponent):
 *   value(k) = ∏ power_basis(x_i(k-d_i), p_i, mode)
 * See PowerMode in safe_power.hpp for the basis definition.
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

    /** Structure-only hash (variables, delays, numerator/denominator). */
    uint32_t structural_hash() const noexcept {
        uint32_t h = 0;
        for (const auto& t : terms) h = h * 31u + t.encoded();
        return h;
    }

    /** Full hash including exponents (used for duplicate detection/caching). */
    uint64_t full_hash() const noexcept;

    /** Evaluate this regressor at sample k (row-major data, rows × cols). */
    double evaluate(const double* data, int k, int rows, int cols,
                    PowerMode mode) const noexcept;
};

/** A model chromosome: ordered list of Regressors + optional coefficient array. */
struct Chromosome {
    std::vector<Regressor> regressors;
    std::vector<double>    coefficients; // empty → not yet fitted
    double                 intercept  = 0.0; // constant (bias) term, fitted alongside coefficients
    std::vector<double>    err;          // ERR per regressor (empty → not computed)
    double                 fitness    = std::numeric_limits<double>::infinity();
    double                 sse        = std::numeric_limits<double>::infinity();
    bool                   evaluated  = false;
    PowerMode              power_mode = PowerMode::Hybrid; // basis semantics of this model
    ModelMetrics           metrics;      // RMSE/R²/BIC/AIC, populated on evaluate()
    FitnessBreakdown       fitness_breakdown; // decomposed fitness terms, populated on evaluate()
    StabilityDiagnostics   stability;    // populated on evaluate()

    // ── Cross-context robustness tracking (specialized islands / migration) ──
    int    contexts_survived  = 0; // number of reevaluations under foreign weights/regimes
    double worst_fitness_seen = std::numeric_limits<double>::quiet_NaN();

    int  num_regressors() const noexcept { return static_cast<int>(regressors.size()); }
    int  num_terms()      const noexcept;
    bool is_rational()    const noexcept;
    int  max_delay()      const noexcept;
    double max_exponent() const noexcept;
    uint32_t structural_hash() const noexcept;
    uint64_t full_hash() const noexcept;

    /**
     * Canonical form: within a regressor, repeated (variable, delay) factors
     * are removed (first occurrence kept) and every factor takes the
     * regressor's numerator/denominator flag; duplicated regressors (same
     * full hash) are removed. Clears fitted state when anything changes.
     * Returns true if the chromosome was modified.
     */
    bool canonicalize();

    /** Drop all fitted/evaluated state (structure kept). */
    void invalidate();
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
 * Columns that are numerically dependent on the previously accepted columns
 * receive x_j = 0 and do not consume a row of R, so the remaining
 * coefficients are the least-squares solution on the reduced column set.
 * Returns false only for invalid dimensions or an all-zero matrix.
 * If rank_out is given, it receives the number of accepted columns.
 */
bool qr_solve(
    const double* A, int m, int n,
    const double* b,
    double*       x,
    int*          rank_out = nullptr
);

} // namespace aegis
