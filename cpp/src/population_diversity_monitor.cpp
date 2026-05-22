#include "aegis/population_diversity_monitor.hpp"
#include <cmath>
#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <numeric>

namespace aegis {

double PopulationDiversityMonitor::shannon_entropy(
    const std::vector<uint32_t>& hashes
) {
    if (hashes.empty()) return 0.0;
    std::unordered_map<uint32_t, int> freq;
    for (uint32_t h : hashes) ++freq[h];
    double n = static_cast<double>(hashes.size());
    double H = 0.0;
    for (const auto& [h, cnt] : freq) {
        double p = cnt / n;
        H -= p * std::log2(p);
    }
    return H;
}

DiversityMetrics PopulationDiversityMonitor::compute(
    const std::vector<Chromosome>& population,
    const std::vector<double>&     recent_fitness_history,
    int                            stagnation_window
) const {
    DiversityMetrics m;
    if (population.empty()) return m;

    // Structural diversity
    std::vector<uint32_t> hashes;
    hashes.reserve(population.size());
    for (const auto& c : population)
        if (c.evaluated) hashes.push_back(c.structural_hash());

    std::unordered_set<uint32_t> unique(hashes.begin(), hashes.end());
    m.unique_structures = static_cast<int>(unique.size());
    m.structure_entropy = shannon_entropy(hashes);

    // Phenotypic diversity (fitness variance)
    double sum = 0.0, sum2 = 0.0;
    int count = 0;
    for (const auto& c : population) {
        if (!c.evaluated || !std::isfinite(c.fitness)) continue;
        sum  += c.fitness;
        sum2 += c.fitness * c.fitness;
        ++count;
    }
    if (count > 1) {
        double mean = sum / count;
        m.phenotypic_variance = sum2 / count - mean * mean;
    }

    // Stagnation detection
    if ((int)recent_fitness_history.size() >= stagnation_window) {
        const auto& h = recent_fitness_history;
        int n = (int)h.size();
        double first = h[n - stagnation_window];
        double last  = h[n - 1];
        double relative_change = std::abs(first - last) / (std::abs(first) + 1e-30);
        m.stagnated      = (relative_change < 1e-6);
        m.stagnation_ratio = relative_change;
    }

    // Fitness entropy (discretised fitness bins)
    if (count > 1) {
        std::vector<double> fits;
        fits.reserve(count);
        for (const auto& c : population)
            if (c.evaluated && std::isfinite(c.fitness)) fits.push_back(c.fitness);
        double mn = *std::min_element(fits.begin(), fits.end());
        double mx = *std::max_element(fits.begin(), fits.end());
        if (mx - mn > 1e-30) {
            std::vector<int> bins(10, 0);
            for (double f : fits) {
                int b = static_cast<int>(10.0 * (f - mn) / (mx - mn));
                b = std::min(b, 9);
                ++bins[b];
            }
            double n_d = static_cast<double>(fits.size());
            for (int b : bins) {
                if (b == 0) continue;
                double p = b / n_d;
                m.fitness_entropy -= p * std::log2(p);
            }
        }
    }
    return m;
}

} // namespace aegis
