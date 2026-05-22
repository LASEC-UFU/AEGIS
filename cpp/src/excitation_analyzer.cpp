#include "aegis/excitation_analyzer.hpp"
#include <cmath>
#include <algorithm>
#include <numeric>

namespace aegis {

std::vector<double> ExcitationAnalyzer::svd_singular_values(
    const double* A, int m, int n, int max_iter
) {
    // Power iteration for dominant singular values
    int k = std::min(m, n);
    std::vector<double> svs(k, 0.0);

    std::vector<double> B((size_t)n * n, 0.0); // A^T A
    for (int i = 0; i < m; ++i)
        for (int j = 0; j < n; ++j)
            for (int l = 0; l < n; ++l)
                B[j * n + l] += A[i * n + j] * A[i * n + l];

    // Dominant singular value via power iteration
    std::vector<double> v(n, 1.0 / std::sqrt((double)n));
    double sv = 0.0;
    for (int iter = 0; iter < max_iter; ++iter) {
        std::vector<double> Bv(n, 0.0);
        for (int i = 0; i < n; ++i)
            for (int j = 0; j < n; ++j)
                Bv[i] += B[i * n + j] * v[j];
        double norm = 0.0;
        for (double x : Bv) norm += x * x;
        norm = std::sqrt(norm);
        if (norm < 1e-30) break;
        sv = std::sqrt(norm);
        for (double& x : Bv) x /= norm;
        v = Bv;
    }
    svs[0] = sv;

    // Minimum singular value: norm of smallest eigenvector of B (rough)
    // Use inverse iteration approximation
    double sv_min = sv;
    for (int j = 0; j < n; ++j)
        B[j * n + j] -= sv_min; // shift
    // Power iteration on shifted gives smallest
    std::fill(v.begin(), v.end(), 1.0 / std::sqrt((double)n));
    double sv2 = 0.0;
    for (int iter = 0; iter < max_iter / 2; ++iter) {
        std::vector<double> Bv(n, 0.0);
        for (int i = 0; i < n; ++i)
            for (int j = 0; j < n; ++j)
                Bv[i] += B[i * n + j] * v[j];
        double norm = 0.0;
        for (double x : Bv) norm += x * x;
        norm = std::sqrt(norm);
        if (norm < 1e-30) break;
        sv2 = std::sqrt(norm);
        for (double& x : Bv) x /= norm;
        v = Bv;
    }
    if (k > 1) svs[k - 1] = sv2;
    return svs;
}

ExcitationResult ExcitationAnalyzer::analyze(const double* psi, int n, int p) const {
    ExcitationResult res;
    if (n <= 0 || p <= 0) {
        res.warning = "Empty regressor matrix";
        return res;
    }

    res.singular_values = svd_singular_values(psi, n, p);
    if (!res.singular_values.empty()) {
        res.min_singular_value = res.singular_values.back();
        double max_sv = res.singular_values.front();

        // Effective rank estimation
        int eff_rank = 0;
        double threshold = max_sv * 1e-6;
        for (double sv : res.singular_values)
            if (sv > threshold) ++eff_rank;

        res.rank_ratio = static_cast<double>(eff_rank) / p;
        res.is_persistently_excited = (res.min_singular_value > pe_threshold_);

        if (!res.is_persistently_excited) {
            res.warning = "Insufficient excitation: min singular value = "
                        + std::to_string(res.min_singular_value)
                        + " < threshold " + std::to_string(pe_threshold_);
        }
    }
    return res;
}

} // namespace aegis
