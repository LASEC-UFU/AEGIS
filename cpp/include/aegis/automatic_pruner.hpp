#pragma once
#include "regressor_library.hpp"
#include "individual_evaluator.hpp"
#include <vector>
#include <string>

namespace aegis {

struct PruneResult {
    Chromosome pruned_chromosome;
    std::vector<int> removed_indices;  // indices (in the original chromosome) removed
    double fitness_before = std::numeric_limits<double>::infinity();
    double fitness_after  = std::numeric_limits<double>::infinity();
    bool   improved = false;
    int    evaluations = 0;
};

/**
 * Backward-elimination pruner (post-processing).
 *
 * Regressors are tried for removal in increasing order of ERR. A removal is
 * accepted only if the model, re-fitted on the training split and scored by
 * the supplied (canonical) evaluator on the validation split, has a fitness
 * no worse than the current one (fitness_tol is a relative tolerance on
 * |fitness|; the default 0 means "never worse"). The test split is never used.
 */
class AutomaticPruner {
public:
    struct Config {
        double fitness_tol;      // relative tolerance on |fitness| (0 = strictly not worse)
        int    max_removals;     // max regressors removed in one pass

        Config() : fitness_tol(0.0), max_removals(10) {}
    };

    explicit AutomaticPruner(const Config& cfg = Config()) : cfg_(cfg) {}

    PruneResult prune(
        const Chromosome& chrom,
        const IndividualEvaluator& evaluator,
        const double* train_data, int train_rows,
        const double* val_data, int val_rows,
        int cols, int output_col
    ) const;

private:
    Config cfg_;
};

} // namespace aegis
