#pragma once
#include "normalizer.hpp"
#include "de_optimizer.hpp"
#include "local_refiner.hpp"
#include "agent_controller.hpp"
#include "overfitting_detector.hpp"
#include "underfitting_detector.hpp"
#include "automatic_pruner.hpp"
#include "excitation_analyzer.hpp"
#include <string>
#include <memory>
#include <atomic>
#include <condition_variable>

namespace aegis {

/**
 * AEGIS Curriculum: staged identification phases. The "reflex layer"
 * (deterministic, runs every generation in IdentificationPipeline) advances
 * through these phases automatically based on indicator thresholds and
 * stagnation, adjusting FitnessWeights and search-space bounds for each
 * island without requiring an LLM round-trip.
 */
enum class IdentificationPhase : int {
    StructuralExploration = 0, // narrow search space, favor models that use inputs
    NonlinearExpansion    = 1, // full pmax/max_delay, free-run penalty ramps in
    ParsimonyValidation   = 2, // complexity/free-run penalties at full strength
    LocalRefinement       = 3, // fine-tuning: reduced mutation, max penalties
};

/** Human-readable phase name (for logs and UI). */
const char* phase_name(IdentificationPhase p);

/**
 * Island specialization roles ("objective x regime grid"). Each island is
 * assigned a FitnessWeights profile on top of the current curriculum phase,
 * plus (when enough validation data is available) a non-contiguous
 * validation fold ("regime"). Migration between islands acts as a two-layer
 * filter: a migrant must survive reevaluation under the destination's
 * weights+regime before being accepted, naturally discarding solutions that
 * are only good in their original objective/regime ("regional trivial
 * solutions").
 */
enum class IslandRole : int {
    Balanced        = 0, // unchanged curriculum weights (reference role)
    Parsimony       = 1, // stronger complexity/no-input pressure
    FreeRunFidelity = 2, // stronger free-run penalty, relaxed complexity
    Stability       = 3, // stronger stability/denominator pressure
};

/** Human-readable island role name (for logs and UI). */
const char* island_role_name(IslandRole r);

/** Full pipeline configuration (matches aegis_configure JSON keys). */
struct PipelineConfig {
    // Data
    NormalizerType normalizer_type = NormalizerType::MinMax;
    double         norm_lo         = -1.0;
    double         norm_hi         = 1.0;
    double         train_ratio     = 0.70;
    double         val_ratio       = 0.15;
    int            output_col      = -1;  // -1 = last column

    // DE
    DEConfig       de;

    // Refiner
    RefineConfig   refine;
    bool           enable_refiner  = true;

    // Pruner
    AutomaticPruner::Config prune;
    bool           enable_pruner   = true;

    // Fitness weights
    FitnessWeights weights;

    // AEGIS Curriculum (phased identification) tunables
    double free_run_penalty       = 0.5;  // target theta for late phases
    double input_contribution_min = 0.3;  // min input ERR share to leave Phase 1
    double gamma_anneal_start     = 0.01; // complexity penalty at generation 0
    double gamma_anneal_end       = 0.1;  // complexity penalty at max_generations
    int    phase_stagnation_limit = 150;  // stagnation generations to force a phase advance

    // Agent WebSocket
    int            ws_port         = 8765;
    bool           enable_ws       = true;

    /** Parse from JSON string. Returns false on parse error. */
    bool from_json(const std::string& json);

    /** Serialize to JSON string. */
    std::string to_json() const;
};

enum class PipelineState { Idle, Running, Paused, Stopped, Completed, Error };

/** Converts PipelineState to string. */
const char* pipeline_state_str(PipelineState s);

/**
 * Top-level AEGIS identification pipeline.
 *
 * Thread model:
 *   - The caller owns the pipeline object.
 *   - start() launches a background thread running DE + refiner.
 *   - The WebSocket server runs in its own threads (one accept + one per client).
 *   - stop()/pause()/resume() are thread-safe.
 */
class IdentificationPipeline {
public:
    IdentificationPipeline();
    ~IdentificationPipeline();

