#include "aegis/overfitting_detector.hpp"
#include <cmath>
#include <sstream>

namespace aegis {

OverfittingResult OverfittingDetector::detect(
    double rmse_train, double rmse_val,
    int k_params, int n_train
) const noexcept {
    OverfittingResult r;
    if (rmse_train <= 0 || !std::isfinite(rmse_train)) return r;

    r.gap_ratio        = (rmse_val - rmse_train) / rmse_train;
    r.complexity_ratio = (n_train > 0) ? static_cast<double>(k_params) / n_train : 0.0;

    bool gap_ovfit = r.gap_ratio > gap_thr_;
    bool cmp_ovfit = r.complexity_ratio > complexity_thr_;
    r.detected = gap_ovfit || cmp_ovfit;

    if (r.detected) {
        std::ostringstream ss;
        ss << "Overfitting detected:";
        if (gap_ovfit)
            ss << " val/train RMSE gap=" << r.gap_ratio;
        if (cmp_ovfit)
            ss << " complexity ratio=" << r.complexity_ratio;
        ss << ". Consider reducing maxRegressors or increasing complexityPenalty.";
        r.suggestion = ss.str();
    }
    return r;
}

} // namespace aegis
