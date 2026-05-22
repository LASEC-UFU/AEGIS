#pragma once
#include "regressor_library.hpp"
#include <vector>

namespace aegis {

struct DiversityMetrics {
    int    unique_structures   = 0;
    double structure_entropy   = 0.0;  // Shannon entropy over structural hashes
    double phenotypic_variance = 0.0;  // variance of fitness values
    double fitness_entropy     = 0.0;
    double avg_hamming_dist    = 0.0;  // avg structural Hamming distance
    bool   stagnated           = false;
    double stagnation_ratio    = 0.0;  // fraction of population with same best fitness
};

class PopulationDiversityMonitor {
public:
    /**
     * Compute diversity metrics for an island population.
     *   population : vector of chromosomes
     *   recent_fitness_history : last N best-fitness values (for stagnation detection)
     *   stagnation_window      : window size for stagnation check
     */
    DiversityMetrics compute(
        const std::vector<Chromosome>& population,
        const std::vector<double>&     recent_fitness_history,
        int                            stagnation_window = 50
    ) const;

private:
    static double shannon_entropy(const std::vector<uint32_t>& hashes);
};

} // namespace aegis
