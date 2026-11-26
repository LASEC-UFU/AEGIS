#pragma once
#include "normalizer.hpp"
#include "de_optimizer.hpp"
#include "local_refiner.hpp"
#include "agent_controller.hpp"
#include "automatic_pruner.hpp"
#include "model_io.hpp"
#include <string>
#include <memory>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <map>

namespace aegis {

/**
 * AEGIS Curriculum: staged identification phases. The deterministic "reflex
 * layer" advances phases from indicator thresholds and stagnation, adjusting
 * FitnessWeights and the search space. Can be disabled (curriculum=false).
 */
enum class IdentificationPhase : int {
    StructuralExploration = 0,
    NonlinearExpansion    = 1,
    ParsimonyValidation   = 2,
    LocalRefinement       = 3,
};

const char* phase_name(IdentificationPhase p);
const char* phase_name_int(int p);

/** Island specialization roles (objective × regime grid). */
enum class IslandRole : int {
    Balanced        = 0,
    Parsimony       = 1,
    FreeRunFidelity = 2,
    Stability       = 3,
};

const char* island_role_name(IslandRole r);

/** Full pipeline configuration (matches aegis_configure JSON keys). */
struct PipelineConfig {
    // Data / splits
    NormalizerType normalizer_type = NormalizerType::MinMax;
    double         norm_lo         = -1.0;
    double         norm_hi         = 1.0;
    double         train_ratio     = 0.70;
    double         val_ratio       = 0.15;
    int            train_end_row   = -1;  // index mode (overrides ratios when ≥ 0)
    int            val_end_row     = -1;
    int            test_start_row  = -1;  // default: val_end_row (contiguous)
    int            test_transient  = 0;   // extra samples skipped at test start when scoring
    int            output_col      = -1;  // -1 = last column
    std::string    dataset_name;

    // DE
    DEConfig       de;

    // Post-processing
    RefineConfig   refine;
    bool           enable_refiner  = true;
    bool           final_refine_simulation = false; // P6: final champion refinement by free-run error
    bool           post_process_guard = false;      // accept post-processing only if reported validation does not worsen
    bool           enable_pruner   = true;
    AutomaticPruner::Config prune;

    // Fitness weights (base values; phases and island roles derive from them)
    FitnessWeights weights;

    // Curriculum
    bool   curriculum             = true;
    double free_run_penalty       = 0.5;
    double input_contribution_min = 0.3;
    double gamma_anneal_start     = 0.01;
    double gamma_anneal_end       = 0.1;
    int    phase_stagnation_limit = 150;
    double initial_pmax           = 1.5;
    double initial_delay_fraction = 0.5;

    // Islands
    bool   island_roles   = true;
    bool   island_regimes = true;

    // Agent interface
    int    ws_port                 = 0;     // 0 disables the WebSocket server
    bool   enable_ws               = false;
    bool   agent_actions_enabled   = true;
    bool   allow_budget_actions    = false; // stagnationLimit changes stopping → off by default
    int    action_cooldown         = 10;    // generations between changes of the same parameter
    int    outcome_horizon         = 25;    // generations used to score an action
    int    broadcast_interval      = 1;     // WebSocket broadcast every N generations

    // Execution
    bool   sync_mode               = false; // lockstep: generations only advance via aegis_step()
    int    history_stride          = 1;     // store every N-th generation in the history

    bool from_json(const std::string& json, std::string* error, std::vector<std::string>* warnings);
    std::string to_json() const;
};

enum class PipelineState { Idle, Running, Paused, Stopped, Completed, Error };

const char* pipeline_state_str(PipelineState s);

/** Compact state digest used for action pre/post comparison. */
struct StateDigest {
    int    generation = 0;
    long long evaluations = 0;
    int    phase = 0;
    double best_fitness = std::numeric_limits<double>::quiet_NaN();
    double rmse_val = std::numeric_limits<double>::quiet_NaN();
    double rmse_train = std::numeric_limits<double>::quiet_NaN();
    double free_run_rmse = std::numeric_limits<double>::quiet_NaN();
    double free_run_val_full = std::numeric_limits<double>::quiet_NaN();
    double diversity = std::numeric_limits<double>::quiet_NaN();
    double success_rate = std::numeric_limits<double>::quiet_NaN();
    int    stagnation = 0;
    int    unique_structures = 0;
    int    num_regressors = 0;
    std::string to_json() const;
};

/** One agent action (accepted or rejected) and its observed outcome. */
struct ActionRecord {
    int         id = 0;
    std::string source;          // "local-ucb1", "llm", "fuzzy", "websocket", "ui", "reflex", ...
    std::string param;
    std::string reason;
    std::string request_json;    // original request (as received)
    double      requested = std::numeric_limits<double>::quiet_NaN();
    double      old_value = std::numeric_limits<double>::quiet_NaN();
    double      new_value = std::numeric_limits<double>::quiet_NaN();
    double      effective_value = std::numeric_limits<double>::quiet_NaN(); // canonical weight after phase rules
    bool        accepted = false;
    std::string code;            // "accepted" | rejection code
    std::string message;
    int         generation_received = 0;
    int         generation_applied  = -1;
    StateDigest pre;
    StateDigest post;
    bool        resolved = false;
    std::string outcome;         // improved | worsened | neutral | inconclusive | pending
    std::string outcome_note;
    double      pre_trend = std::numeric_limits<double>::quiet_NaN();   // rel. rmse_val change in H gens before
    double      post_change = std::numeric_limits<double>::quiet_NaN(); // rel. rmse_val change in H gens after
    std::string to_json() const;
};

/** Specification of one agent-tunable parameter (published as schema). */
struct ActionSpec {
    std::string name;
    std::string kind;        // "de" | "weight" | "event"
    double min = 0.0, max = 1.0, max_step = 1.0;
    bool   integer = false;
    bool   budget = false;   // affects the evaluation budget / stopping
    int    cooldown = 10;
    std::string description;
};

/**
 * Top-level AEGIS identification pipeline.
 *
 * Thread model:
 *   - async mode: start() launches the DE worker thread; agent actions are
 *     validated immediately and applied by the worker at the next generation
 *     boundary (never mid-generation);
 *   - sync (lockstep) mode: generations advance only inside step(); actions
 *     are applied at the beginning of the next step;
 *   - the optional WebSocket server runs in its own threads and uses the
 *     same action interface.
 */
class IdentificationPipeline {
public:
    IdentificationPipeline();
    ~IdentificationPipeline();

