#pragma once
#include "regressor_library.hpp"
#include "individual_evaluator.hpp"
#include "population_diversity_monitor.hpp"
#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <mutex>
#include <thread>
#include <random>

namespace aegis {

struct DEConfig {
    // Island topology
    int    num_islands       = 3;
    int    population_size   = 50;
    int    elitism_count     = 2;

    // JADE parameters
    double mu_f              = 0.5;   // initial mean F (mutation factor)
    double mu_cr             = 0.9;   // initial mean CR (crossover rate)
    double jade_c            = 0.1;   // JADE adaptation learning rate

    // Migration
    int    migration_interval= 20;
    double migration_rate    = 0.1;

    // Chromosome encoding
    int    max_regressors    = 8;
    int    max_terms_per_reg = 3;
    int    num_variables     = 2;     // set from data
    int    max_delay         = 20;
    double pmin              = 0.5;
    double pmax              = 5.0;

    // Stopping
    int    max_generations   = 5000;
    int    stagnation_limit  = 500;

    // Anti-premature-convergence (random immigrants + triggered hypermutation)
    double reinit_ratio          = 0.1;  // fraction of worst non-elite individuals reinitialized per wave
    int    reinit_interval       = 25;   // island-stagnation generations between reinit waves
    double hypermutation_boost   = 1.5;  // mu_f multiplier applied on sustained zero success
    int    hypermutation_trigger = 20;   // consecutive zero-success generations to trigger hypermutation

    // Threading
    int    num_threads       = 0;     // 0 = auto (hardware_concurrency)
};

/** Progress report emitted every generation. */
struct GenerationReport {
    int    generation          = 0;
    double best_fitness        = 0.0;
    double rmse_train          = 0.0;
    double rmse_val            = 0.0;
    double rmse_test           = 0.0;
    double bic                 = 0.0;
    double aic                 = 0.0;
    double r2_train             = 0.0;
    double r2_val               = 0.0;
    double population_variance = 0.0;
    int    unique_structures   = 0;
    double success_rate        = 0.0;
    double population_diversity= 0.0;
    int    stagnation          = 0;
    double mu_f                = 0.0;
    double mu_cr               = 0.0;
    int    num_terms           = 0;
    bool   is_stable           = true;
    bool   overfitting         = false;
    bool   underfitting        = false;
    bool   pe_ok               = false;
    std::vector<double> residual_autocorr;
    std::vector<double> best_coefficients;
    double              best_intercept     = 0.0;
    std::vector<double> best_exponents;
    std::string         alerts;

    // ── AEGIS Curriculum indicators ──────────────────────────────────────
    double free_run_rmse            = std::numeric_limits<double>::quiet_NaN();
    double input_contribution_ratio = std::numeric_limits<double>::quiet_NaN();
    double residual_input_corr      = std::numeric_limits<double>::quiet_NaN();
    double structure_entropy        = 0.0; // Shannon entropy (bits) of structural hashes
    int    phase                    = 0;
    std::string phase_name;
    FitnessBreakdown fitness_breakdown;

    // ── Specialized islands / two-layer migration filter ─────────────────
    int    best_contexts_survived   = 0;
    double best_worst_fitness_seen  = std::numeric_limits<double>::quiet_NaN();
    std::vector<std::string> island_roles;
};

/** One DE island with independent population and RNG. */
class Island {
public:
    Island(int id, const DEConfig& cfg, uint64_t seed,
           const double* train_data, int train_rows,
           const double* val_data,   int val_rows,
           int cols, int output_col,
           const FitnessWeights& weights);

    void run_generation();

    Chromosome        best_chromosome() const;
    double            best_fitness()    const;
    int               stagnation()      const { return stagnation_; }
    const DEConfig&   config()          const { return cfg_; }
    double            mu_f()            const { return mu_f_; }
    double            mu_cr()           const { return mu_cr_; }
    double            success_rate()    const;

    /** Accept immigrants replacing worst individuals. */
    void accept_migrants(const std::vector<Chromosome>& migrants);

    /** Broad restart: reinitialize a large fraction of the population and
     *  reset JADE adaptation (mu_f/mu_cr, success archives). Last-resort
     *  anti-stagnation measure for when even local refinement stalls. */
    void restart(double ratio);

    /** Update config at runtime (for agent tuning). */
    void update_config(const DEConfig& new_cfg);

    /** Update fitness weights at runtime (for phase transitions). */
    void update_weights(const FitnessWeights& w) { evaluator_.weights() = w; }
    const FitnessWeights& weights() const noexcept { return evaluator_.weights(); }

    /** Override the validation window used by this island ("regime"). The
     *  pointer must remain valid for the island's lifetime. */
    void set_validation_window(const double* val_data, int val_rows) {
        val_data_ = val_data;
        val_rows_ = val_rows;
    }

    /** Reevaluate a chromosome under this island's weights + validation
     *  regime, in place. Tracks contexts_survived/worst_fitness_seen for
     *  cross-context robustness analysis. */
    void reevaluate(Chromosome& c) const;

    std::vector<Chromosome>&       population()       { return pop_; }
    const std::vector<Chromosome>& population() const { return pop_; }

private:
    int               id_;
    DEConfig          cfg_;
    std::mt19937_64   rng_;
    IndividualEvaluator evaluator_;

