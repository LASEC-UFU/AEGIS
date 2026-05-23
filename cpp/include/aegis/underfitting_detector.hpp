#pragma once
#include <string>

namespace aegis {

struct UnderfittingResult {
    bool   detected     = false;
    double rmse_ratio   = 0.0;  // rmse_train / output_std
    double r2           = 0.0;
    std::string suggestion;
};

class UnderfittingDetector {
public:
    /**
     * rmse_threshold : if rmse_train / output_std > this → underfit
     * r2_threshold   : if R² < this → underfit
     */
    explicit UnderfittingDetector(double rmse_threshold = 0.5,
                                   double r2_threshold   = 0.7)
        : rmse_thr_(rmse_threshold), r2_thr_(r2_threshold) {}

    UnderfittingResult detect(
        double rmse_train, double output_std, double r2_train
    ) const noexcept;

private:
    double rmse_thr_;
    double r2_thr_;
};

} // namespace aegis
