#include "aegis/de_optimizer.hpp"
#include "aegis/normalizer.hpp"

#include <cmath>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include <vector>

namespace {

bool expect(bool condition, const char* message) {
    if (!condition) std::fprintf(stderr, "FAIL: %s\n", message);
    return condition;
}

bool test_normalizers() {
    double minmax_data[] = {-2.0, 0.0, 2.0};
    aegis::Normalizer minmax(aegis::NormalizerType::MinMax, -1.0, 1.0);
    minmax.fit(minmax_data, 3, 1);
    minmax.transform(minmax_data, 3, 1);

    bool ok = true;
    ok &= expect(std::abs(minmax_data[0] + 1.0) < 1e-12,
                 "min-max lower endpoint must be -1");
    ok &= expect(std::abs(minmax_data[1]) < 1e-12,
                 "min-max midpoint must remain centered");
    ok &= expect(std::abs(minmax_data[2] - 1.0) < 1e-12,
                 "min-max upper endpoint must be 1");

    double zscore_data[] = {-2.0, 0.0, 2.0};
    aegis::Normalizer zscore(aegis::NormalizerType::ZScore);
    zscore.fit(zscore_data, 3, 1);
    zscore.transform(zscore_data, 3, 1);
    ok &= expect(zscore_data[0] < 0.0 && zscore_data[2] > 1.0,
                 "z-score values must not be clamped to a min-max interval");

    bool rejected_empty = false;
    try {
        zscore.fit(nullptr, 0, 1);
    } catch (const std::invalid_argument&) {
        rejected_empty = true;
    }
    ok &= expect(rejected_empty, "normalizer must reject empty training data");
    return ok;
}

bool test_optimizer_invariants() {
    constexpr int rows = 360;
    constexpr int cols = 2;
    std::vector<double> data(static_cast<size_t>(rows) * cols, 0.0);
    for (int k = 0; k < rows; ++k) {
        const double u = std::sin(0.071 * k) + 0.35 * std::sin(0.193 * k);
        const double y_prev = k > 0 ? data[static_cast<size_t>(k - 1) * cols + 1] : 0.0;
        const double u_prev = k > 0 ? data[static_cast<size_t>(k - 1) * cols] : 0.0;
        data[static_cast<size_t>(k) * cols] = u;
        data[static_cast<size_t>(k) * cols + 1] = 0.65 * y_prev + 0.30 * u_prev;
    }

    aegis::DEConfig cfg;
    cfg.num_islands = 3;
    cfg.population_size = 20;
    cfg.elitism_count = 2;
    cfg.max_regressors = 5;
    cfg.max_terms_per_reg = 2;
    cfg.num_variables = cols;
    cfg.max_delay = 5;
    cfg.pmin = 1.0;
    cfg.pmax = 1.0;
    cfg.migration_interval = 3;
    cfg.max_generations = 12;
    cfg.stagnation_limit = 12;
    cfg.random_seed = 12345;

    aegis::FitnessWeights weights;
    weights.alpha = 0.05;
    weights.gamma = 0.01;
    weights.zeta = 1.0;
    weights.theta = 0.1;

    constexpr int train_rows = 260;
    aegis::Island island(
        0, cfg, 12345, data.data(), train_rows,
        data.data() + static_cast<size_t>(train_rows) * cols,
        rows - train_rows, cols, 1, weights
    );
    aegis::Chromosome invalid;
    invalid.evaluated = true;
    invalid.fitness = -123.0;
    island.reevaluate(invalid);

    bool ok = true;
    ok &= expect(!invalid.evaluated && std::isinf(invalid.fitness),
                 "failed reevaluation must invalidate stale fitness");

    aegis::DifferentialEvolutionOptimizer optimizer(cfg);
    optimizer.initialize(
        data.data(), train_rows,
        data.data() + static_cast<size_t>(train_rows) * cols, rows - train_rows,
        nullptr, 0, cols, 1, weights
    );

    double previous_best = std::numeric_limits<double>::infinity();
    int reports = 0;
    optimizer.run_steps(10, [&](const aegis::GenerationReport& report) {
        ++reports;
        ok &= expect(std::isfinite(report.best_fitness),
                     "best fitness must remain finite");
        ok &= expect(std::isfinite(report.population_diversity),
                     "population diversity must remain finite");
        ok &= expect(report.success_rate >= 0.0 && report.success_rate <= 1.0,
                     "success rate must be a probability");
        ok &= expect(report.best_fitness <= previous_best + 1e-12,
                     "elitist minimization must not lose the best fitness");
        previous_best = report.best_fitness;
    });
    ok &= expect(reports == 10, "optimizer must emit one report per generation");
    return ok;
}

} // namespace

int main() {
    const bool ok = test_normalizers() && test_optimizer_invariants();
    if (ok) std::puts("All C++ core tests passed.");
    return ok ? 0 : 1;
}