    const double* train_data_;
    int           train_rows_;
    const double* val_data_;
    int           val_rows_;
    int           cols_;
    int           output_col_;

    std::vector<Chromosome> pop_;
    int    generation_       = 0;
    int    stagnation_       = 0;
    double prev_best_        = std::numeric_limits<double>::infinity();
    double mu_f_             = 0.5;
    double mu_cr_            = 0.9;

    // JADE success archives
    std::vector<double> success_f_;
    std::vector<double> success_cr_;
    int    success_count_    = 0;
    int    trial_count_      = 0;

    // Anti-premature-convergence bookkeeping
    int    zero_success_streak_ = 0;

    /** Replace the worst non-elite individuals with fresh random
     *  chromosomes ("random immigrants"). */
    void reinitialize_worst();

    Chromosome random_chromosome();
    Chromosome mutate_jade(int target_idx, double& f_i, double& cr_i);
    Chromosome crossover_binomial(const Chromosome& target,
                                   const Chromosome& mutant, double cr);
    void jade_end_generation();

    double lehmer_mean(const std::vector<double>& v) const;
    double gauss_rand(double mean, double std);
    double cauchy_rand(double loc, double scale);
};

/** Main DE optimizer orchestrating multiple islands. */
class DifferentialEvolutionOptimizer {
public:
    using ProgressCallback = std::function<void(const GenerationReport&)>;
    using ShouldStopFn     = std::function<bool()>;

    explicit DifferentialEvolutionOptimizer(const DEConfig& cfg = DEConfig())
        : cfg_(cfg) {}

    /**
     * Initialize islands with data. Call before run().
     * Data is row-major (rows × cols).
     */
    void initialize(
        const double* train_data, int train_rows,
        const double* val_data,   int val_rows,
        const double* test_data,  int test_rows,
        int cols, int output_col,
        const FitnessWeights& weights = FitnessWeights()
    );

    /**
     * Run the optimizer asynchronously in a background thread.
     * on_progress is called from the worker thread every generation.
     * should_stop() is checked every generation; returns false → keep going.
     */
    void run_async(ProgressCallback on_progress, ShouldStopFn should_stop);

    /**
     * Run up to n generations synchronously (WASM / no-thread path).
     * Returns the number of generations actually run (may be < n if done or stopped).
     */
    int run_steps(int n, ProgressCallback on_progress,
                  ShouldStopFn should_stop = nullptr);

    /** Returns true when max_generations or stagnation_limit reached. */
    bool is_done() const;

    /** Stop the optimizer gracefully. Blocks until the thread exits. */
    void stop();

    /** Block until optimization is complete or stopped. */
    void wait();

    Chromosome best_chromosome() const;

    /** Apply agent tuning at runtime (thread-safe). */
    void apply_tuning(const std::string& param, double value);

    /** Update fitness weights across all islands at runtime (phase transitions). */
    void update_weights(const FitnessWeights& w);

    /** Current fitness weights (as seen by island 0). */
    FitnessWeights current_weights() const;

    /** Update search-space bounds (pmax, max_delay) across all islands at
     *  runtime, preserving each island's current JADE-adapted mu_f/mu_cr. */
    void update_search_space(double pmax, int max_delay);

    /** Update fitness weights for a single island (specialized roles). */
    void update_weights_for_island(int idx, const FitnessWeights& w);

    /** Override the validation window ("regime") for a single island. The
     *  pointer must remain valid for the optimizer's lifetime. */
    void set_island_validation_window(int idx, const double* val_data, int val_rows);

    /** Record the human-readable role name for a single island (for reports). */
    void set_island_role(int idx, const std::string& name);

    /** Force a broad restart across all islands: reinitialize a larger
     *  fraction of each island's population and reset JADE mu_f/mu_cr to
     *  their configured defaults. Last-resort anti-stagnation measure. */
    void trigger_restart(double ratio);

    DEConfig& config_mut() { return cfg_; }

private:
    DEConfig              cfg_;
    std::vector<std::unique_ptr<Island>> islands_;
    std::vector<std::string> island_roles_;
    std::thread           worker_thread_;
    std::atomic<bool>     stop_flag_{false};
    mutable std::mutex    islands_mutex_;

    const double* train_data_ = nullptr;
    int           train_rows_ = 0;
    const double* val_data_   = nullptr;
    int           val_rows_   = 0;
    const double* test_data_  = nullptr;
    int           test_rows_  = 0;
    int           cols_       = 0;
    int           output_col_ = 0;

    // Synchronous-step tracking (run_steps / WASM path)
    int    current_gen_           = 0;
    int    global_stagnation_sync_= 0;
    double prev_best_sync_        = std::numeric_limits<double>::infinity();

    void migrate();
    GenerationReport build_report(int generation) const;
    /** Pick the best chromosome across islands, rescoring non-reference
     *  islands' bests under island[0]'s weights+regime for a fair, common
     *  scale ("canonical" champion selection). Assumes islands_mutex_ held. */
    Chromosome canonical_best_locked() const;
};

} // namespace aegis
