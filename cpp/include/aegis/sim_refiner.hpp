#pragma once
// sim_refiner.hpp — admissibility veto (M9) and final refinement of the
// champion's coefficients by free-run simulation error (P6).
//
// Validated as the P6 tool (experiments/p6/P6_PREREG.md, P6_REPORT.md):
// Levenberg–Marquardt on the training free-run SSE with exact forward
// sensitivities for numerator and denominator coefficients; every accepted
// iterate passes the admissibility veto; the iterate with the lowest free-run
// RMSE on the first half of the validation split (V_A) is kept (iterate 0,
// the original coefficients, is always a candidate). Structure, delays and
// exponents are fixed. Hybrid power basis only.
#include "regressor_library.hpp"
#include <string>
#include <vector>

namespace aegis {

/** Free-run admissibility: the simulation over each block (first max_delay
 *  rows measured) does not diverge (|ŷ| ≤ bound, finite) and, for rational
 *  models, |D(k)| never falls below kMinDenominator. Null blocks are skipped. */
bool free_run_admissible(const Chromosome& c, const double* train, int train_rows,
                         const double* val, int val_rows, int cols, int out, double bound);

struct SimRefineResult {
    bool        ran = false;
    std::string status;            // LM status or reason it did not run
    int         iterations = 0, accepted = 0, admissible_iterates = 0, chosen_iterate = 0;
    double      tau = 0.0;         // denominator floor used by the veto
    double      train0 = 0, train = 0, va0 = 0, va = 0, vb0 = 0, vb = 0; // free-run RMSE, normalized
    double      seconds = 0.0;
    double      intercept = 0.0;
    std::vector<double> coefficients; // chosen iterate
};

/**
 * @param data      normalized data, row-major, all rows
 * @param train_end first validation row; the training block is [0, train_end)
 * @param val_end   end of validation (exclusive)
 * @param ctx       context rows before train_end used to start the validation
 *                  simulation (the pipeline's maxDelay); scoring starts at ctx
 * @param bound     divergence bound (kDivergenceFactor·max|y_train|)
 */
SimRefineResult refine_by_simulation(const Chromosome& c, const double* data, int cols, int out,
                                     int train_end, int val_end, int ctx, double bound);

} // namespace aegis