    IdentificationPipeline(const IdentificationPipeline&) = delete;
    IdentificationPipeline& operator=(const IdentificationPipeline&) = delete;

    bool load_data(const double* data, int rows, int cols);
    bool configure(const std::string& json_config);
    bool start();
    int  step(int n = 5);
    void pause();
    void resume();
    void stop();

    PipelineState state() const { return state_.load(); }
    int           generation()  const { return generation_.load(); }
    double        best_fitness()const { return best_fitness_.load(); }

    std::string   status_json() const;
    std::string   best_model_json() const;
    std::string   snapshot_json() const;
    std::string   config_json() const;
    std::string   history_json() const;
    std::string   final_report_json() const;
    std::string   last_error() const;

    // ── Agent interface ─────────────────────────────────────────────
    /** Validate and (queue) one action; returns the result JSON. */
    std::string apply_action_json(const std::string& action_json);
    /** Legacy entry point: 0 accepted, 1 rejected, -1 unknown parameter. */
    int  apply_tuning(const std::string& param, double value, const std::string& reason,
                      const std::string& source = "legacy");
    std::string tuning_log_json() const;   // all action records
    std::string action_schema_json() const;
    void set_agent_enabled(bool enabled);
    bool agent_enabled() const { return agent_enabled_.load(); }

    /** Evaluate an external model JSON on this pipeline's data and splits. */
    std::string evaluate_model_json(const std::string& model_json, bool refit);

    bool inject_individual(const std::string& json);

private:
    PipelineConfig              cfg_;
    std::atomic<PipelineState>  state_{PipelineState::Idle};
    std::atomic<int>            generation_{0};
    std::atomic<double>         best_fitness_{std::numeric_limits<double>::infinity()};
    std::atomic<bool>           agent_enabled_{true};
    std::atomic<bool>           finalized_{false};

    std::vector<double> raw_data_;
    int raw_rows_ = 0, raw_cols_ = 0;
    std::string data_hash_;

    // Normalized full series + split boundaries
    std::vector<double> norm_data_;
    int train_end_ = 0, val_end_ = 0, test_start_ = 0;
    std::vector<double> train_data_, val_data_;
    int train_rows_ = 0, val_rows_ = 0;

    std::unique_ptr<Normalizer>                      normalizer_;
    std::unique_ptr<DifferentialEvolutionOptimizer>  de_;
    std::unique_ptr<AgentController>                 ws_;

    // Results
    mutable std::mutex results_mutex_;
    Chromosome         best_chromosome_;
    GenerationReport   latest_report_;
    std::vector<std::string> history_;      // compact per-generation JSON records
    std::deque<StateDigest>  recent_;       // last outcome_horizon+1 digests
    std::string        final_report_;
    std::string        last_error_;
    std::string        post_processing_log_;
    std::chrono::steady_clock::time_point t_start_;
    double             elapsed_s_ = 0.0;

    // Control (configuration, weights, actions)
    mutable std::mutex control_mutex_;
    std::vector<ActionRecord> actions_;
    std::vector<int>          pending_;     // indices into actions_ awaiting application
    std::map<std::string, int> last_change_gen_;
    std::vector<ActionSpec>   specs_;
    int                       next_action_id_ = 1;

    std::atomic<int>   phase_{0};
    std::vector<IslandRole> island_roles_;
    double             annealed_gamma_ = 0.01; // γ chosen by the curriculum at the last phase change
    double             gamma_override_ = -1.0; // ≥ 0 once an agent has set complexityPenalty
    double current_gamma_value() const;

    std::thread     worker_thread_;
    std::atomic<bool> shutdown_{false};

    void build_specs();
    const ActionSpec* find_spec(const std::string& name) const;
    double current_value_locked(const std::string& name) const;
    double effective_value_locked(const std::string& name) const;
    void   apply_pending_locked();
    void   apply_action_locked(ActionRecord& a);
    void   push_weights_locked();
    void   resolve_outcomes(const StateDigest& now, bool phase_changed);
    StateDigest digest(const GenerationReport& r) const;

    void prepare_data();
    void on_generation(const GenerationReport& report);
    bool before_generation();
    void finalize(const std::string& reason);
    void post_process(Chromosome& champ);

    FitnessWeights phase_weights(int phase, double gamma) const;
    FitnessWeights apply_role_profile(FitnessWeights w, IslandRole role) const;
    void update_phase(GenerationReport& rpt);
    void log_reflex(const std::string& param, double value, const std::string& reason, int gen);
    double divergence_bound() const;
    std::string segment_metrics_json(const Chromosome& c) const;
};

} // namespace aegis
