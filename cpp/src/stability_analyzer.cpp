#include "aegis/stability_analyzer.hpp"
#include <cmath>
#include <algorithm>
#include <complex>
#include <vector>

namespace aegis {

void StabilityAnalyzer::finalize(StabilityDiagnostics& d, bool is_rational) {
    double p_sing = 0.0;
    if (is_rational) {
        if (d.denominator_sign_changes > 0) {
            p_sing = 1.0;
        } else if (std::isfinite(d.min_abs_denominator)) {
            p_sing = std::max(0.0, (kDenominatorMargin - d.min_abs_denominator) /
                                   kDenominatorMargin);
        }
    }
    const double p_div = d.free_run_diverged ? 1.0 : 0.0;
    d.penalty = p_sing + p_div;
    d.is_stable = !d.free_run_diverged &&
                  (!is_rational || (d.denominator_sign_changes == 0 &&
                                    !(d.min_abs_denominator < 1e-6)));
    d.evaluated = true;
}

std::vector<std::complex<double>> StabilityAnalyzer::monic_roots(const std::vector<double>& c) {
    using cd = std::complex<double>;
    const int n = static_cast<int>(c.size());
    std::vector<cd> roots;
    if (n == 0) return roots;
    if (n == 1) { roots.emplace_back(-c[0], 0.0); return roots; }

    // Cauchy bound for the initial circle radius.
    double bound = 0.0;
    for (double v : c) bound = std::max(bound, std::abs(v));
    bound = 1.0 + bound;

    auto poly = [&](const cd& z) {
        cd p(1.0, 0.0);
        for (int i = 0; i < n; ++i) p = p * z + c[i];
        return p;
    };

    roots.resize(n);
    const cd seed(0.4, 0.9);
    cd w(1.0, 0.0);
    for (int i = 0; i < n; ++i) {
        w *= seed;
        roots[i] = bound * w / std::abs(w);
    }
    for (int it = 0; it < 2000; ++it) {
        double max_delta = 0.0;
        for (int i = 0; i < n; ++i) {
            cd denom(1.0, 0.0);
            for (int j = 0; j < n; ++j)
                if (j != i) denom *= (roots[i] - roots[j]);
            if (std::abs(denom) < 1e-300) denom = cd(1e-300, 0.0);
            const cd delta = poly(roots[i]) / denom;
            roots[i] -= delta;
            max_delta = std::max(max_delta, std::abs(delta));
        }
        if (max_delta < 1e-13 * bound) break;
    }
    return roots;
}

double StabilityAnalyzer::linear_spectral_radius(const Chromosome& chrom, int output_col) {
    if (chrom.coefficients.size() != chrom.regressors.size()) return std::nan("");
    int n = 0;
    std::vector<double> a(1, 0.0); // a[d] for d = 1..n (index 0 unused)
    for (size_t j = 0; j < chrom.regressors.size(); ++j) {
        const auto& reg = chrom.regressors[j];
        if (reg.is_denominator() || reg.terms.size() != 1) continue;
        const auto& t = reg.terms[0];
        if (t.variable != output_col || std::abs(t.exponent - 1.0) > 1e-9) continue;
        if (t.delay > n) { n = t.delay; a.resize(n + 1, 0.0); }
        a[t.delay] += chrom.coefficients[j];
    }
    if (n == 0) return 0.0;
    // z^n − a1 z^{n−1} − … − an  →  monic coefficients c[i] = −a[i+1]
    std::vector<double> c(n);
    for (int i = 0; i < n; ++i) c[i] = -a[i + 1];
    // Trailing zero coefficients correspond to roots at the origin.
    while (!c.empty() && std::abs(c.back()) < 1e-300) c.pop_back();
    if (c.empty()) return 0.0;
    double rho = 0.0;
    for (const auto& r : monic_roots(c)) rho = std::max(rho, std::abs(r));
    return rho;
}

} // namespace aegis
