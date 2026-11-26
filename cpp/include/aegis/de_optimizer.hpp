#pragma once
#include "regressor_library.hpp"
#include "individual_evaluator.hpp"
#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <mutex>
#include <thread>
#include <random>
#include <memory>
#include <unordered_map>

namespace aegis {

enum class MutationStrategy : int {
    JadeCurrentToPBest = 0, // JADE DE/current-to-pbest/1 with adaptive F/CR
    Rand1              = 1, // classic DE/rand/1 with fixed F/CR (ablation baseline)
};

inline const char* mutation_strategy_name(MutationStrategy s) {
    return s == MutationStrategy::Rand1 ? "rand1" : "jade";
}

struct DEConfig {
    // Island topology
    int    num_islands       = 3;
    int    population_size   = 50;
    int    elitism_count     = 2;     // protected from random immigrants / restarts

    // Mutation strategy and JADE parameters
    MutationStrategy strategy = MutationStrategy::JadeCurrentToPBest;
    double mu_f              = 0.5;   // initial mean F (JADE) or fixed F (rand1)
    double mu_cr             = 0.9;   // initial mean CR (JADE) or fixed CR (rand1)
    double jade_c            = 0.1;   // JADE adaptation learning rate
    double jade_p            = 0.2;   // JADE p-best fraction (top 100p %)

    // Migration (ring topology, two-layer filter)
    int    migration_interval= 20;
    double migration_rate    = 0.1;

    // Chromosome encoding
    int    max_regressors    = 8;
    int    max_terms_per_reg = 3;
    int    num_variables     = 2;     // set from data
    int    max_delay         = 40;
    double pmin              = 0.5;
    double pmax              = 5.0;
    double exponent_step     = 0.5;   // ≤ 0 → continuous exponents
    PowerMode power_mode     = PowerMode::Hybrid;
    double denominator_probability = 0.3; // 0 → polynomial-only search
    double variable_mutation_rate  = 0.3; // per factor
    double structural_mutation_rate= 0.1; // per trial: add/delete/replace regressor

    // Stopping
    int    max_generations   = 5000;
    int    stagnation_limit  = 500;   // generations without canonical improvement
    long long max_evaluations= 0;     // 0 = unlimited

    // Anti-premature-convergence (random immigrants + triggered hypermutation)
    double reinit_ratio          = 0.1;
    int    reinit_interval       = 25;
    bool   hypermutation         = true;
    double hypermutation_boost   = 1.5;
    int    hypermutation_trigger = 20;

    // Threading
    int    num_threads       = 0;     // 0 = one thread per island; 1 = sequential
    int    fit_method        = 0;     // P2'a: 0 = QR (default), 1 = Gram/Cholesky in the island inner loop
    uint64_t random_seed     = 0;     // 0 = time-based seed (pipeline records the effective seed)
};

/** Per-island statistics published every generation. */
struct IslandReport {
    int    id = 0;
    std::string role;
    double best_fitness   = std::numeric_limits<double>::quiet_NaN();
    double mean_fitness   = std::numeric_limits<double>::quiet_NaN();
    double median_fitness = std::numeric_limits<double>::quiet_NaN();
    double std_fitness    = std::numeric_limits<double>::quiet_NaN();
    double worst_fitness  = std::numeric_limits<double>::quiet_NaN();
    int    stagnation     = 0;
    double success_rate   = 0.0;
    double mu_f           = 0.0;
    double mu_cr          = 0.0;
    int    unique_structures = 0;
    int    population_size   = 0;
    double mean_num_regressors = 0.0;
    double best_rmse_val  = std::numeric_limits<double>::quiet_NaN(); // island's own regime
};

/** Progress report emitted every generation. */
struct GenerationReport {
    int       generation          = 0;   // completed generations (1-based)
    long long evaluations         = 0;   // cumulative objective evaluations
    double best_fitness           = std::numeric_limits<double>::infinity(); // canonical champion
    double rmse_train             = std::numeric_limits<double>::quiet_NaN();
    double rmse_val               = std::numeric_limits<double>::quiet_NaN();
    double rmse_test              = std::numeric_limits<double>::quiet_NaN(); // never filled during a run
    double bic                    = std::numeric_limits<double>::quiet_NaN();
    double aic                    = std::numeric_limits<double>::quiet_NaN();
    double r2_train               = std::numeric_limits<double>::quiet_NaN();
    double r2_val                 = std::numeric_limits<double>::quiet_NaN();

    // Population (pooled over islands)
    double population_variance    = 0.0; // mean within-island fitness variance
    int    unique_structures      = 0;
    double success_rate           = 0.0; // mean over islands
    double population_diversity   = 0.0; // mean within-island fitness std
    double fitness_mean           = std::numeric_limits<double>::quiet_NaN(); // mean of island means
    double fitness_median         = std::numeric_limits<double>::quiet_NaN(); // median of island medians
    int    stagnation             = 0;   // max island stagnation
    int    global_stagnation      = 0;   // generations without canonical improvement
    double mu_f                   = 0.0; // mean over islands
    double mu_cr                  = 0.0;
    double structure_entropy      = 0.0; // Shannon entropy (bits) of structural hashes
    double mean_num_regressors    = 0.0;
    std::vector<IslandReport> islands;

    // Champion structure / coefficients
    int    num_terms              = 0;   // number of regressors (kept name for compatibility)
    int    num_factors            = 0;
    int    best_max_delay         = 0;
    double best_max_exponent      = 0.0;
    bool   best_is_rational       = false;
    std::vector<double>      best_coefficients;
    double                   best_intercept     = 0.0;
    std::vector<double>      best_exponents;
    std::vector<double>      best_err;
    std::vector<std::string> best_term_labels;

