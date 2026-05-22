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

namespace aegis {

/** Full pipeline configuration (matches aegis_configure JSON keys). */
struct PipelineConfig {
    // Data
    NormalizerType normalizer_type = NormalizerType::MinMax;
    double         norm_lo         = 1e-6;
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

    // Background thread for pause/resume
    std::thread     worker_thread_;
    std::atomic<bool> pause_flag_{false};
    std::mutex        pause_mutex_;
    std::condition_variable pause_cv_;

    void worker_loop();
    void split_data();
    bool setup_agent();
    bool handle_suggestion(const AgentSuggestion& s, TuningLogEntry& entry);
};

} // namespace aegis
