#pragma once
#include "regressor_library.hpp"
#include <vector>

namespace aegis {

struct PruneResult {
    Chromosome pruned_chromosome;
    std::vector<int> removed_indices;  // original regressor indices removed
    double fitness_before;
    double fitness_after;
    bool   improved;
};

/**
 * Automatic pruner: removes low-contribution regressors using
 * ERR threshold, coefficient magnitude, and VIF collinearity.
 *
 * Pipeline:
 *   1. Compute ERR for each regressor
 *   2. Compute VIF collinearity
 *   3. Mark candidates: ERR < err_threshold OR |coeff| < coeff_threshold OR VIF > vif_max
 *   4. Remove least-contributing candidates one at a time
 *   5. Refit and validate; accept removal if fitness does not worsen beyond tolerance
 */
class AutomaticPruner {
public:
    struct Config {
        double err_threshold   = 0.01;  // regressors below this ERR are candidates
        double coeff_threshold = 1e-4;  // |coeff| below this → candidate
        double vif_max         = 10.0;  // VIF above this → collinear candidate
        double fitness_tol     = 0.05;  // allow up to 5% fitness worsening
        int    max_removals    = 5;     // max regressors to remove in one pass
    };

    explicit AutomaticPruner(const Config& cfg = Config()) : cfg_(cfg) {}

    /**
     * Prune a chromosome.
     *   chrom      : fitted chromosome with coefficients and ERR values
     *   data       : training data (row-major, rows × cols)
     *   output_col : output column index
     */
    PruneResult prune(
        const Chromosome& chrom,
        const double* data, int rows, int cols, int output_col
    ) const;

private:
    Config cfg_;
};

} // namespace aegis
