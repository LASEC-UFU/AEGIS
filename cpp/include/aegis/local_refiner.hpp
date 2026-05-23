#pragma once
#include "regressor_library.hpp"
#include <functional>
#include <string>
#include <vector>

namespace aegis {

enum class RefineMethod { TrustRegionReflective, LevenbergMarquardt };

struct RefineConfig {
    RefineMethod method;
    int          max_iter;
    double       ftol;          // function tolerance
    double       xtol;          // parameter tolerance
    double       gtol;          // gradient tolerance
    double       initial_delta; // TRF trust region initial radius
    double       lambda_init;   // LM initial damping

    // Explicit constructor avoids Clang CWG-1861 when used as default arg.
    RefineConfig()
        : method(RefineMethod::TrustRegionReflective), max_iter(200),
          ftol(1e-8), xtol(1e-8), gtol(1e-8),
          initial_delta(1.0), lambda_init(1e-3) {}
};

struct RefineResult {
    std::vector<double> coefficients;
    double              final_sse     = 0.0;
    double              initial_sse   = 0.0;
    int                 iterations    = 0;
    bool                converged     = false;
    std::string         message;
};

/**
 * Local coefficient refiner applied after DE finds a good structure.
 *
 * Refinement is only over the linear coefficients (θ), not the model structure.
 * The non-linear part (exponents, delays, variable indices) is fixed.
 *
 * For rational models the residual function is:
 *   r(k,θ) = y(k) - [N(k,θ_N) / D(k,θ_D)]
 * which is non-linear in θ — exactly what TRF/LM solve.
 *
 * For polynomial models linear QR already gives the exact solution,
 * so the refiner is a no-op (returns the QR solution as-is).
 */
class LocalRefiner {
public:
    explicit LocalRefiner(const RefineConfig& cfg = RefineConfig()) : cfg_(cfg) {}

    RefineResult refine(
        const Chromosome& chrom,          // structure (fixed during refinement)
        const double*     data,           // training data, row-major rows × cols
        int               rows,
        int               cols,
        int               output_col
    ) const;

private:
    RefineConfig cfg_;

    RefineResult refine_trf(
        const Chromosome& chrom,
        const double* data, int rows, int cols, int output_col
    ) const;

    RefineResult refine_lm(
        const Chromosome& chrom,
        const double* data, int rows, int cols, int output_col
    ) const;

    /** Numerical Jacobian via forward differences. */
    void compute_jacobian(
        const std::vector<double>& theta,
        const Chromosome&          chrom,
        const double*              data, int rows, int cols, int output_col,
        std::vector<double>&       J,   // (usable_rows) × n_params, row-major
        std::vector<double>&       r    // residual vector
    ) const;
};

} // namespace aegis
