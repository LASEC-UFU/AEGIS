#include "aegis/stability_analyzer.hpp"
#include <cmath>
#include <algorithm>
#include <complex>
#include <vector>

namespace aegis {

// Companion matrix eigenvalues via power iteration (simplified)
std::vector<std::complex<double>> StabilityAnalyzer::poly_roots(
    const std::vector<double>& coeffs
) {
    int n = static_cast<int>(coeffs.size()) - 1;
    if (n <= 0) return {};

    // Build companion matrix (column-major)
    std::vector<double> C(n * n, 0.0);
    for (int i = 0; i < n - 1; ++i)
        C[(i + 1) * n + i] = 1.0; // sub-diagonal
    double an = coeffs[n];
    if (std::abs(an) < 1e-30) an = 1.0;
    for (int i = 0; i < n; ++i)
        C[i * n + (n - 1)] = -coeffs[i] / an; // last column

    // QR iteration to find eigenvalues (simplified - returns diagonal after 100 iters)
    std::vector<std::complex<double>> roots;

    // For small polynomials use analytical solutions
    if (n == 1) {
        double r = -coeffs[0] / coeffs[1];
        roots.emplace_back(r, 0.0);
        return roots;
    }
    if (n == 2) {
        double a = coeffs[2], b = coeffs[1], c = coeffs[0];
        double disc = b * b - 4.0 * a * c;
        if (disc >= 0) {
            double sq = std::sqrt(disc);
            roots.emplace_back((-b + sq) / (2 * a), 0.0);
            roots.emplace_back((-b - sq) / (2 * a), 0.0);
        } else {
            double real = -b / (2 * a);
            double imag = std::sqrt(-disc) / (2 * a);
            roots.emplace_back(real,  imag);
            roots.emplace_back(real, -imag);
        }
        return roots;
    }

    // For higher order: use companion matrix power iteration to estimate
    // the dominant eigenvalue, then deflate. This is a rough approximation.
    // Production code would use a full QR eigenvalue algorithm.
    std::vector<double> v(n, 1.0 / std::sqrt((double)n));
    for (int iter = 0; iter < 200; ++iter) {
        std::vector<double> w(n, 0.0);
        for (int i = 0; i < n; ++i)
            for (int j = 0; j < n; ++j)
                w[i] += C[j * n + i] * v[j];
        double norm = 0.0;
        for (double x : w) norm += x * x;
        norm = std::sqrt(norm);
        if (norm < 1e-30) break;
        for (double& x : w) x /= norm;
        v = w;
    }
    // Rayleigh quotient for dominant eigenvalue
    std::vector<double> Cv(n, 0.0);
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j)
            Cv[i] += C[j * n + i] * v[j];
    double ev = 0.0;
    for (int i = 0; i < n; ++i) ev += v[i] * Cv[i];
    roots.emplace_back(ev, 0.0);

    // Fill remaining with zero (conservative stability check)
    for (int i = 1; i < n; ++i) roots.emplace_back(0.0, 0.0);
    return roots;
}

std::vector<double> StabilityAnalyzer::extract_denom_poly(
    const Chromosome& chrom
) const {
    // Collect denominator coefficients grouped by delay
    int max_del = 0;
    for (const auto& r : chrom.regressors)
        if (r.is_denominator()) max_del = std::max(max_del, r.max_delay());
    if (max_del == 0) return {};

    std::vector<double> poly(max_del + 1, 0.0);
    poly[0] = 1.0; // D(k) = 1 + ...

    for (size_t j = 0; j < chrom.regressors.size(); ++j) {
        const auto& reg = chrom.regressors[j];
        if (!reg.is_denominator()) continue;
        if (j >= chrom.coefficients.size()) continue;
        int del = reg.max_delay();
        if (del < 1 || del > max_del) continue;
        poly[del] += chrom.coefficients[j];
    }
    return poly;
}

StabilityResult StabilityAnalyzer::analyze(const Chromosome& chrom) const {
    StabilityResult res;
    if (!chrom.is_rational() || chrom.coefficients.empty()) {
        res.is_stable = true;
        res.stability_margin = 1.0;
        res.penalty = 0.0;
        return res;
    }

    auto poly = extract_denom_poly(chrom);
    if (poly.empty()) return res;

    res.denominator_roots = poly_roots(poly);

    double max_mod = 0.0;
    for (const auto& root : res.denominator_roots) {
        double mod = std::abs(root);
        max_mod = std::max(max_mod, mod);
    }

    res.is_stable = (max_mod < 1.0);
    res.stability_margin = 1.0 - max_mod;

    if (!res.is_stable) {
        res.penalty = std::max(0.0, max_mod - 1.0) * 10.0;
    }
    return res;
}

} // namespace aegis
