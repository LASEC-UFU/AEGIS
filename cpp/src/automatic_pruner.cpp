#include "aegis/automatic_pruner.hpp"
#include <algorithm>
#include <numeric>
#include <cmath>

namespace aegis {

PruneResult AutomaticPruner::prune(
    const Chromosome& chrom,
    const IndividualEvaluator& evaluator,
    const double* train_data, int train_rows,
    const double* val_data, int val_rows,
    int cols, int output_col
) const {
    PruneResult res;
    Chromosome current = chrom;
    evaluator.evaluate(current, train_data, train_rows, val_data, val_rows, cols, output_col);
    ++res.evaluations;
    res.pruned_chromosome = current;
    res.fitness_before = current.fitness;
    res.fitness_after = current.fitness;
    if (!current.evaluated || current.num_regressors() <= 1) return res;

    // Track original indices of the surviving regressors.
    std::vector<int> orig(current.num_regressors());
    std::iota(orig.begin(), orig.end(), 0);

    int removals = 0;
    bool changed = true;
    while (changed && removals < cfg_.max_removals && current.num_regressors() > 1) {
        changed = false;
        // Order candidates by ERR (lowest first).
        std::vector<int> order(current.num_regressors());
        std::iota(order.begin(), order.end(), 0);
        std::sort(order.begin(), order.end(), [&](int a, int b) {
            const double ea = a < static_cast<int>(current.err.size()) ? current.err[a] : 0.0;
            const double eb = b < static_cast<int>(current.err.size()) ? current.err[b] : 0.0;
            return ea < eb;
        });
        for (int j : order) {
            Chromosome trial = current;
            trial.regressors.erase(trial.regressors.begin() + j);
            trial.invalidate();
            evaluator.evaluate(trial, train_data, train_rows, val_data, val_rows, cols, output_col);
            ++res.evaluations;
            if (!trial.evaluated) continue;
            const double tol = cfg_.fitness_tol * std::abs(current.fitness);
            if (trial.fitness <= current.fitness + tol) {
                res.removed_indices.push_back(orig[j]);
                orig.erase(orig.begin() + j);
                current = std::move(trial);
                ++removals;
                changed = true;
                break; // re-rank with the new ERR values
            }
        }
    }
    res.pruned_chromosome = current;
    res.fitness_after = current.fitness;
    res.improved = current.fitness < res.fitness_before;
    return res;
}

} // namespace aegis
