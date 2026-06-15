#include "aegis/identification_pipeline.hpp"
#include "aegis/metrics.hpp"
#include "aegis/rational_model.hpp"
#include "aegis/overfitting_detector.hpp"
#include "aegis/underfitting_detector.hpp"
#include "aegis/excitation_analyzer.hpp"
#include "aegis/residual_analyzer.hpp"
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <cstring>
#include <map>
#include <chrono>

namespace aegis {

// ── Helpers ────────────────────────────────────────────────────────────────

static std::string json_bool(bool v) { return v ? "true" : "false"; }
static std::string json_dbl(double v) {
    if (!std::isfinite(v)) return "null";
    std::ostringstream ss; ss << std::fixed << std::setprecision(8) << v;
    return ss.str();
}
static std::string json_arr(const std::vector<double>& v) {
    std::string s = "[";
    for (size_t i = 0; i < v.size(); ++i) { if(i) s+=","; s += json_dbl(v[i]); }
    return s + "]";
}

const char* phase_name(IdentificationPhase p) {
    switch (p) {
        case IdentificationPhase::StructuralExploration: return "structural_exploration";
        case IdentificationPhase::NonlinearExpansion:    return "nonlinear_expansion";
        case IdentificationPhase::ParsimonyValidation:   return "parsimony_validation";
        case IdentificationPhase::LocalRefinement:       return "local_refinement";
    }
    return "unknown";
}

const char* island_role_name(IslandRole r) {
    switch (r) {
        case IslandRole::Balanced:        return "balanced";
        case IslandRole::Parsimony:       return "parsimony";
        case IslandRole::FreeRunFidelity: return "free_run_fidelity";
        case IslandRole::Stability:       return "stability";
    }
    return "balanced";
}

const char* pipeline_state_str(PipelineState s) {
    switch (s) {
        case PipelineState::Idle:      return "idle";
        case PipelineState::Running:   return "running";
        case PipelineState::Paused:    return "paused";
        case PipelineState::Stopped:   return "stopped";
        case PipelineState::Completed: return "completed";
        case PipelineState::Error:     return "error";
    }
    return "unknown";
}

// ── PipelineConfig JSON parsing (minimal) ─────────────────────────────────

static void sync_report_best(GenerationReport& r, const Chromosome& best) {
    if (!best.evaluated) return;

    r.best_fitness = best.fitness;
    r.num_terms = best.num_regressors();
    r.best_contexts_survived = best.contexts_survived;
    r.best_worst_fitness_seen = best.worst_fitness_seen;
    r.rmse_train = best.metrics.rmse_train;
    r.rmse_val = best.metrics.rmse_val;
    r.rmse_test = best.metrics.rmse_test;
    r.bic = best.metrics.bic;
    r.aic = best.metrics.aic;
    r.r2_train = best.metrics.r2_train;
    r.r2_val = best.metrics.r2_val;
    r.free_run_rmse = best.metrics.rmse_free_run;
    r.input_contribution_ratio = best.metrics.input_contribution_ratio;
    r.residual_input_corr = best.metrics.residual_input_corr;
    r.fitness_breakdown = best.fitness_breakdown;
    r.best_coefficients = best.coefficients;
    r.best_intercept = best.intercept;
    r.best_exponents.clear();
    for (const auto& reg : best.regressors)
        for (const auto& term : reg.terms)
            r.best_exponents.push_back(term.exponent);
}

bool PipelineConfig::from_json(const std::string& json) {
    auto getd = [&](const std::string& key, double def) -> double {
        auto p = json.find("\"" + key + "\"");
        if (p == std::string::npos) return def;
        auto c = json.find(':', p);
        if (c == std::string::npos) return def;
        try { return std::stod(json.substr(c + 1)); }
        catch (...) { return def; }
    };
    auto geti = [&](const std::string& key, int def) -> int {
        return static_cast<int>(getd(key, def));
    };
    auto gets = [&](const std::string& key, const std::string& def) -> std::string {
        auto p = json.find("\"" + key + "\"");
        if (p == std::string::npos) return def;
        auto c = json.find(':', p);
        if (c == std::string::npos) return def;
        while (c < json.size() && json[c] != '"') ++c;
        if (c >= json.size()) return def;
        ++c;
        auto e = json.find('"', c);
        if (e == std::string::npos) return def;
        return json.substr(c, e - c);
    };

    std::string nt = gets("normalizerType", "minmax");
    if      (nt == "robust") normalizer_type = NormalizerType::RobustScaler;
    else if (nt == "zscore") normalizer_type = NormalizerType::ZScore;
    else                     normalizer_type = NormalizerType::MinMax;

    train_ratio      = getd("trainRatio",     0.70);
    val_ratio        = getd("validationRatio",0.15);
    output_col       = geti("outputCol",     -1);
    ws_port          = geti("webSocketPort",  8765);
    enable_ws        = ws_port > 0;

    de.num_islands      = geti("numIslands",       3);
    de.population_size  = geti("populationSize",  50);
    de.max_generations  = geti("maxGenerations",5000);
    de.stagnation_limit = geti("stagnationLimit", 500);
    de.mu_f             = getd("mutationFactor",  0.5);
    de.mu_cr            = getd("crossoverRate",   0.9);
    de.elitism_count    = geti("elitismCount",      2);
    de.migration_interval=geti("migrationInterval",20);
    de.migration_rate   = getd("migrationRate",  0.1);
    de.reinit_ratio     = getd("reinitializationRatio", 0.1);
    de.max_regressors   = geti("maxRegressors",    8);
    de.max_terms_per_reg= geti("maxTermsPerReg",   3);
    de.pmin             = getd("pmin",            0.5);
    de.pmax             = getd("pmax",            5.0);
    de.max_delay        = geti("maxDelay",         40);
    de.num_threads      = geti("numThreads",        0);
    de.random_seed      = static_cast<uint64_t>(getd("randomSeed", 0));

    weights.alpha = getd("alpha",          0.05);
    weights.beta  = getd("denominatorPenalty", 0.1);
    weights.gamma = getd("complexityPenalty",0.01);
    weights.delta = getd("exponentPenalty",  0.01);
    weights.eta   = getd("stabilityPenalty",  1.0);
    weights.zeta  = getd("noInputPenalty",    0.5);
    weights.theta = getd("freeRunPenalty",    0.0);
    weights.free_run_horizon = geti("freeRunHorizon", 50);

    free_run_penalty       = getd("freeRunPenalty",       0.5);
    input_contribution_min = getd("inputContributionMin", 0.3);
    weights.input_contribution_target = input_contribution_min;
    gamma_anneal_start     = getd("gammaAnnealStart",      weights.gamma);
    gamma_anneal_end       = getd("gammaAnnealEnd",        std::max(weights.gamma, 0.1));
    phase_stagnation_limit = geti("phaseStagnationLimit",  150);
    return true;
}

std::string PipelineConfig::to_json() const {
    std::ostringstream j;
    j << std::fixed << std::setprecision(4);
    j << "{\"normalizerType\":\"" << (normalizer_type==NormalizerType::MinMax?"minmax":
                                      normalizer_type==NormalizerType::RobustScaler?"robust":"zscore")
      << "\",\"trainRatio\":"       << train_ratio
      << ",\"validationRatio\":"    << val_ratio
      << ",\"outputCol\":"          << output_col
      << ",\"numIslands\":"         << de.num_islands
      << ",\"populationSize\":"     << de.population_size
      << ",\"maxGenerations\":"     << de.max_generations
      << ",\"stagnationLimit\":"    << de.stagnation_limit
      << ",\"mutationFactor\":"     << de.mu_f
      << ",\"crossoverRate\":"      << de.mu_cr
      << ",\"maxRegressors\":"      << de.max_regressors
      << ",\"maxDelay\":"           << de.max_delay
      << ",\"pmin\":"               << de.pmin
      << ",\"pmax\":"               << de.pmax
      << "}";
    return j.str();
}

// ── IdentificationPipeline ────────────────────────────────────────────────

IdentificationPipeline::IdentificationPipeline() = default;

IdentificationPipeline::~IdentificationPipeline() {
    stop();
    if (agent_) agent_->stop();
}

bool IdentificationPipeline::load_data(const double* data, int rows, int cols) {
    if (!data || rows <= 0 || cols <= 0) return false;
    raw_data_.assign(data, data + (size_t)rows * cols);
    raw_rows_ = rows;
    raw_cols_ = cols;
    return true;
}

bool IdentificationPipeline::configure(const std::string& json_config) {
    if (!cfg_.from_json(json_config) || raw_cols_ <= 0) return false;
    if (cfg_.output_col < 0) cfg_.output_col = raw_cols_ - 1;
    if (cfg_.output_col < 0 || cfg_.output_col >= raw_cols_) return false;
    if (cfg_.train_ratio <= 0.0 || cfg_.val_ratio < 0.0 ||
        cfg_.train_ratio + cfg_.val_ratio >= 1.0) return false;

    cfg_.de.num_islands = std::clamp(cfg_.de.num_islands, 1, 16);
    cfg_.de.population_size = std::clamp(cfg_.de.population_size, 4, 500);
    cfg_.de.elitism_count = std::clamp(
        cfg_.de.elitism_count, 0, cfg_.de.population_size - 1
    );
    cfg_.de.max_regressors = std::clamp(cfg_.de.max_regressors, 1, 30);
    cfg_.de.max_terms_per_reg = std::clamp(cfg_.de.max_terms_per_reg, 1, 5);
    cfg_.de.max_delay = std::clamp(cfg_.de.max_delay, 1, 200);
    cfg_.de.pmin = std::max(0.1, cfg_.de.pmin);
    cfg_.de.pmax = std::max(cfg_.de.pmin, cfg_.de.pmax);
    cfg_.de.mu_f = std::clamp(cfg_.de.mu_f, 0.01, 2.0);
    cfg_.de.mu_cr = std::clamp(cfg_.de.mu_cr, 0.0, 1.0);
    cfg_.de.migration_rate = std::clamp(cfg_.de.migration_rate, 0.0, 1.0);
    cfg_.de.migration_interval = std::max(1, cfg_.de.migration_interval);
    cfg_.de.max_generations = std::max(1, cfg_.de.max_generations);
    cfg_.de.stagnation_limit = std::max(1, cfg_.de.stagnation_limit);
    cfg_.de.reinit_ratio = std::clamp(cfg_.de.reinit_ratio, 0.0, 1.0);
    cfg_.weights.alpha = std::max(0.0, cfg_.weights.alpha);
    cfg_.weights.beta = std::max(0.0, cfg_.weights.beta);
    cfg_.weights.gamma = std::max(0.0, cfg_.weights.gamma);
    cfg_.weights.delta = std::max(0.0, cfg_.weights.delta);
    cfg_.weights.eta = std::max(0.0, cfg_.weights.eta);
    cfg_.weights.zeta = std::max(0.0, cfg_.weights.zeta);
    cfg_.weights.theta = std::max(0.0, cfg_.weights.theta);
    cfg_.weights.free_run_horizon = std::max(1, cfg_.weights.free_run_horizon);
    cfg_.input_contribution_min = std::clamp(cfg_.input_contribution_min, 0.0, 1.0);
    cfg_.weights.input_contribution_target = cfg_.input_contribution_min;
    cfg_.free_run_penalty = std::max(0.0, cfg_.free_run_penalty);
    cfg_.gamma_anneal_start = std::max(0.0, cfg_.gamma_anneal_start);
    cfg_.gamma_anneal_end = std::max(0.0, cfg_.gamma_anneal_end);
    cfg_.phase_stagnation_limit = std::max(2, cfg_.phase_stagnation_limit);
    cfg_.de.num_variables = raw_cols_;
    return true;
}

void IdentificationPipeline::split_data() {
    if (raw_data_.empty()) return;
    int n = raw_rows_;
    int n_train = static_cast<int>(n * cfg_.train_ratio);
    int n_val   = static_cast<int>(n * cfg_.val_ratio);
    int n_test  = n - n_train - n_val;

    train_rows_ = n_train;
    val_rows_   = std::max(0, n_val);
    test_rows_  = std::max(0, n_test);

    const int cols = raw_cols_;
    train_data_.assign(raw_data_.begin(),
                       raw_data_.begin() + (size_t)n_train * cols);
    if (val_rows_ > 0)
        val_data_.assign(raw_data_.begin() + (size_t)n_train * cols,
                         raw_data_.begin() + (size_t)(n_train + n_val) * cols);
    if (test_rows_ > 0)
        test_data_.assign(raw_data_.begin() + (size_t)(n_train + n_val) * cols,
                          raw_data_.end());
}

bool IdentificationPipeline::setup_agent() {
    if (!cfg_.enable_ws) return true;
    agent_ = std::make_unique<AgentController>(cfg_.ws_port);
    agent_->on_suggestion([this](const AgentSuggestion& s, TuningLogEntry& entry) -> bool {
        return handle_suggestion(s, entry);
    });
    return agent_->start();
}

bool IdentificationPipeline::handle_suggestion(
    const AgentSuggestion& s, TuningLogEntry& entry
) {
    entry.param_name = s.param_name;
    entry.new_value  = s.proposed_value;
    entry.reason     = s.reason;
    entry.generation = generation_.load();

    // Validate
    static const std::map<std::string, std::pair<double,double>> limits = {
        {"mutationFactor",     {0.0, 2.0}},
        {"crossoverRate",      {0.0, 1.0}},
        {"migrationRate",      {0.0, 0.5}},
        {"migrationInterval",  {5,   200}},
        {"stagnationLimit",    {50,  5000}},
        {"reinitializationRatio", {0.0, 0.5}},
        {"complexityPenalty",  {0.0, 1.0}},
        {"noInputPenalty",     {0.0, 2.0}},
        {"freeRunPenalty",     {0.0, 2.0}},
        {"denominatorPenalty", {0.0, 1.0}},
        {"stabilityPenalty",   {0.0, 2.0}},
        {"exponentPenalty",    {0.0, 1.0}},
        {"alpha",              {0.0, 2.0}},
        {"freeRunHorizon",     {10,  500}},
    };
    auto it = limits.find(s.param_name);
    if (it == limits.end()) {
        entry.rejection_reason = "Unknown parameter: " + s.param_name;
        return false;
    }
    double lo = it->second.first, hi = it->second.second;
    if (s.proposed_value < lo || s.proposed_value > hi) {
        std::ostringstream ss;
        ss << "Value " << s.proposed_value << " out of range ["
           << lo << "," << hi << "]";
        entry.rejection_reason = ss.str();
        return false;
    }

    // Apply to DE
    if (de_) de_->apply_tuning(s.param_name, s.proposed_value);
    entry.accepted = true;
    return true;
}

// ── AEGIS Curriculum: phase manager (deterministic reflex layer) ──────────

FitnessWeights IdentificationPipeline::phase_weights(
    IdentificationPhase phase, double gamma
) const {
    FitnessWeights w = cfg_.weights;
    w.gamma = gamma;
    switch (phase) {
        case IdentificationPhase::StructuralExploration:
            // Strongly discourage purely-autoregressive models so the
            // population is forced to explore input-dependent structures
            // before any nonlinear / free-run penalties kick in.
            w.zeta  = std::max(cfg_.weights.zeta, 5.0);
            w.theta = 0.0;
            break;
        case IdentificationPhase::NonlinearExpansion:
            // Relax the input-usage pressure and start ramping in the
            // free-run penalty as candidate structures gain nonlinear terms.
            w.zeta  = std::max(cfg_.weights.zeta * 0.6, 2.0);
            w.theta = cfg_.free_run_penalty * 0.5;
            break;
        case IdentificationPhase::ParsimonyValidation:
            // Full free-run penalty: candidates must remain accurate under
            // simulation, not just one-step-ahead prediction.
            w.zeta  = std::max(cfg_.weights.zeta, 1.0);
            w.theta = cfg_.free_run_penalty;
            break;
        case IdentificationPhase::LocalRefinement:
            // Final polishing: maximum pressure for parsimony and
            // simulation accuracy.
            w.zeta  = std::max(cfg_.weights.zeta, 1.0);
            w.theta = cfg_.free_run_penalty * 1.5;
            break;
    }
    return w;
}

FitnessWeights IdentificationPipeline::apply_role_profile(
    FitnessWeights w, IslandRole role
) const {
    switch (role) {
        case IslandRole::Parsimony:
            // Stronger pressure for compact, input-driven models.
            w.gamma *= 2.0;
            w.zeta  *= 1.5;
            break;
        case IslandRole::FreeRunFidelity:
            // Prioritize long-horizon simulation accuracy over parsimony.
            w.theta = std::max(w.theta, 0.15);
            w.gamma *= 0.7;
            break;
        case IslandRole::Stability:
            // Prioritize a well-conditioned, stable rational model.
            w.eta  *= 1.6;
            w.beta *= 1.4;
            break;
        case IslandRole::Balanced:
        default:
            break; // reference profile, unchanged
    }
    return w;
}

void IdentificationPipeline::update_phase(GenerationReport& rpt) {
    if (!de_) return;

    auto cur = static_cast<IdentificationPhase>(phase_.load());

    // Select the complexity pressure for the next phase from run progress.
    // The value remains fixed until another phase transition.
    double progress = cfg_.de.max_generations > 0
        ? std::clamp(static_cast<double>(rpt.generation) / cfg_.de.max_generations, 0.0, 1.0)
        : 0.0;
    double gamma = cfg_.gamma_anneal_start +
                    (cfg_.gamma_anneal_end - cfg_.gamma_anneal_start) * progress;

    IdentificationPhase next = cur;
    std::string reason;

    switch (cur) {
        case IdentificationPhase::StructuralExploration:
            if (std::isfinite(rpt.input_contribution_ratio) &&
                rpt.input_contribution_ratio >= cfg_.input_contribution_min &&
                rpt.r2_train > 0.3) {
                next = IdentificationPhase::NonlinearExpansion;
                reason = "input_contribution_ratio and r2_train thresholds reached";
            } else if (rpt.stagnation >= cfg_.phase_stagnation_limit) {
                next = IdentificationPhase::NonlinearExpansion;
                reason = "stagnation limit reached (forced advance)";
            }
            break;
        case IdentificationPhase::NonlinearExpansion:
            if (rpt.stagnation >= cfg_.phase_stagnation_limit / 2) {
                next = IdentificationPhase::ParsimonyValidation;
                reason = "nonlinear search stagnated";
            }
            break;
        case IdentificationPhase::ParsimonyValidation:
            if (rpt.stagnation >= cfg_.phase_stagnation_limit) {
                next = IdentificationPhase::LocalRefinement;
                reason = "parsimony search stagnated";
            }
            break;
        case IdentificationPhase::LocalRefinement:
            // Terminal phase, but not passive: if the search is still
            // stagnant after reaching maximal refinement pressure, fall
            // back to a broad restart (large-fraction random immigrants +
            // JADE reset) every phase_stagnation_limit generations, instead
            // of just idling until the global stagnation limit halts the
            // run.
            if (rpt.stagnation > 0 && rpt.stagnation % cfg_.phase_stagnation_limit == 0) {
                de_->trigger_restart(0.3);
                TuningLogEntry entry;
                entry.accepted   = true;
                entry.param_name = "restart";
                entry.new_value  = 0.3;
                entry.reason     = "AEGIS reflex: LocalRefinement stagnated again "
                                    "-> broad restart (random immigrants + JADE reset)";
                entry.generation = rpt.generation;
                std::lock_guard<std::mutex> lk(results_mutex_);
                tuning_log_.push_back(entry);
            }
            break;
    }

    bool phase_changed = next != cur;

    // Keep one objective scale within each phase. Continuously changing
    // gamma makes stagnation and greedy selection compare different goals.
    if (phase_changed) {
        FitnessWeights base = phase_weights(next, gamma);
        for (int i = 0; i < (int)island_roles_.size(); ++i)
            de_->update_weights_for_island(i, apply_role_profile(base, island_roles_[i]));
        last_gamma_applied_ = gamma;

        if (phase_changed) {
            phase_.store(static_cast<int>(next));

            if (next == IdentificationPhase::NonlinearExpansion) {
                // Open up the search space to its full configured bounds.
                de_->update_search_space(cfg_.de.pmax, cfg_.de.max_delay);
            } else if (next == IdentificationPhase::LocalRefinement) {
                // Reduce mutation strength for fine-tuning around good optima.
                de_->apply_tuning("mutationFactor", std::max(0.1, cfg_.de.mu_f * 0.5));
            }

            TuningLogEntry entry;
            entry.accepted   = true;
            entry.param_name = "phase";
            entry.new_value  = static_cast<double>(next);
            entry.reason     = std::string("AEGIS reflex: ") + reason +
                               " -> " + phase_name(next);
            entry.generation = rpt.generation;
            {
                std::lock_guard<std::mutex> lk(results_mutex_);
                tuning_log_.push_back(entry);
            }
        }
    }

    rpt.phase      = phase_.load();
    rpt.phase_name = phase_name(static_cast<IdentificationPhase>(rpt.phase));
}

bool IdentificationPipeline::start() {
    const auto current_state = state_.load();
    if (current_state == PipelineState::Running ||
        current_state == PipelineState::Paused) return false;
    if (raw_data_.empty()) return false;
    const int configured_train_rows =
        static_cast<int>(raw_rows_ * cfg_.train_ratio);
    if (configured_train_rows <= cfg_.de.max_delay) {
        state_.store(PipelineState::Error);
        return false;
    }

    // Join any previous run's threads before discarding de_/agent_
    if (de_) de_->stop();
    if (worker_thread_.joinable()) worker_thread_.join();
    if (results_refresh_thread_.joinable()) results_refresh_thread_.join();
    if (agent_) agent_.reset();

    generation_.store(0);
    best_fitness_.store(std::numeric_limits<double>::infinity());
    phase_.store(static_cast<int>(IdentificationPhase::StructuralExploration));
    {
        std::lock_guard<std::mutex> lk(results_mutex_);
        best_chromosome_ = Chromosome();
        latest_report_ = GenerationReport();
        latest_report_.phase_name =
            phase_name(IdentificationPhase::StructuralExploration);
        tuning_log_.clear();
    }
    state_.store(PipelineState::Running);

    // Normalise and split
    normalizer_ = std::make_unique<Normalizer>(
        cfg_.normalizer_type, cfg_.norm_lo, cfg_.norm_hi
    );
    // Fit on training portion
    int n_train = static_cast<int>(raw_rows_ * cfg_.train_ratio);
    normalizer_->fit(raw_data_.data(), n_train, raw_cols_);
    // Normalise full dataset
    std::vector<double> norm_data = raw_data_;
    normalizer_->transform(norm_data.data(), raw_rows_, raw_cols_);
    // Patch raw_data_ with normalised version for splitting
    std::swap(raw_data_, norm_data);
    split_data();
    std::swap(raw_data_, norm_data); // restore original

    DEConfig initial_de = cfg_.de;
    initial_de.pmax = std::min(cfg_.de.pmax, 1.5);
    initial_de.max_delay = std::max(
        1, std::min(cfg_.de.max_delay, std::max(5, cfg_.de.max_delay / 2))
    );
    FitnessWeights initial_weights = phase_weights(
        IdentificationPhase::StructuralExploration, cfg_.gamma_anneal_start
    );

    de_ = std::make_unique<DifferentialEvolutionOptimizer>(initial_de);
    de_->initialize(
        train_data_.data(), train_rows_,
        val_rows_ > 0 ? val_data_.data() : nullptr, val_rows_,
        test_rows_ > 0 ? test_data_.data() : nullptr, test_rows_,
        raw_cols_, cfg_.output_col, initial_weights
    );

    // ── Merged disruptive idea: specialized islands (objective x regime) ──
    // Each island gets a FitnessWeights role profile on top of the
    // curriculum phase, plus (when enough validation data exists) a
    // non-contiguous validation fold ("regime"). Migration later acts as a
    // two-layer filter between these specialized islands.
    {
        const int n_islands = cfg_.de.num_islands;
        static const IslandRole role_cycle[4] = {
            IslandRole::Balanced, IslandRole::Parsimony,
            IslandRole::FreeRunFidelity, IslandRole::Stability
        };
        island_roles_.assign(n_islands, IslandRole::Balanced);
        for (int i = 0; i < n_islands; ++i) {
            IslandRole role = role_cycle[i % 4];
            island_roles_[i] = role;
            de_->set_island_role(i, island_role_name(role));
        }

        // Non-contiguous validation folds: split val_data_ into n_islands
        // chunks, each becomes one island's validation regime, with a
        // max_delay warm-up prefix so free-run simulation starts correctly.
        if (val_rows_ > 0 && n_islands > 0) {
            int chunk  = val_rows_ / n_islands;
            int warmup = cfg_.de.max_delay;
            if (chunk > warmup + 5) {
                for (int i = 0; i < n_islands; ++i) {
                    int start_row  = i * chunk;
                    int end_row    = (i == n_islands - 1) ? val_rows_ : (i + 1) * chunk;
                    int data_start = std::max(0, start_row - warmup);
                    int rows       = end_row - data_start;
                    const double* ptr = val_data_.data() +
                        static_cast<size_t>(data_start) * raw_cols_;
                    de_->set_island_validation_window(i, ptr, rows);
                }
            }
        }
    }

    // ── AEGIS Curriculum: Phase 1 (Structural Exploration) ──────────────
    // Start with a narrow search space (near-linear, short delays) and
    // strong pressure against pure-autoregressive structures.
    phase_.store(static_cast<int>(IdentificationPhase::StructuralExploration));
    last_gamma_applied_ = cfg_.gamma_anneal_start;
    {
        FitnessWeights base = phase_weights(IdentificationPhase::StructuralExploration, cfg_.gamma_anneal_start);
        for (int i = 0; i < (int)island_roles_.size(); ++i)
            de_->update_weights_for_island(i, apply_role_profile(base, island_roles_[i]));
    }
#ifndef __EMSCRIPTEN__
    setup_agent();

    de_->run_async(
        [this](const GenerationReport& report) {
            GenerationReport rpt = report;
            update_phase(rpt);

            Chromosome live = de_->best_chromosome();
            sync_report_best(rpt, live);
            generation_.store(rpt.generation);
            best_fitness_.store(rpt.best_fitness);
            {
                std::lock_guard<std::mutex> lk(results_mutex_);
                latest_report_ = rpt;
                if (live.evaluated) best_chromosome_ = std::move(live);
            }
            if (agent_) {
                agent_->broadcast(build_broadcast_json(rpt));
            }
        },
        [this]() -> bool {
            using namespace std::chrono_literals;
            while (state_.load() == PipelineState::Paused)
                std::this_thread::sleep_for(20ms);
            return state_.load() == PipelineState::Stopped;
        }
    );

    // Monitor in background thread for completion
    worker_thread_ = std::thread([this] {
        de_->wait();
        if (state_.load() == PipelineState::Running)
            state_.store(PipelineState::Completed);
        // Store final best
        {
            std::lock_guard<std::mutex> lk(results_mutex_);
            best_chromosome_ = de_->best_chromosome();
        }
        compute_test_metrics();
    });

    // Periodically refresh best_chromosome_ while running, so the Results
    // tab can display the currently converging model/equation, not just the
    // final one once the run completes.
    results_refresh_thread_ = std::thread([this] {
        using namespace std::chrono_literals;
        while (true) {
            std::this_thread::sleep_for(2s);
            auto st = state_.load();
            if (st == PipelineState::Stopped || st == PipelineState::Completed ||
                st == PipelineState::Error)
                break;
            if (st != PipelineState::Running) continue; // paused — wait it out

            Chromosome live = de_->best_chromosome();
            if (!live.evaluated) continue;
            {
                std::lock_guard<std::mutex> lk(results_mutex_);
                best_chromosome_ = live;
            }
            compute_test_metrics();
        }
    });
#endif // !__EMSCRIPTEN__

    return true;
}

int IdentificationPipeline::step(int n) {
    if (state_.load() != PipelineState::Running) return 0;
    if (!de_) return 0;

    int ran = de_->run_steps(n,
        [this](const GenerationReport& report) {
            GenerationReport rpt = report;
            update_phase(rpt);

            Chromosome live = de_->best_chromosome();
            sync_report_best(rpt, live);
            generation_.store(rpt.generation);
            best_fitness_.store(rpt.best_fitness);
            std::lock_guard<std::mutex> lk(results_mutex_);
            latest_report_ = rpt;
            if (live.evaluated) best_chromosome_ = std::move(live);
        },
        [this]() -> bool {
            auto s = state_.load();
            return s == PipelineState::Stopped || s == PipelineState::Paused;
        }
    );

    if (de_->is_done() && state_.load() == PipelineState::Running) {
        {
            std::lock_guard<std::mutex> lk(results_mutex_);
            best_chromosome_ = de_->best_chromosome();
        }
        compute_test_metrics();
        state_.store(PipelineState::Completed);
    }

    return ran;
}

void IdentificationPipeline::pause() {
    if (state_.load() == PipelineState::Running)
        state_.store(PipelineState::Paused);
}

void IdentificationPipeline::resume() {
    if (state_.load() == PipelineState::Paused)
        state_.store(PipelineState::Running);
}

void IdentificationPipeline::stop() {
    state_.store(PipelineState::Stopped);
    if (de_) de_->stop();
    if (worker_thread_.joinable()) worker_thread_.join();
    if (results_refresh_thread_.joinable()) results_refresh_thread_.join();
}

// ── Status JSON ───────────────────────────────────────────────────────────

std::string IdentificationPipeline::status_json() const {
    GenerationReport rpt;
    { std::lock_guard<std::mutex> lk(results_mutex_); rpt = latest_report_; }

    std::ostringstream j;
    j << "{"
      << "\"state\":\"" << pipeline_state_str(state_.load()) << "\","
      << "\"generation\":"   << generation_.load()              << ","
      << "\"bestFitness\":"  << json_dbl(best_fitness_.load())  << ","
      << "\"rmseTrain\":"    << json_dbl(rpt.rmse_train)        << ","
      << "\"rmseVal\":"      << json_dbl(rpt.rmse_val)          << ","
      << "\"rmseTest\":"     << json_dbl(rpt.rmse_test)         << ","
      << "\"bic\":"          << json_dbl(rpt.bic)               << ","
      << "\"aic\":"          << json_dbl(rpt.aic)               << ","
      << "\"diversity\":"    << json_dbl(rpt.population_diversity) << ","
      << "\"stagnation\":"   << rpt.stagnation          << ","
      << "\"phase\":"        << phase_.load()           << ","
      << "\"phaseName\":\""  << phase_name(static_cast<IdentificationPhase>(phase_.load())) << "\""
      << "}";
    return j.str();
}

void IdentificationPipeline::compute_test_metrics() {
    std::lock_guard<std::mutex> lk(results_mutex_);
    if (!best_chromosome_.evaluated || test_rows_ <= 0) return;

    RationalModel model(best_chromosome_);
    const int md = best_chromosome_.max_delay();
    const int n_test = test_rows_ - md;
    if (n_test <= 0) return;

    std::vector<double> yhat_test = model.predict_one_step(
        test_data_.data(), test_rows_, raw_cols_, cfg_.output_col
    );
    std::vector<double> y_test(n_test);
    for (int i = 0; i < n_test; ++i)
        y_test[i] = test_data_[(size_t)(i + md) * raw_cols_ + cfg_.output_col];

    best_chromosome_.metrics.rmse_test = Metrics::rmse(y_test.data(), yhat_test.data(), n_test);
    best_chromosome_.metrics.r2_test   = Metrics::r2(y_test.data(), yhat_test.data(), n_test);
}

std::string IdentificationPipeline::best_model_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    const auto& c = best_chromosome_;
    if (!c.evaluated) return "{\"status\":\"not_available\"}";

