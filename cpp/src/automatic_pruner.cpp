#include "aegis/automatic_pruner.hpp"
#include "aegis/individual_evaluator.hpp"
#include "aegis/collinearity_analyzer.hpp"
#include <algorithm>
#include <numeric>

namespace aegis {

PruneResult AutomaticPruner::prune(
    const Chromosome& chrom,
    const double* data, int rows, int cols, int output_col
) const {
    PruneResult res;
    res.pruned_chromosome = chrom;
    res.fitness_before    = chrom.fitness;
    res.fitness_after     = chrom.fitness;
    res.improved          = false;

    if (chrom.num_regressors() <= 1) return res;

    IndividualEvaluator evaluator;

    // Compute ERR if not available
    std::vector<double> err = chrom.err.empty()
        ? evaluator.compute_err(chrom, data, rows, cols, output_col)
        : chrom.err;

    // Compute VIF
    std::vector<double> psi;
    int usable;
    build_psi_matrix(chrom, data, rows, cols, psi, usable);
    CollinearityAnalyzer ca(cfg_.vif_max);
    CollinearityResult col_res;
    if (usable > 0 && !psi.empty())
        col_res = ca.analyze(psi.data(), usable, chrom.num_regressors());

    // Identify removal candidates
    std::vector<int> candidates;
    int nr = chrom.num_regressors();
    for (int j = 0; j < nr; ++j) {
        bool low_err  = (j < (int)err.size() && err[j] < cfg_.err_threshold);
        bool low_coef = (!chrom.coefficients.empty() && j < (int)chrom.coefficients.size()
                         && std::abs(chrom.coefficients[j]) < cfg_.coeff_threshold);
        bool collinear= std::find(col_res.problematic_regressors.begin(),
                                  col_res.problematic_regressors.end(), j)
                        != col_res.problematic_regressors.end();
        if (low_err || low_coef || collinear) candidates.push_back(j);
    }

    if (candidates.empty()) return res;

    // Sort candidates by ERR (lowest first → remove worst first)
    std::sort(candidates.begin(), candidates.end(), [&](int a, int b) {
        double ea = (a < (int)err.size()) ? err[a] : 0.0;
        double eb = (b < (int)err.size()) ? err[b] : 0.0;
        return ea < eb;
    });

    Chromosome current = chrom;
    int removals = 0;

    for (int ci : candidates) {
        if (removals >= cfg_.max_removals) break;
        if (current.num_regressors() <= 1) break;

        // Build candidate without regressor ci
        Chromosome trial = current;
        trial.regressors.erase(trial.regressors.begin() + ci);
        trial.coefficients.clear();
        trial.err.clear();
        trial.evaluated = false;

        // Re-evaluate
        EvalResult er = evaluator.evaluate(trial, data, rows, nullptr, 0, cols, output_col);
        if (!er.valid) continue;

        double fitness_new = er.fitness;
        double tol = std::abs(current.fitness) * cfg_.fitness_tol;

        if (fitness_new <= current.fitness + tol) {
            res.removed_indices.push_back(ci);
            current = trial;
            ++removals;
        }
    }

    res.pruned_chromosome = current;
    res.fitness_after     = current.fitness;
    res.improved          = (current.fitness < chrom.fitness);
    return res;
}

} // namespace aegis
