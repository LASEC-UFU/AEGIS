#pragma once
#include <string>

namespace aegis {

struct OverfittingResult {
    bool   detected        = false;
    double gap_ratio       = 0.0;  // (rmse_val - rmse_train) / rmse_train
    double complexity_ratio= 0.0;  // k / n_train
    std::string suggestion;
};

class OverfittingDetector {
public:
    /**
     * gap_threshold    : if (rmse_val - rmse_train)/rmse_train > this → overfit
     * complexity_ratio : if k/n_train > this → also suspect
     */
    explicit OverfittingDetector(double gap_threshold    = 0.3,
                                  double complexity_ratio = 0.1)
        : gap_thr_(gap_threshold), complexity_thr_(complexity_ratio) {}

    OverfittingResult detect(
        double rmse_train, double rmse_val,
        int k_params, int n_train
    ) const noexcept;

private:
    double gap_thr_;
    double complexity_thr_;
};

} // namespace aegis
