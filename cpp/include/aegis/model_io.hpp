#pragma once
#include "regressor_library.hpp"
#include "normalizer.hpp"
#include "json_lite.hpp"
#include <string>

namespace aegis {

/** Serialize the structure + coefficients of a chromosome (no metrics). */
std::string chromosome_structure_json(const Chromosome& c);

/**
 * Parse a model from JSON. Accepts the AEGIS model format
 * ({"regressors":[{"terms":[{variable,delay,exponent,isDenominator}]}],
 *   "coefficients":[…], "intercept":…, "powerMode":"hybrid"}).
 * Coefficients are optional (a structure-only model is re-fitted by callers).
 * Missing powerMode → `default_mode`.
 */
bool chromosome_from_json(const json::Value& v, Chromosome& out,
                          PowerMode default_mode, std::string* error = nullptr);

/** Metrics of one data segment (one-step and free-run). */
struct SegmentMetrics {
    std::string name;
    int    seg_start = 0, seg_end = 0, score_start = 0, n = 0;
    // normalized units
    double rmse_one_step = std::numeric_limits<double>::quiet_NaN();
    double r2_one_step   = std::numeric_limits<double>::quiet_NaN();
    double fit_one_step  = std::numeric_limits<double>::quiet_NaN(); // 100(1-‖e‖/‖y-ȳ‖)
    double rmse_free_run = std::numeric_limits<double>::quiet_NaN();
    double r2_free_run   = std::numeric_limits<double>::quiet_NaN();
    double fit_free_run  = std::numeric_limits<double>::quiet_NaN();
    // original units of the output column
    double rmse_one_step_orig = std::numeric_limits<double>::quiet_NaN();
    double rmse_free_run_orig = std::numeric_limits<double>::quiet_NaN();
    double mae_free_run_orig  = std::numeric_limits<double>::quiet_NaN();
    double max_abs_err_free_run_orig = std::numeric_limits<double>::quiet_NaN();
    bool   free_run_diverged = false;
    int    divergence_row    = -1;
    double min_abs_denominator = std::numeric_limits<double>::quiet_NaN();
    int    denominator_sign_changes = 0;

    std::string to_json() const;
};

/**
 * Evaluate a fitted model on rows [seg_start, seg_end) of a normalized data
 * matrix. The first max_delay rows of the segment (starting at seg_start)
 * provide measured initial conditions; errors are scored on rows
 * [score_start, seg_end). For a fair comparison all models must use the same
 * score_start (≥ seg_start + max_delay of every model).
 * `bound` is the free-run divergence envelope in normalized units.
 */
SegmentMetrics evaluate_segment(const Chromosome& c, const double* norm_data,
                                int rows, int cols, int output_col,
                                int seg_start, int seg_end, int score_start,
                                double bound, const Normalizer* norm,
                                const std::string& name);

/** FNV-1a 64-bit hash of a double array (bitwise), as 16 hex digits. */
std::string hash_doubles(const double* data, size_t n);

/** Build information (compiler, flags, version) as JSON object string. */
std::string build_info_json();

} // namespace aegis