    std::ostringstream j;
    j << "{"
      << "\"outputCol\":"       << cfg_.output_col << ","
      << "\"numRegressors\":"   << c.num_regressors() << ","
      << "\"isRational\":"      << json_bool(c.is_rational()) << ","
      << "\"maxDelay\":"        << c.max_delay() << ","
      << "\"maxExponent\":"     << json_dbl(c.max_exponent()) << ","
      << "\"fitness\":"         << json_dbl(c.fitness) << ","
      << "\"sse\":"             << json_dbl(c.sse) << ","
      << "\"rmseTrain\":"       << json_dbl(c.metrics.rmse_train) << ","
      << "\"rmseVal\":"         << json_dbl(c.metrics.rmse_val) << ","
      << "\"rmseTest\":"        << json_dbl(c.metrics.rmse_test) << ","
      << "\"r2Train\":"         << json_dbl(c.metrics.r2_train) << ","
      << "\"r2Val\":"           << json_dbl(c.metrics.r2_val) << ","
      << "\"r2Test\":"          << json_dbl(c.metrics.r2_test) << ","
      << "\"bic\":"             << json_dbl(c.metrics.bic) << ","
      << "\"aic\":"             << json_dbl(c.metrics.aic) << ","
      << "\"freeRunRmse\":"     << json_dbl(c.metrics.rmse_free_run) << ","
      << "\"inputContributionRatio\":" << json_dbl(c.metrics.input_contribution_ratio) << ","
      << "\"residualInputCorr\":" << json_dbl(c.metrics.residual_input_corr) << ","
      << "\"contextsSurvived\":" << c.contexts_survived << ","
      << "\"worstFitnessSeen\":" << json_dbl(c.worst_fitness_seen) << ","
      << "\"intercept\":"       << json_dbl(c.intercept) << ","
      << "\"coefficients\":"    << json_arr(c.coefficients) << ","
      << "\"err\":"             << json_arr(c.err) << ","
      << "\"regressors\":[";
    for (size_t i = 0; i < c.regressors.size(); ++i) {
        if (i) j << ",";
        const auto& reg = c.regressors[i];
        j << "{\"terms\":[";
        for (size_t t = 0; t < reg.terms.size(); ++t) {
            if (t) j << ",";
            const auto& term = reg.terms[t];
            j << "{\"variable\":"      << term.variable
              << ",\"delay\":"         << term.delay
              << ",\"exponent\":"      << json_dbl(term.exponent)
              << ",\"isDenominator\":" << json_bool(term.is_denominator)
              << "}";
        }
        j << "]}";
    }
    j << "]"
      << "}";
    return j.str();
}

std::string IdentificationPipeline::snapshot_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    return build_broadcast_json(latest_report_);
}

int IdentificationPipeline::apply_tuning(
    const std::string& param, double value, const std::string& reason
) {
    AgentSuggestion s;
    s.param_name     = param;
    s.proposed_value = value;
    s.reason         = reason;
    TuningLogEntry entry;
    bool ok = handle_suggestion(s, entry);
    {
        std::lock_guard<std::mutex> lk(results_mutex_);
        tuning_log_.push_back(entry);
    }
    return ok ? 0 : 1;
}

std::string IdentificationPipeline::tuning_log_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    std::string s = "[";
    for (size_t i = 0; i < tuning_log_.size(); ++i) {
        const auto& e = tuning_log_[i];
        if (i) s += ",";
        s += "{\"accepted\":" + json_bool(e.accepted)
           + ",\"param\":\"" + e.param_name + "\""
           + ",\"newValue\":" + json_dbl(e.new_value)
           + ",\"reason\":\"" + e.reason + "\""
           + ",\"rejectionReason\":\"" + e.rejection_reason + "\""
           + ",\"generation\":" + std::to_string(e.generation)
           + "}";
    }
    return s + "]";
}

} // namespace aegis