    // Champion indicators
    double free_run_rmse            = std::numeric_limits<double>::quiet_NaN(); // horizon, validation
    double input_contribution_ratio = std::numeric_limits<double>::quiet_NaN();
    double residual_input_corr      = std::numeric_limits<double>::quiet_NaN();
    FitnessBreakdown   fitness_breakdown;
    StabilityDiagnostics stability;
    ModelDiagnostics   diagnostics;  // residual ACF, full free-run on validation, over/under-fit

    // Compatibility flags (derived from stability/diagnostics)
    bool   is_stable              = true;
    bool   overfitting            = false;
    bool   underfitting           = false;
    bool   pe_ok                  = false;
    std::vector<double> residual_autocorr; // REAL residual ACF (lags 0..L)
    std::string alerts;

    // Curriculum / roles (filled by the pipeline)
    int    phase                    = 0;
    std::string phase_name;
    std::vector<std::string> island_roles;
    int    best_contexts_survived   = 0;
    double best_worst_fitness_seen  = std::numeric_limits<double>::quiet_NaN();

    std::string stop_reason;   // empty while running
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
    const Chromosome& best_ref() const;
    double            best_fitness()    const;
    int               stagnation()      const { return stagnation_; }
    const DEConfig&   config()          const { return cfg_; }
    double            mu_f()            const { return mu_f_; }
    double            mu_cr()           const { return mu_cr_; }
    double            success_rate()    const;
    long long         evaluations()     const { return evaluator_.evaluations(); }

    void accept_migrants(const std::vector<Chromosome>& migrants);
    void restart(double ratio);

    /** Replace config (search space, rates). JADE means are NOT reset. */
    void update_config(const DEConfig& new_cfg);
    void set_mu_f(double v)  { mu_f_ = v; }
    void set_mu_cr(double v) { mu_cr_ = v; }

    void update_weights(const FitnessWeights& w);
    const FitnessWeights& weights() const noexcept { return evaluator_.weights(); }

    void set_validation_window(const double* val_data, int val_rows);
    void reevaluate_population();
    void reevaluate(Chromosome& c) const;

    IslandReport report() const;

    std::vector<Chromosome>&       population()       { return pop_; }
    const std::vector<Chromosome>& population() const { return pop_; }

    // Variation operators (public for unit testing).
    Chromosome mutate(int target_idx, double& f_i, double& cr_i);
    Chromosome crossover_binomial(const Chromosome& target,
                                  const Chromosome& mutant, double cr);
    void       repair(Chromosome& c);

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

    std::vector<double> success_f_;
    std::vector<double> success_cr_;
    int    success_count_    = 0;
    int    trial_count_      = 0;
    int    zero_success_streak_ = 0;

    void reinitialize_worst();
    void evaluate(Chromosome& c);

    Term       random_term(bool denom);
    Regressor  random_regressor();
    Chromosome random_chromosome();
    void       structural_mutation(Chromosome& c);
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
    ~DifferentialEvolutionOptimizer() { stop(); }

    void initialize(
        const double* train_data, int train_rows,
        const double* val_data,   int val_rows,
        const double* test_data,  int test_rows,
        int cols, int output_col,
        const FitnessWeights& weights = FitnessWeights()
    );

    /** Run asynchronously in a background thread (native only). */
    void run_async(ProgressCallback on_progress, ShouldStopFn should_stop);

    /** Run up to n generations synchronously in the calling thread. */
    int run_steps(int n, ProgressCallback on_progress,
                  ShouldStopFn should_stop = nullptr);

    bool is_done() const;
    void stop();
    void wait();

    /** Canonical champion (full validation, reference weights). */
    Chromosome best_chromosome() const;

    /** Apply tuning at runtime (thread-safe). Returns false for unknown names. */
    bool apply_tuning(const std::string& param, double value);
    /** Current value of a tunable (NaN if unknown). */
    double tuning_value(const std::string& param) const;

    void update_weights(const FitnessWeights& w);
    FitnessWeights current_weights() const;
    void update_search_space(double pmax, int max_delay);
    void update_weights_for_island(int idx, const FitnessWeights& w);
    /** Weights of the canonical (champion-selection) evaluator. */
    void set_canonical_weights(const FitnessWeights& w);
    void set_island_validation_window(int idx, const double* val_data, int val_rows);
    void set_island_role(int idx, const std::string& name);
    void trigger_restart(double ratio);
    void inject_migrant(const Chromosome& c);

    long long evaluations() const;
    std::vector<IslandReport> island_reports() const;
    int generation() const { return current_gen_.load(); }
    std::string stop_reason() const;
    DEConfig config() const;

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

    // Canonical champion selection
    IndividualEvaluator canonical_eval_;
    Chromosome          champion_;
    bool                champion_valid_ = false;
    std::unordered_map<uint64_t, Chromosome> canonical_cache_;
    ModelDiagnostics    champion_diag_;
    uint64_t            champion_diag_hash_ = 0;

    // Progress / stopping (generation-level)
    std::atomic<int> current_gen_{0};
    int    global_stagnation_ = 0;
    double prev_best_         = std::numeric_limits<double>::infinity();
    std::string stop_reason_;
    bool   done_ = false;

    /** One full generation (islands, migration, champion, report). Lock held inside. */
    GenerationReport step_generation_locked();
    void migrate();
    void update_champion_locked();
    Chromosome canonical_evaluate_locked(const Chromosome& c);
    GenerationReport build_report_locked();
    bool check_stop_locked();
};

} // namespace aegis
