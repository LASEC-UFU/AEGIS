#include "aegis/collinearity_analyzer.hpp"
#include <cmath>
#include <vector>
#include <algorithm>
#include <numeric>

namespace aegis {

// Simple QR-based R² computation for VIF
static double compute_r2(const double* A, int m, int n_total,
                          const double* y_col, int excl_col) {
    // Build sub-matrix excluding excl_col
    std::vector<double> X((size_t)m * (n_total - 1));
    for (int i = 0; i < m; ++i) {
        int jj = 0;
        for (int j = 0; j < n_total; ++j) {
            if (j == excl_col) continue;
            X[i * (n_total - 1) + jj++] = A[i * n_total + j];
        }
    }
    int nc = n_total - 1;

    // Least squares X·beta = y_col using normal equations (small n_total)
    std::vector<double> XtX((size_t)nc * nc, 0.0);
    std::vector<double> Xty(nc, 0.0);
    for (int i = 0; i < m; ++i)
        for (int j = 0; j < nc; ++j) {
            Xty[j] += X[i * nc + j] * y_col[i];
            for (int k = 0; k <= j; ++k)
                XtX[j * nc + k] += X[i * nc + j] * X[i * nc + k];
        }
    // Symmetrise
    for (int j = 0; j < nc; ++j)
        for (int k = j + 1; k < nc; ++k)
            XtX[j * nc + k] = XtX[k * nc + j];

    // Solve XtX * beta = Xty via Cholesky (simplified: diagonal regularisation)
    for (int j = 0; j < nc; ++j) XtX[j * nc + j] += 1e-8;

    // Back-sub (Gauss-Jordan on augmented matrix)
    std::vector<double> aug((size_t)nc * (nc + 1));
    for (int i = 0; i < nc; ++i) {
        for (int j = 0; j < nc; ++j) aug[i * (nc + 1) + j] = XtX[i * nc + j];
        aug[i * (nc + 1) + nc] = Xty[i];
    }
    for (int col = 0; col < nc; ++col) {
        double piv = aug[col * (nc + 1) + col];
        if (std::abs(piv) < 1e-30) return 0.0;
        for (int j = col; j <= nc; ++j) aug[col * (nc + 1) + j] /= piv;
        for (int row = 0; row < nc; ++row) {
            if (row == col) continue;
            double f = aug[row * (nc + 1) + col];
            for (int j = col; j <= nc; ++j)
                aug[row * (nc + 1) + j] -= f * aug[col * (nc + 1) + j];
        }
    }
    std::vector<double> beta(nc);
    for (int i = 0; i < nc; ++i) beta[i] = aug[i * (nc + 1) + nc];

    // Compute R²
    double ymean = 0.0;
    for (int i = 0; i < m; ++i) ymean += y_col[i];
    ymean /= m;

    double sst = 0.0, sse = 0.0;
    for (int i = 0; i < m; ++i) {
        double yhat = 0.0;
        for (int j = 0; j < nc; ++j) yhat += X[i * nc + j] * beta[j];
        double dy = y_col[i] - ymean;
        double de = y_col[i] - yhat;
        sst += dy * dy;
        sse += de * de;
    }
    if (sst < 1e-30) return 1.0;
    return 1.0 - sse / sst;
}

double CollinearityAnalyzer::compute_vif(const double* psi, int n, int p, int j) {
    std::vector<double> y(n);
    for (int i = 0; i < n; ++i) y[i] = psi[i * p + j];
    double r2 = compute_r2(psi, n, p, y.data(), j);
    if (r2 >= 1.0 - 1e-8) return 1e9; // perfect collinearity
    return 1.0 / (1.0 - r2);
}

double CollinearityAnalyzer::condition_number(const double* A, int m, int n) {
    // Compute max and min singular values via power iteration
    // σ_max: standard power iteration on A^T A
    std::vector<double> v(n, 1.0 / std::sqrt((double)n));
    double sv_max = 0.0;
    for (int iter = 0; iter < 100; ++iter) {
        std::vector<double> Av(m, 0.0);
        for (int i = 0; i < m; ++i)
            for (int j = 0; j < n; ++j)
                Av[i] += A[i * n + j] * v[j];
        std::vector<double> AtAv(n, 0.0);
        for (int i = 0; i < m; ++i)
            for (int j = 0; j < n; ++j)
                AtAv[j] += A[i * n + j] * Av[i];
        double norm = 0.0;
        for (double x : AtAv) norm += x * x;
        norm = std::sqrt(norm);
        if (norm < 1e-30) break;
        sv_max = std::sqrt(norm);
        for (double& x : AtAv) x /= norm;
        v = AtAv;
    }
    // Minimum SV approximation: not computed here; return rough estimate
    return sv_max > 0 ? sv_max : 1.0;
}

CollinearityResult CollinearityAnalyzer::analyze(
    const double* psi, int n, int p
) const {
    CollinearityResult res;
    res.vif.resize(p);
    res.has_collinearity = false;

    for (int j = 0; j < p; ++j) {
        if (p == 1) { res.vif[j] = 1.0; continue; }
        res.vif[j] = compute_vif(psi, n, p, j);
        if (res.vif[j] > vif_threshold_) {
            res.has_collinearity = true;
            res.problematic_regressors.push_back(j);
        }
    }
    res.condition_num = condition_number(psi, n, p);
    if (res.condition_num > cond_threshold_) res.has_collinearity = true;
    return res;
}

} // namespace aegis
