#pragma once
#include <vector>

namespace aegis {

struct CollinearityResult {
    std::vector<double> vif;          // Variance Inflation Factor per regressor
    double              condition_num; // Condition number of Ψ^T Ψ
    bool                has_collinearity; // any VIF > threshold
    std::vector<int>    problematic_regressors;
};

class CollinearityAnalyzer {
public:
    explicit CollinearityAnalyzer(double vif_threshold = 10.0,
                                   double cond_threshold = 1e6)
        : vif_threshold_(vif_threshold), cond_threshold_(cond_threshold) {}

    /**
     * Analyze collinearity of the regressor matrix.
     *   psi       : row-major, n × p (n samples, p regressors)
     *   n, p      : dimensions
     */
    CollinearityResult analyze(const double* psi, int n, int p) const;

private:
    double vif_threshold_;
    double cond_threshold_;

    /** VIF_j = 1 / (1 - R²_j), where R²_j is from regressing col j on all others. */
    static double compute_vif(const double* psi, int n, int p, int j);

    /** Condition number of A^T A using SVD power iteration. */
    static double condition_number(const double* A, int m, int n);
};

} // namespace aegis