    // Non-copyable, non-movable
    IdentificationPipeline(const IdentificationPipeline&) = delete;
    IdentificationPipeline& operator=(const IdentificationPipeline&) = delete;

    /**
     * Load raw data matrix (row-major, rows × cols).
     * Data is copied internally.
     */
    bool load_data(const double* data, int rows, int cols);

    /** Configure the pipeline. Must be called before start(). */
    bool configure(const std::string& json_config);

    /** Start asynchronous identification (native) or initialize sync state (WASM). */
    bool start();

    /**
     * Run up to n DE generations synchronously (WASM / single-thread path).
     * Called repeatedly from Dart polling timer instead of run_async.
     * Returns generations run; 0 when engine is done or not running.
     */
    int step(int n = 5);

    /** Pause the running identification. */
    void pause();

    /** Resume after pause. */
    void resume();

    /** Stop gracefully. */
    void stop();

    // ── Status ──────────────────────────────────────────────────

    PipelineState state() const { return state_.load(); }
    int           generation()  const { return generation_.load(); }
    double        best_fitness()const { return best_fitness_.load(); }

    std::string   status_json() const;
    std::string   best_model_json() const;
    std::string   snapshot_json() const;

    // ── Agent tuning (thread-safe) ───────────────────────────────

    int  apply_tuning(const std::string& param, double value,
                      const std::string& reason);
    std::string tuning_log_json() const;

private:
    PipelineConfig              cfg_;
    std::atomic<PipelineState>  state_{PipelineState::Idle};
    std::atomic<int>            generation_{0};
    std::atomic<double>         best_fitness_{std::numeric_limits<double>::infinity()};

    // Owned data (raw + normalized splits)
    std::vector<double> raw_data_;
    int raw_rows_ = 0, raw_cols_ = 0;

    std::vector<double> train_data_, val_data_, test_data_;
    int train_rows_ = 0, val_rows_ = 0, test_rows_ = 0;

    // Engine
    std::unique_ptr<Normalizer>                      normalizer_;
    std::unique_ptr<DifferentialEvolutionOptimizer>  de_;
    std::unique_ptr<LocalRefiner>                    refiner_;
    std::unique_ptr<AutomaticPruner>                 pruner_;
    std::unique_ptr<AgentController>                 agent_;

    // Latest results (protected by results_mutex_)
    mutable std::mutex results_mutex_;
    Chromosome         best_chromosome_;
    GenerationReport   latest_report_;
    std::vector<TuningLogEntry> tuning_log_;

    // ── AEGIS Curriculum phase manager (deterministic "reflex" layer) ────
    std::atomic<int>   phase_{0};
    double             last_gamma_applied_ = 0.0;

    // ── Specialized islands (objective x regime grid) ─────────────────────
    std::vector<IslandRole> island_roles_;

    // Background thread for pause/resume
    std::thread     worker_thread_;
    // Periodically refreshes best_chromosome_ while running, so the Results
    // tab can show the currently converging model (not just the final one).
    std::thread     results_refresh_thread_;
    std::atomic<bool> pause_flag_{false};
    std::mutex        pause_mutex_;
    std::condition_variable pause_cv_;

    void worker_loop();
    void split_data();
    bool setup_agent();
    bool handle_suggestion(const AgentSuggestion& s, TuningLogEntry& entry);
    /** Evaluate best_chromosome_ on the held-out test split (rmse_test/r2_test). */
    void compute_test_metrics();

    /** FitnessWeights profile for a given phase + annealed gamma. */
    FitnessWeights phase_weights(IdentificationPhase phase, double gamma) const;
    /** Apply an island's role specialization on top of the phase profile. */
    FitnessWeights apply_role_profile(FitnessWeights w, IslandRole role) const;
    /** Reflex layer: advance phases and log transitions. Mutates rpt.phase/phase_name. */
    void update_phase(GenerationReport& rpt);
};

} // namespace aegis
