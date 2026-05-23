#include "aegis/underfitting_detector.hpp"
#include <cmath>
#include <sstream>

namespace aegis {

UnderfittingResult UnderfittingDetector::detect(
    double rmse_train, double output_std, double r2_train
) const noexcept {
    UnderfittingResult r;
    r.r2 = r2_train;
    if (output_std > 1e-30)
        r.rmse_ratio = rmse_train / output_std;

    bool rmse_unfit = r.rmse_ratio > rmse_thr_;
    bool r2_unfit   = r2_train < r2_thr_;
    r.detected = rmse_unfit || r2_unfit;

    if (r.detected) {
        std::ostringstream ss;
        ss << "Underfitting detected:";
        if (rmse_unfit)
            ss << " RMSE/std=" << r.rmse_ratio;
        if (r2_unfit)
            ss << " R2=" << r2_train;
        ss << ". Consider increasing maxRegressors, maxDelay, or maxExponent.";
        r.suggestion = ss.str();
    }
    return r;
}

} // namespace aegis
