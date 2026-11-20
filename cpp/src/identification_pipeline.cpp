#include "aegis/identification_pipeline.hpp"
#include "aegis/metrics.hpp"
#include "aegis/rational_model.hpp"
#include "aegis/json_lite.hpp"
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <cstring>
#include <map>
#include <set>
#include <chrono>
#include <random>

namespace aegis {

using json::num;
using json::str;

// ── Names ──────────────────────────────────────────────────────────────────

const char* phase_name(IdentificationPhase p) {
    switch (p) {
        case IdentificationPhase::StructuralExploration: return "structural_exploration";
        case IdentificationPhase::NonlinearExpansion:    return "nonlinear_expansion";
        case IdentificationPhase::ParsimonyValidation:   return "parsimony_validation";
        case IdentificationPhase::LocalRefinement:       return "local_refinement";
    }
    return "unknown";
}

const char* phase_name_int(int p) {
    if (p < 0) return "curriculum_off";
    return phase_name(static_cast<IdentificationPhase>(std::min(p, 3)));
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

// ── PipelineConfig ─────────────────────────────────────────────────────────

static const std::set<std::string>& known_config_keys() {
    static const std::set<std::string> keys = {
        "normalizerType","trainRatio","validationRatio","trainEndRow","valEndRow","testStartRow",
        "testTransient","outputCol","datasetName",
        "numIslands","populationSize","elitismCount","mutationStrategy","mutationFactor",
        "crossoverRate","jadeC","jadeP","migrationInterval","migrationRate","maxRegressors",
        "maxTermsPerReg","maxDelay","pmin","pmax","exponentStep","powerMode",
        "denominatorProbability","rational","variableMutationRate","structuralMutationRate",
        "maxGenerations","stagnationLimit","maxEvaluations","reinitializationRatio",
        "reinitInterval","hypermutation","numThreads","randomSeed",
        "alpha","denominatorPenalty","complexityPenalty","exponentPenalty","stabilityPenalty",
        "noInputPenalty","freeRunPenalty","freeRunHorizon","inputContributionMin","errorMode",
        "curriculum","gammaAnnealStart","gammaAnnealEnd","phaseStagnationLimit","initialPmax",
        "initialDelayFraction","islandRoles","islandRegimes","enableRefiner","enablePruner",
        "webSocketPort","agentActionsEnabled","allowBudgetActions","actionCooldown",
        "outcomeHorizon","broadcastInterval","syncMode","historyStride"
    };
    return keys;
}

bool PipelineConfig::from_json(const std::string& text, std::string* error,
                               std::vector<std::string>* warnings) {
    json::Value v;
    std::string perr;
    if (!json::parse(text.empty() ? "{}" : text, v, &perr)) {
        if (error) *error = "invalid configuration JSON: " + perr;
        return false;
    }
    if (!v.is_object()) {
        if (error) *error = "configuration must be a JSON object";
        return false;
    }
    if (warnings)
        for (const auto& kv : v.members())
            if (!known_config_keys().count(kv.first))
                warnings->push_back("unknown configuration key ignored: " + kv.first);

    *this = PipelineConfig(); // defaults for every missing key

    const std::string nt = v.string_or("normalizerType", "minmax");
    if      (nt == "robust") normalizer_type = NormalizerType::RobustScaler;
    else if (nt == "zscore") normalizer_type = NormalizerType::ZScore;
    else                     normalizer_type = NormalizerType::MinMax;

    train_ratio    = v.number_or("trainRatio", 0.70);
    val_ratio      = v.number_or("validationRatio", 0.15);
    train_end_row  = v.int_or("trainEndRow", -1);
    val_end_row    = v.int_or("valEndRow", -1);
    test_start_row = v.int_or("testStartRow", -1);
    test_transient = std::max(0, v.int_or("testTransient", 0));
    output_col     = v.int_or("outputCol", -1);
    dataset_name   = v.string_or("datasetName", "");

    de.num_islands       = v.int_or("numIslands", 3);
    de.population_size   = v.int_or("populationSize", 50);
    de.elitism_count     = v.int_or("elitismCount", 2);
    de.strategy          = v.string_or("mutationStrategy", "jade") == "rand1"
                           ? MutationStrategy::Rand1 : MutationStrategy::JadeCurrentToPBest;
    de.mu_f              = v.number_or("mutationFactor", 0.5);
    de.mu_cr             = v.number_or("crossoverRate", 0.9);
    de.jade_c            = v.number_or("jadeC", 0.1);
    de.jade_p            = v.number_or("jadeP", 0.2);
    de.migration_interval= v.int_or("migrationInterval", 20);
    de.migration_rate    = v.number_or("migrationRate", 0.1);
    de.max_regressors    = v.int_or("maxRegressors", 8);
    de.max_terms_per_reg = v.int_or("maxTermsPerReg", 3);
    de.max_delay         = v.int_or("maxDelay", 40);
    de.pmin              = v.number_or("pmin", 0.5);
    de.pmax              = v.number_or("pmax", 5.0);
    de.exponent_step     = v.number_or("exponentStep", 0.5);
    de.power_mode        = power_mode_from_name(v.string_or("powerMode", "hybrid"));
    de.denominator_probability = v.number_or("denominatorProbability", 0.3);
    if (v.has("rational") && !v.bool_or("rational", true)) de.denominator_probability = 0.0;
    de.variable_mutation_rate   = v.number_or("variableMutationRate", 0.3);
    de.structural_mutation_rate = v.number_or("structuralMutationRate", 0.1);
    de.max_generations   = v.int_or("maxGenerations", 5000);
    de.stagnation_limit  = v.int_or("stagnationLimit", 500);
    de.max_evaluations   = static_cast<long long>(v.number_or("maxEvaluations", 0.0));
    de.reinit_ratio      = v.number_or("reinitializationRatio", 0.1);
    de.reinit_interval   = v.int_or("reinitInterval", 25);
    de.hypermutation     = v.bool_or("hypermutation", true);
    de.num_threads       = v.int_or("numThreads", 0);
    {
        const double s = v.number_or("randomSeed", 0.0);
        de.random_seed = (std::isfinite(s) && s > 0) ? static_cast<uint64_t>(s) : 0;
    }

    weights.alpha = v.number_or("alpha", 0.05);
    weights.beta  = v.number_or("denominatorPenalty", 0.1);
    weights.gamma = v.number_or("complexityPenalty", 0.01);
    weights.delta = v.number_or("exponentPenalty", 0.01);
    weights.eta   = v.number_or("stabilityPenalty", 1.0);
    weights.zeta  = v.number_or("noInputPenalty", 0.5);
    free_run_penalty = v.number_or("freeRunPenalty", 0.5);
    weights.theta = free_run_penalty;
    weights.free_run_horizon = v.int_or("freeRunHorizon", 50);
    weights.error_mode = v.string_or("errorMode", "one_step") == "simulation" ? 1 : 0;
    input_contribution_min = v.number_or("inputContributionMin", 0.3);
    weights.input_contribution_target = input_contribution_min;

    curriculum             = v.bool_or("curriculum", true);
    gamma_anneal_start     = v.number_or("gammaAnnealStart", weights.gamma);
    gamma_anneal_end       = v.number_or("gammaAnnealEnd", std::max(weights.gamma, 0.1));
    phase_stagnation_limit = v.int_or("phaseStagnationLimit", 150);
    initial_pmax           = v.number_or("initialPmax", 1.5);
    initial_delay_fraction = v.number_or("initialDelayFraction", 0.5);

    island_roles   = v.bool_or("islandRoles", true);
    island_regimes = v.bool_or("islandRegimes", true);
    enable_refiner = v.bool_or("enableRefiner", true);
    enable_pruner  = v.bool_or("enablePruner", true);

    ws_port   = v.int_or("webSocketPort", 0);
    enable_ws = ws_port > 0;
    agent_actions_enabled = v.bool_or("agentActionsEnabled", true);
    allow_budget_actions  = v.bool_or("allowBudgetActions", false);
    action_cooldown       = v.int_or("actionCooldown", 10);
    outcome_horizon       = v.int_or("outcomeHorizon", 25);
    broadcast_interval    = v.int_or("broadcastInterval", 1);
    sync_mode             = v.bool_or("syncMode", false);
    history_stride        = v.int_or("historyStride", 1);
    return true;
}

std::string PipelineConfig::to_json() const {
    std::ostringstream j;
    j << "{\"normalizerType\":" << str(normalizer_type == NormalizerType::MinMax ? "minmax" :
                                       normalizer_type == NormalizerType::RobustScaler ? "robust" : "zscore")
      << ",\"trainRatio\":" << num(train_ratio) << ",\"validationRatio\":" << num(val_ratio)
      << ",\"trainEndRow\":" << train_end_row << ",\"valEndRow\":" << val_end_row
      << ",\"testStartRow\":" << test_start_row << ",\"testTransient\":" << test_transient
      << ",\"outputCol\":" << output_col << ",\"datasetName\":" << str(dataset_name)
      << ",\"numIslands\":" << de.num_islands << ",\"populationSize\":" << de.population_size
      << ",\"elitismCount\":" << de.elitism_count
      << ",\"mutationStrategy\":" << str(mutation_strategy_name(de.strategy))
      << ",\"mutationFactor\":" << num(de.mu_f) << ",\"crossoverRate\":" << num(de.mu_cr)
      << ",\"jadeC\":" << num(de.jade_c) << ",\"jadeP\":" << num(de.jade_p)
      << ",\"migrationInterval\":" << de.migration_interval << ",\"migrationRate\":" << num(de.migration_rate)
      << ",\"maxRegressors\":" << de.max_regressors << ",\"maxTermsPerReg\":" << de.max_terms_per_reg
      << ",\"maxDelay\":" << de.max_delay << ",\"pmin\":" << num(de.pmin) << ",\"pmax\":" << num(de.pmax)
      << ",\"exponentStep\":" << num(de.exponent_step)
      << ",\"powerMode\":" << str(power_mode_name(de.power_mode))
      << ",\"denominatorProbability\":" << num(de.denominator_probability)
      << ",\"variableMutationRate\":" << num(de.variable_mutation_rate)
      << ",\"structuralMutationRate\":" << num(de.structural_mutation_rate)
      << ",\"maxGenerations\":" << de.max_generations << ",\"stagnationLimit\":" << de.stagnation_limit
      << ",\"maxEvaluations\":" << de.max_evaluations
      << ",\"reinitializationRatio\":" << num(de.reinit_ratio) << ",\"reinitInterval\":" << de.reinit_interval
      << ",\"hypermutation\":" << json::boolean(de.hypermutation)
      << ",\"numThreads\":" << de.num_threads << ",\"randomSeed\":" << de.random_seed
      << ",\"alpha\":" << num(weights.alpha) << ",\"denominatorPenalty\":" << num(weights.beta)
      << ",\"complexityPenalty\":" << num(weights.gamma) << ",\"exponentPenalty\":" << num(weights.delta)
      << ",\"stabilityPenalty\":" << num(weights.eta) << ",\"noInputPenalty\":" << num(weights.zeta)
      << ",\"freeRunPenalty\":" << num(free_run_penalty) << ",\"freeRunHorizon\":" << weights.free_run_horizon
      << ",\"errorMode\":" << str(weights.error_mode == 1 ? "simulation" : "one_step")
      << ",\"inputContributionMin\":" << num(input_contribution_min)
      << ",\"curriculum\":" << json::boolean(curriculum)
      << ",\"gammaAnnealStart\":" << num(gamma_anneal_start) << ",\"gammaAnnealEnd\":" << num(gamma_anneal_end)
      << ",\"phaseStagnationLimit\":" << phase_stagnation_limit
      << ",\"initialPmax\":" << num(initial_pmax) << ",\"initialDelayFraction\":" << num(initial_delay_fraction)
      << ",\"islandRoles\":" << json::boolean(island_roles) << ",\"islandRegimes\":" << json::boolean(island_regimes)
      << ",\"enableRefiner\":" << json::boolean(enable_refiner) << ",\"enablePruner\":" << json::boolean(enable_pruner)
      << ",\"webSocketPort\":" << ws_port
      << ",\"agentActionsEnabled\":" << json::boolean(agent_actions_enabled)
      << ",\"allowBudgetActions\":" << json::boolean(allow_budget_actions)
      << ",\"actionCooldown\":" << action_cooldown << ",\"outcomeHorizon\":" << outcome_horizon
      << ",\"broadcastInterval\":" << broadcast_interval
      << ",\"syncMode\":" << json::boolean(sync_mode) << ",\"historyStride\":" << history_stride
      << "}";
    return j.str();
}

// ── StateDigest / ActionRecord JSON ───────────────────────────────────────

std::string StateDigest::to_json() const {
    std::ostringstream j;
    j << "{\"generation\":" << generation << ",\"evaluations\":" << evaluations
      << ",\"phase\":" << phase << ",\"bestFitness\":" << num(best_fitness)
      << ",\"rmseVal\":" << num(rmse_val) << ",\"rmseTrain\":" << num(rmse_train)
      << ",\"freeRunRmse\":" << num(free_run_rmse) << ",\"freeRunRmseValFull\":" << num(free_run_val_full)
      << ",\"diversity\":" << num(diversity) << ",\"successRate\":" << num(success_rate)
      << ",\"stagnation\":" << stagnation << ",\"uniqueStructures\":" << unique_structures
      << ",\"numRegressors\":" << num_regressors << "}";
    return j.str();
}

std::string ActionRecord::to_json() const {
    std::ostringstream j;
    j << "{\"id\":" << id << ",\"source\":" << str(source) << ",\"param\":" << str(param)
      << ",\"reason\":" << str(reason)
      << ",\"requested\":" << num(requested) << ",\"oldValue\":" << num(old_value)
      << ",\"newValue\":" << num(new_value) << ",\"effectiveValue\":" << num(effective_value)
      << ",\"accepted\":" << json::boolean(accepted) << ",\"code\":" << str(code)
      << ",\"message\":" << str(message)
      << ",\"rejectionReason\":" << str(accepted ? "" : message)
      << ",\"generation\":" << generation_received
      << ",\"generationApplied\":" << generation_applied
      << ",\"pre\":" << pre.to_json()
      << ",\"post\":" << (resolved ? post.to_json() : "null")
      << ",\"resolved\":" << json::boolean(resolved)
      << ",\"outcome\":" << str(outcome) << ",\"outcomeNote\":" << str(outcome_note)
      << ",\"preTrend\":" << num(pre_trend) << ",\"postChange\":" << num(post_change)
      << "}";
    return j.str();
}

// ── Construction / data ───────────────────────────────────────────────────

IdentificationPipeline::IdentificationPipeline() { build_specs(); }

IdentificationPipeline::~IdentificationPipeline() {
    shutdown_.store(true);
    const auto s = state_.load();
    if (s == PipelineState::Running || s == PipelineState::Paused) state_.store(PipelineState::Stopped);
    if (de_) de_->stop();
    if (worker_thread_.joinable()) worker_thread_.join();
    if (ws_) ws_->stop();
}

bool IdentificationPipeline::load_data(const double* data, int rows, int cols) {
    if (!data || rows <= 0 || cols <= 0) return false;
    const auto s = state_.load();
    if (s == PipelineState::Running || s == PipelineState::Paused) return false;
    for (size_t i = 0; i < static_cast<size_t>(rows) * cols; ++i) {
        if (!std::isfinite(data[i])) {
            std::lock_guard<std::mutex> lk(results_mutex_);
            last_error_ = "data contain non-finite values";
            return false;
        }
    }
    raw_data_.assign(data, data + static_cast<size_t>(rows) * cols);
    raw_rows_ = rows;
    raw_cols_ = cols;
    data_hash_ = hash_doubles(raw_data_.data(), raw_data_.size());
    norm_data_.clear();
    return true;
}

bool IdentificationPipeline::configure(const std::string& json_config) {
    const auto s = state_.load();
    if (s == PipelineState::Running || s == PipelineState::Paused) return false;
    auto set_error = [&](const std::string& e) {
        std::lock_guard<std::mutex> lk(results_mutex_);
        last_error_ = e;
        return false;
    };
    if (raw_cols_ <= 0) return set_error("configure() called before load_data()");
    PipelineConfig c;
    std::string err;
    std::vector<std::string> warnings;
    if (!c.from_json(json_config, &err, &warnings)) return set_error(err);

    if (c.output_col < 0) c.output_col = raw_cols_ - 1;
    if (c.output_col >= raw_cols_) return set_error("outputCol out of range");
    if (c.train_end_row < 0) {
        if (!(c.train_ratio > 0.0) || c.val_ratio < 0.0 || c.train_ratio + c.val_ratio >= 1.0)
            return set_error("invalid trainRatio/validationRatio");
    } else {
        if (c.val_end_row < 0) c.val_end_row = c.train_end_row;
        if (c.test_start_row < 0) c.test_start_row = c.val_end_row;
        if (c.train_end_row <= 0 || c.val_end_row < c.train_end_row ||
            c.test_start_row < c.val_end_row || c.test_start_row > raw_rows_ ||
            c.val_end_row > raw_rows_)
            return set_error("invalid trainEndRow/valEndRow/testStartRow");
    }

    c.de.num_islands        = std::clamp(c.de.num_islands, 1, 16);
    c.de.population_size    = std::clamp(c.de.population_size, 4, 1000);
    c.de.elitism_count      = std::clamp(c.de.elitism_count, 0, c.de.population_size - 1);
    c.de.max_regressors     = std::clamp(c.de.max_regressors, 1, 40);
    c.de.max_terms_per_reg  = std::clamp(c.de.max_terms_per_reg, 1, 6);
    c.de.max_delay          = std::clamp(c.de.max_delay, 1, 500);
    c.de.pmin               = std::clamp(c.de.pmin, 0.1, 10.0);
    c.de.pmax               = std::clamp(c.de.pmax, c.de.pmin, 10.0);
    c.de.exponent_step      = std::clamp(c.de.exponent_step, 0.0, 1.0);
    c.de.mu_f               = std::clamp(c.de.mu_f, 0.01, 2.0);
    c.de.mu_cr              = std::clamp(c.de.mu_cr, 0.0, 1.0);
    c.de.jade_c             = std::clamp(c.de.jade_c, 0.0, 1.0);
    c.de.jade_p             = std::clamp(c.de.jade_p, 0.01, 1.0);
    c.de.migration_rate     = std::clamp(c.de.migration_rate, 0.0, 1.0);
    c.de.migration_interval = std::max(0, c.de.migration_interval);
    c.de.max_generations    = std::max(1, c.de.max_generations);
    c.de.stagnation_limit   = std::max(1, c.de.stagnation_limit);
    c.de.max_evaluations    = std::max(0LL, c.de.max_evaluations);
    c.de.reinit_ratio       = std::clamp(c.de.reinit_ratio, 0.0, 1.0);
    c.de.reinit_interval    = std::max(0, c.de.reinit_interval);
    c.de.denominator_probability   = std::clamp(c.de.denominator_probability, 0.0, 1.0);
    c.de.variable_mutation_rate    = std::clamp(c.de.variable_mutation_rate, 0.0, 1.0);
    c.de.structural_mutation_rate  = std::clamp(c.de.structural_mutation_rate, 0.0, 1.0);
    c.de.num_threads        = std::clamp(c.de.num_threads, 0, 64);
    c.weights.alpha = std::max(0.0, c.weights.alpha);
    c.weights.beta  = std::max(0.0, c.weights.beta);
    c.weights.gamma = std::max(0.0, c.weights.gamma);
    c.weights.delta = std::max(0.0, c.weights.delta);
    c.weights.eta   = std::max(0.0, c.weights.eta);
    c.weights.zeta  = std::max(0.0, c.weights.zeta);
    c.free_run_penalty = std::max(0.0, c.free_run_penalty);
    c.weights.theta = c.free_run_penalty;
    c.weights.free_run_horizon = std::max(0, c.weights.free_run_horizon); // 0 = whole validation split
    c.input_contribution_min = std::clamp(c.input_contribution_min, 0.0, 1.0);
    c.weights.input_contribution_target = c.input_contribution_min;
    c.gamma_anneal_start = std::max(0.0, c.gamma_anneal_start);
    c.gamma_anneal_end   = std::max(0.0, c.gamma_anneal_end);
    c.phase_stagnation_limit = std::max(2, c.phase_stagnation_limit);
    c.initial_pmax = std::clamp(c.initial_pmax, c.de.pmin, c.de.pmax);
    c.initial_delay_fraction = std::clamp(c.initial_delay_fraction, 0.05, 1.0);
    c.action_cooldown = std::max(0, c.action_cooldown);
    c.outcome_horizon = std::max(1, c.outcome_horizon);
    c.broadcast_interval = std::max(1, c.broadcast_interval);
    c.history_stride = std::max(1, c.history_stride);
    c.de.num_variables = raw_cols_;
    c.weights.score_start = c.de.max_delay; // common scoring row for all candidates
#ifdef __EMSCRIPTEN__
    c.sync_mode = true;
    c.enable_ws = false;
    c.de.num_threads = 1;   // no pthreads in the WASM build
#endif
    if (c.de.random_seed == 0) {
        // Record an explicit effective seed so the run can be reproduced.
        std::random_device rd;
        c.de.random_seed = (static_cast<uint64_t>(rd()) << 20) ^
            static_cast<uint64_t>(std::chrono::high_resolution_clock::now().time_since_epoch().count());
        c.de.random_seed &= 0x1FFFFFFFFFFFFFULL; // fits a JSON double exactly
        if (c.de.random_seed == 0) c.de.random_seed = 1;
    }

    {
        std::lock_guard<std::mutex> lk(control_mutex_);
        cfg_ = c;
        agent_enabled_.store(c.agent_actions_enabled);
    }
    std::lock_guard<std::mutex> lk(results_mutex_);
    last_error_.clear();
    for (const auto& w : warnings) last_error_ += (last_error_.empty() ? "" : "; ") + w;
    return true;
}

void IdentificationPipeline::prepare_data() {
    const int n = raw_rows_;
    const int cols = raw_cols_;
    if (cfg_.train_end_row >= 0) {
        train_end_  = cfg_.train_end_row;
        val_end_    = cfg_.val_end_row >= 0 ? cfg_.val_end_row : train_end_;
        test_start_ = cfg_.test_start_row >= 0 ? cfg_.test_start_row : val_end_;
    } else {
        train_end_  = static_cast<int>(n * cfg_.train_ratio);
        val_end_    = train_end_ + static_cast<int>(n * cfg_.val_ratio);
        test_start_ = val_end_;
    }
    normalizer_ = std::make_unique<Normalizer>(cfg_.normalizer_type, cfg_.norm_lo, cfg_.norm_hi);
    normalizer_->fit(raw_data_.data(), train_end_, cols);   // training segment only
    norm_data_ = raw_data_;
    normalizer_->transform(norm_data_.data(), n, cols);
    train_rows_ = train_end_;
    val_rows_   = val_end_ - train_end_;
    train_data_.assign(norm_data_.begin(), norm_data_.begin() + static_cast<size_t>(train_end_) * cols);
    if (val_rows_ > 0)
        val_data_.assign(norm_data_.begin() + static_cast<size_t>(train_end_) * cols,
                         norm_data_.begin() + static_cast<size_t>(val_end_) * cols);
    else
        val_data_.clear();
}

double IdentificationPipeline::divergence_bound() const {
    double m = 0.0;
    for (int i = 0; i < train_rows_; ++i)
        m = std::max(m, std::abs(train_data_[static_cast<size_t>(i) * raw_cols_ + cfg_.output_col]));
    return IndividualEvaluator::kDivergenceFactor * std::max(m, 1e-6);
}

// ── Action specification ──────────────────────────────────────────────────

void IdentificationPipeline::build_specs() {
    auto add = [&](const char* n, const char* kind, double mn, double mx, double step, bool integer,
                   bool budget, int cooldown, const char* desc) {
        ActionSpec s;
        s.name = n; s.kind = kind; s.min = mn; s.max = mx; s.max_step = step;
        s.integer = integer; s.budget = budget; s.cooldown = cooldown; s.description = desc;
        specs_.push_back(s);
    };
    add("mutationFactor", "de", 0.05, 1.0, 0.3, false, false, -1,
        "DE scale factor F (fixed for rand1; resets the JADE mean muF for jade)");
    add("crossoverRate", "de", 0.0, 1.0, 0.3, false, false, -1,
        "DE crossover rate CR (fixed for rand1; resets the JADE mean muCR for jade)");
    add("migrationRate", "de", 0.0, 0.5, 0.2, false, false, -1, "fraction of NP migrated (ring)");
    add("migrationInterval", "de", 5, 200, 50, true, false, -1, "generations between migrations");
    add("reinitializationRatio", "de", 0.0, 0.5, 0.2, false, false, -1,
        "fraction of worst individuals replaced by random immigrants on island stagnation");
    add("structuralMutationRate", "de", 0.0, 0.5, 0.2, false, false, -1,
        "probability of an add/delete/replace-regressor mutation per trial");
    add("stagnationLimit", "de", 50, 5000, 1000, true, true, -1,
        "global stopping criterion (budget-affecting; rejected unless allowBudgetActions)");
    add("complexityPenalty", "weight", 0.0, 1.0, 0.1, false, false, -1,
        "gamma; overrides the curriculum annealing from now on");
    add("noInputPenalty", "weight", 0.0, 5.0, 1.0, false, false, -1,
        "zeta (base; phase 0 enforces >= 1.5, later phases >= 0.8/1.0)");
    add("freeRunPenalty", "weight", 0.0, 5.0, 1.0, false, false, -1,
        "theta base (phase multipliers 0, 0.5, 1, 1.5)");
    add("freeRunHorizon", "weight", 10, 500, 200, true, false, -1,
        "samples of the in-loop free-run RMSE (triggers re-evaluation)");
    add("denominatorPenalty", "weight", 0.0, 2.0, 0.5, false, false, -1, "beta");
    add("stabilityPenalty", "weight", 0.0, 5.0, 1.0, false, false, -1,
        "eta (singularity + free-run divergence penalty)");
    add("exponentPenalty", "weight", 0.0, 1.0, 0.2, false, false, -1, "delta");
    add("alpha", "weight", 0.0, 2.0, 0.5, false, false, -1, "BIC/n weight");
    add("triggerRestart", "event", 0.05, 0.5, 0.5, false, false, 50,
        "one-shot: replace this fraction of every island and reset JADE means");
}

const ActionSpec* IdentificationPipeline::find_spec(const std::string& name) const {
    for (const auto& s : specs_) if (s.name == name) return &s;
    return nullptr;
}

std::string IdentificationPipeline::action_schema_json() const {
    std::lock_guard<std::mutex> lk(control_mutex_);
    std::ostringstream j;
    j << "{\"schema\":\"aegis.actions/1\",\"actionFormat\":{\"param\":\"string\",\"value\":\"number\","
         "\"reason\":\"string\",\"source\":\"string\"},\"defaultCooldown\":" << cfg_.action_cooldown
      << ",\"outcomeHorizon\":" << cfg_.outcome_horizon
      << ",\"allowBudgetActions\":" << json::boolean(cfg_.allow_budget_actions)
      << ",\"rejectionCodes\":[\"agent_disabled\",\"not_running\",\"invalid_json\",\"unknown_parameter\","
         "\"invalid_value\",\"budget_locked\",\"out_of_range\",\"step_too_large\",\"cooldown\",\"no_change\"]"
      << ",\"parameters\":[";
    for (size_t i = 0; i < specs_.size(); ++i) {
        const auto& s = specs_[i];
        if (i) j << ",";
        j << "{\"name\":" << str(s.name) << ",\"kind\":" << str(s.kind)
          << ",\"min\":" << num(s.min) << ",\"max\":" << num(s.max)
          << ",\"maxStep\":" << num(s.max_step) << ",\"integer\":" << json::boolean(s.integer)
          << ",\"budget\":" << json::boolean(s.budget)
          << ",\"cooldown\":" << (s.cooldown >= 0 ? s.cooldown : cfg_.action_cooldown)
          << ",\"current\":" << num(current_value_locked(s.name))
          << ",\"description\":" << str(s.description) << "}";
    }
    j << "]}";
    return j.str();
}

double IdentificationPipeline::current_value_locked(const std::string& name) const {
    if (name == "complexityPenalty")  return current_gamma_value();
    if (name == "noInputPenalty")     return cfg_.weights.zeta;
    if (name == "freeRunPenalty")     return cfg_.free_run_penalty;
    if (name == "freeRunHorizon")     return cfg_.weights.free_run_horizon;
    if (name == "denominatorPenalty") return cfg_.weights.beta;
    if (name == "stabilityPenalty")   return cfg_.weights.eta;
    if (name == "exponentPenalty")    return cfg_.weights.delta;
    if (name == "alpha")              return cfg_.weights.alpha;
    if (name == "triggerRestart")     return std::numeric_limits<double>::quiet_NaN();
    if (de_) return de_->tuning_value(name);
    if (name == "mutationFactor")        return cfg_.de.mu_f;
    if (name == "crossoverRate")         return cfg_.de.mu_cr;
    if (name == "migrationRate")         return cfg_.de.migration_rate;
    if (name == "migrationInterval")     return cfg_.de.migration_interval;
    if (name == "reinitializationRatio") return cfg_.de.reinit_ratio;
    if (name == "structuralMutationRate")return cfg_.de.structural_mutation_rate;
    if (name == "stagnationLimit")       return cfg_.de.stagnation_limit;
    return std::numeric_limits<double>::quiet_NaN();
}

double IdentificationPipeline::effective_value_locked(const std::string& name) const {
    if (!de_) return current_value_locked(name);
    const FitnessWeights w = de_->current_weights();
    if (name == "complexityPenalty")  return w.gamma;
    if (name == "noInputPenalty")     return w.zeta;
    if (name == "freeRunPenalty")     return w.theta;
    if (name == "freeRunHorizon")     return w.free_run_horizon;
    if (name == "denominatorPenalty") return w.beta;
    if (name == "stabilityPenalty")   return w.eta;
    if (name == "exponentPenalty")    return w.delta;
    if (name == "alpha")              return w.alpha;
    return current_value_locked(name);
}

// ── Curriculum ────────────────────────────────────────────────────────────

FitnessWeights IdentificationPipeline::phase_weights(int phase, double gamma) const {
    FitnessWeights w = cfg_.weights;
    w.gamma = gamma;
    if (!cfg_.curriculum || phase < 0) {
        w.theta = cfg_.free_run_penalty;
        return w;
    }
    switch (static_cast<IdentificationPhase>(phase)) {
        case IdentificationPhase::StructuralExploration:
            w.zeta  = std::max(cfg_.weights.zeta, 1.5);
            w.theta = 0.0;
            break;
        case IdentificationPhase::NonlinearExpansion:
            w.zeta  = std::max(cfg_.weights.zeta * 0.6, 0.8);
            w.theta = cfg_.free_run_penalty * 0.5;
            break;
        case IdentificationPhase::ParsimonyValidation:
            w.zeta  = std::max(cfg_.weights.zeta, 1.0);
            w.theta = cfg_.free_run_penalty;
            break;
        case IdentificationPhase::LocalRefinement:
            w.zeta  = std::max(cfg_.weights.zeta, 1.0);
            w.theta = cfg_.free_run_penalty * 1.5;
            break;
    }
    return w;
}

FitnessWeights IdentificationPipeline::apply_role_profile(FitnessWeights w, IslandRole role) const {
    switch (role) {
        case IslandRole::Parsimony:       w.gamma *= 2.0; w.zeta *= 1.5; break;
        case IslandRole::FreeRunFidelity: w.theta = std::max(w.theta, 0.15); w.gamma *= 0.7; break;
        case IslandRole::Stability:       w.eta *= 1.6; w.beta *= 1.4; break;
        case IslandRole::Balanced:
        default: break;
    }
    return w;
}

void IdentificationPipeline::push_weights_locked() {
    if (!de_) return;
    const FitnessWeights base = phase_weights(phase_.load(), current_gamma_value());
    for (int i = 0; i < static_cast<int>(island_roles_.size()); ++i)
        de_->update_weights_for_island(i, apply_role_profile(base, island_roles_[i]));
    de_->set_canonical_weights(base);
}

void IdentificationPipeline::log_reflex(const std::string& param, double value,
                                        const std::string& reason, int gen) {
    ActionRecord a;
    a.id = next_action_id_++;
    a.source = "reflex";
    a.param = param;
    a.reason = reason;
    a.requested = a.new_value = a.effective_value = value;
    a.accepted = true;
    a.code = "accepted";
    a.generation_received = a.generation_applied = gen;
    a.resolved = true;
    a.outcome = "n/a";
    actions_.push_back(std::move(a));
}

void IdentificationPipeline::update_phase(GenerationReport& rpt) {
    if (!de_) return;
    if (!cfg_.curriculum) {
        rpt.phase = -1;
        rpt.phase_name = phase_name_int(-1);
        return;
    }
    const int cur = phase_.load();
    int next = cur;
    std::string reason;
    const int stag = rpt.global_stagnation;
    const int psl = cfg_.phase_stagnation_limit;

    switch (static_cast<IdentificationPhase>(cur)) {
        case IdentificationPhase::StructuralExploration:
            if (std::isfinite(rpt.input_contribution_ratio) &&
                rpt.input_contribution_ratio >= cfg_.input_contribution_min && rpt.r2_train > 0.3) {
                next = 1; reason = "input_contribution_ratio and r2_train thresholds reached";
            } else if (stag >= psl) {
                next = 1; reason = "stagnation limit reached (forced advance)";
            }
            break;
        case IdentificationPhase::NonlinearExpansion:
            if (stag >= psl / 2) { next = 2; reason = "nonlinear search stagnated"; }
            break;
        case IdentificationPhase::ParsimonyValidation:
            if (stag >= psl) { next = 3; reason = "parsimony search stagnated"; }
            break;
        case IdentificationPhase::LocalRefinement:
            if (stag > 0 && stag % psl == 0) {
                de_->trigger_restart(0.3);
                log_reflex("restart", 0.3, "AEGIS reflex: LocalRefinement stagnated again -> "
                           "broad restart (random immigrants + JADE reset)", rpt.generation);
            }
            break;
    }

    if (next != cur) {
        // Complexity pressure for the new phase (annealed with run progress
        // unless an agent has overridden it).
        const double progress = std::clamp(
            static_cast<double>(rpt.generation) / std::max(1, cfg_.de.max_generations), 0.0, 1.0);
        annealed_gamma_ = cfg_.gamma_anneal_start +
                          (cfg_.gamma_anneal_end - cfg_.gamma_anneal_start) * progress;
        phase_.store(next);
        if (next == 1) de_->update_search_space(cfg_.de.pmax, cfg_.de.max_delay);
        if (next == 3) {
            const double mf = std::max(0.1, de_->tuning_value("mutationFactor") * 0.5);
            de_->apply_tuning("mutationFactor", mf);
            log_reflex("mutationFactor", mf, "AEGIS reflex: LocalRefinement halves F", rpt.generation);
        }
        push_weights_locked();
        log_reflex("phase", next, std::string("AEGIS reflex: ") + reason + " -> " +
                   phase_name_int(next), rpt.generation);
    }
    rpt.phase = phase_.load();
    rpt.phase_name = phase_name_int(rpt.phase);
}

double IdentificationPipeline::current_gamma_value() const {
    return gamma_override_ >= 0.0 ? gamma_override_ : annealed_gamma_;
}

// ── Start / step / control ────────────────────────────────────────────────

bool IdentificationPipeline::start() {
    const auto current_state = state_.load();
    if (current_state == PipelineState::Running || current_state == PipelineState::Paused) return false;
    auto fail = [&](const std::string& e) {
        std::lock_guard<std::mutex> lk(results_mutex_);
        last_error_ = e;
        state_.store(PipelineState::Error);
        return false;
    };
    if (raw_data_.empty()) return fail("no data loaded");

    // Join any previous run before discarding it.
    shutdown_.store(true);
    if (de_) de_->stop();
    if (worker_thread_.joinable()) worker_thread_.join();
    if (ws_) { ws_->stop(); ws_.reset(); }
    shutdown_.store(false);
    finalized_.store(false);

    std::lock_guard<std::mutex> ctl(control_mutex_);
    prepare_data();
    const int md_cfg = cfg_.de.max_delay;
    if (train_rows_ <= md_cfg + cfg_.de.max_regressors + 2)
        return fail("training split too short for maxDelay/maxRegressors");

    generation_.store(0);
    best_fitness_.store(std::numeric_limits<double>::infinity());
    phase_.store(cfg_.curriculum ? 0 : -1);
    annealed_gamma_ = cfg_.curriculum ? cfg_.gamma_anneal_start : cfg_.weights.gamma;
    gamma_override_ = -1.0;
    actions_.clear();
    pending_.clear();
    last_change_gen_.clear();
    next_action_id_ = 1;
    {
        std::lock_guard<std::mutex> lk(results_mutex_);
        best_chromosome_ = Chromosome();
        latest_report_ = GenerationReport();
        latest_report_.phase = phase_.load();
        latest_report_.phase_name = phase_name_int(phase_.load());
        history_.clear();
        recent_.clear();
        final_report_.clear();
        post_processing_log_.clear();
        elapsed_s_ = 0.0;
    }

    DEConfig initial_de = cfg_.de;
    if (cfg_.curriculum) {
        initial_de.pmax = std::min(cfg_.de.pmax, cfg_.initial_pmax);
        initial_de.max_delay = std::max(1, std::min(cfg_.de.max_delay,
            std::max(5, static_cast<int>(std::lround(cfg_.de.max_delay * cfg_.initial_delay_fraction)))));
    }
    const FitnessWeights initial_weights = phase_weights(phase_.load(), current_gamma_value());

    de_ = std::make_unique<DifferentialEvolutionOptimizer>(initial_de);
    de_->initialize(train_data_.data(), train_rows_,
                    val_rows_ > 0 ? val_data_.data() : nullptr, val_rows_,
                    nullptr, 0, raw_cols_, cfg_.output_col, initial_weights);

    // Specialized islands (roles) and validation regimes.
    const int n_islands = cfg_.de.num_islands;
    static const IslandRole role_cycle[4] = {
        IslandRole::Balanced, IslandRole::Parsimony, IslandRole::FreeRunFidelity, IslandRole::Stability
    };
    island_roles_.assign(n_islands, IslandRole::Balanced);
    for (int i = 0; i < n_islands; ++i) {
        island_roles_[i] = cfg_.island_roles ? role_cycle[i % 4] : IslandRole::Balanced;
        de_->set_island_role(i, island_role_name(island_roles_[i]));
    }
    if (cfg_.island_regimes && val_rows_ > 0 && n_islands > 1) {
        const int chunk = val_rows_ / n_islands;
        const int warmup = cfg_.de.max_delay;
        if (chunk > warmup + 5) {
            for (int i = 0; i < n_islands; ++i) {
                const int start_row = i * chunk;
                const int end_row = (i == n_islands - 1) ? val_rows_ : (i + 1) * chunk;
                const int data_start = std::max(0, start_row - warmup);
                de_->set_island_validation_window(
                    i, val_data_.data() + static_cast<size_t>(data_start) * raw_cols_, end_row - data_start);
            }
        }
    }
    push_weights_locked();

    t_start_ = std::chrono::steady_clock::now();
    state_.store(PipelineState::Running);

#ifndef __EMSCRIPTEN__
    if (cfg_.enable_ws) {
        ws_ = std::make_unique<AgentController>(cfg_.ws_port);
        ws_->on_message([this](const std::string& payload) {
            return apply_action_json(payload);
        });
        if (!ws_->start()) {
            std::lock_guard<std::mutex> lk(results_mutex_);
            last_error_ = "WebSocket server could not bind port " + std::to_string(cfg_.ws_port);
            ws_.reset();
        }
    }
    if (!cfg_.sync_mode) {
        de_->run_async(
            [this](const GenerationReport& r) { on_generation(r); },
            [this]() { return before_generation(); });
        worker_thread_ = std::thread([this] {
            de_->wait();
            if (shutdown_.load()) return;
            finalize(state_.load() == PipelineState::Stopped ? "stopped" : de_->stop_reason());
        });
    }
#endif
    return true;
}

bool IdentificationPipeline::before_generation() {
    {
        std::lock_guard<std::mutex> lk(control_mutex_);
        apply_pending_locked();
    }
    if (!cfg_.sync_mode) {
        while (state_.load() == PipelineState::Paused && !shutdown_.load())
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
    } else if (state_.load() == PipelineState::Paused) {
        return true;
    }
    return state_.load() == PipelineState::Stopped || shutdown_.load();
}

int IdentificationPipeline::step(int n) {
    if (state_.load() != PipelineState::Running || !de_) return 0;
    if (!cfg_.sync_mode) return 0; // async mode advances on its own thread
    const int ran = de_->run_steps(n,
        [this](const GenerationReport& r) { on_generation(r); },
        [this]() { return before_generation(); });
    if (de_->is_done() && state_.load() == PipelineState::Running) finalize(de_->stop_reason());
    return ran;
}

void IdentificationPipeline::pause() {
    PipelineState expected = PipelineState::Running;
    state_.compare_exchange_strong(expected, PipelineState::Paused);
}

void IdentificationPipeline::resume() {
    PipelineState expected = PipelineState::Paused;
    state_.compare_exchange_strong(expected, PipelineState::Running);
}

void IdentificationPipeline::stop() {
    const auto s = state_.load();
    if (s != PipelineState::Running && s != PipelineState::Paused) return;
    state_.store(PipelineState::Stopped);
    if (cfg_.sync_mode) {
        finalize("stopped");
    } else {
        if (de_) de_->stop();
        if (worker_thread_.joinable()) worker_thread_.join();
        if (!finalized_.load()) finalize("stopped");
    }
}

// ── Per-generation hook ───────────────────────────────────────────────────

StateDigest IdentificationPipeline::digest(const GenerationReport& r) const {
    StateDigest d;
    d.generation = r.generation;
    d.evaluations = r.evaluations;
    d.phase = r.phase;
    d.best_fitness = r.best_fitness;
    d.rmse_val = r.rmse_val;
    d.rmse_train = r.rmse_train;
    d.free_run_rmse = r.free_run_rmse;
    d.free_run_val_full = r.diagnostics.free_run_rmse_val_full;
    d.diversity = r.population_diversity;
    d.success_rate = r.success_rate;
    d.stagnation = r.global_stagnation;
    d.unique_structures = r.unique_structures;
    d.num_regressors = r.num_terms;
    return d;
}

static double rel_change(double before, double after) {
    if (!std::isfinite(before) || !std::isfinite(after) || std::abs(before) < 1e-300)
        return std::numeric_limits<double>::quiet_NaN();
    return (after - before) / std::abs(before);
}

void IdentificationPipeline::resolve_outcomes(const StateDigest& now, bool phase_changed) {
    std::lock_guard<std::mutex> lk(control_mutex_);
    const int H = cfg_.outcome_horizon;
    for (auto& a : actions_) {
        if (!a.accepted || a.resolved || a.generation_applied < 0 || a.source == "reflex") continue;
        if (phase_changed) a.outcome_note += (a.outcome_note.empty() ? "" : ";") + std::string("phase_change");
        if (now.generation - a.generation_applied < H) continue;
        a.post = now;
        a.resolved = true;
        a.post_change = rel_change(a.pre.rmse_val, now.rmse_val);
        // Confounders: other accepted non-reflex actions applied inside the window,
        // reflex restarts/phase changes inside the window.
        for (const auto& b : actions_) {
            if (b.id == a.id || !b.accepted || b.generation_applied < 0) continue;
            if (b.generation_applied >= a.generation_applied && b.generation_applied <= now.generation) {
                a.outcome_note += (a.outcome_note.empty() ? "" : ";") +
                                  (b.source == "reflex" ? "reflex_" + b.param : "other_action_" + std::to_string(b.id));
            }
        }
        if (!a.outcome_note.empty()) {
            a.outcome = "inconclusive";
        } else if (!std::isfinite(a.post_change)) {
            a.outcome = "inconclusive";
            a.outcome_note = "missing_metric";
        } else {
            const double before = std::isfinite(a.pre_trend) ? -a.pre_trend : 0.0;
            const double after = -a.post_change;
            const double score = after - before;
            a.outcome = score > 2e-3 ? "improved" : (score < -2e-3 ? "worsened" : "neutral");
        }
    }
}

void IdentificationPipeline::on_generation(const GenerationReport& report) {
    GenerationReport rpt = report;
    bool phase_changed = false;
    {
        std::lock_guard<std::mutex> lk(control_mutex_);
        const int before = phase_.load();
        update_phase(rpt);
        phase_changed = phase_.load() != before;
    }
    const StateDigest d = digest(rpt);
    resolve_outcomes(d, phase_changed);

    Chromosome live = de_->best_chromosome();
    generation_.store(rpt.generation);
    best_fitness_.store(rpt.best_fitness);
    std::string snap_for_ws;
    {
        std::lock_guard<std::mutex> lk(results_mutex_);
        elapsed_s_ = std::chrono::duration<double>(std::chrono::steady_clock::now() - t_start_).count();
        latest_report_ = rpt;
        if (live.evaluated) best_chromosome_ = std::move(live);
        recent_.push_back(d);
        while (static_cast<int>(recent_.size()) > 2 * cfg_.outcome_horizon + 2) recent_.pop_front();
        if (rpt.generation % cfg_.history_stride == 0 || !rpt.stop_reason.empty()) {
            std::ostringstream h;
            h << "{\"g\":" << rpt.generation << ",\"evals\":" << rpt.evaluations
              << ",\"t\":" << num(elapsed_s_, 6)
              << ",\"phase\":" << rpt.phase << ",\"best\":" << num(rpt.best_fitness)
              << ",\"rmseTrain\":" << num(rpt.rmse_train) << ",\"rmseVal\":" << num(rpt.rmse_val)
              << ",\"freeRun\":" << num(rpt.free_run_rmse)
              << ",\"freeRunValFull\":" << num(rpt.diagnostics.free_run_rmse_val_full)
              << ",\"nReg\":" << rpt.num_terms << ",\"div\":" << num(rpt.population_diversity)
              << ",\"sr\":" << num(rpt.success_rate) << ",\"stag\":" << rpt.global_stagnation
              << ",\"muF\":" << num(rpt.mu_f) << ",\"muCR\":" << num(rpt.mu_cr)
              << ",\"uniq\":" << rpt.unique_structures << "}";
            history_.push_back(h.str());
        }
    }
    if (ws_ && rpt.generation % cfg_.broadcast_interval == 0 && ws_->client_count() > 0)
        ws_->broadcast(snapshot_json());
}

// ── Actions ───────────────────────────────────────────────────────────────

std::string IdentificationPipeline::apply_action_json(const std::string& action_json) {
    json::Value v;
    std::string perr;
    std::vector<std::pair<std::string, double>> requests;
    std::string reason, source = "external";
    if (!json::parse(action_json, v, &perr) || !v.is_object()) {
        std::lock_guard<std::mutex> lk(control_mutex_);
        ActionRecord a;
        a.id = next_action_id_++;
        a.source = source;
        a.request_json = action_json.substr(0, 2000);
        a.code = "invalid_json";
        a.message = perr.empty() ? "action must be a JSON object" : perr;
        a.generation_received = generation_.load();
        a.outcome = "rejected";
        a.resolved = true;
        actions_.push_back(a);
        return "{\"results\":[" + a.to_json() + "]}";
    }
    reason = v.string_or("reason", "");
    source = v.string_or("source", "external");
    if (const json::Value* pc = v.get("proposed_changes"); pc && pc->is_object()) {
        for (const auto& kv : pc->members())
            requests.emplace_back(kv.first, kv.second.is_number() ? kv.second.as_number()
                                                                  : std::numeric_limits<double>::quiet_NaN());
    } else if (const json::Value* acts = v.get("actions"); acts && acts->is_array()) {
        for (const auto& a : acts->items())
            requests.emplace_back(a.string_or("param", ""), a.number_or("value", std::nan("")));
    } else {
        requests.emplace_back(v.string_or("param", ""), v.number_or("value", std::nan("")));
    }

    std::string out = "{\"results\":[";
    for (size_t i = 0; i < requests.size(); ++i) {
        const auto& rq = requests[i];
        std::lock_guard<std::mutex> lk(control_mutex_);
        ActionRecord a;
        a.id = next_action_id_++;
        a.source = source;
        a.param = rq.first;
        a.reason = reason;
        a.request_json = action_json.substr(0, 2000);
        a.requested = rq.second;
        a.generation_received = generation_.load();
        {
            std::lock_guard<std::mutex> rlk(results_mutex_);
            a.pre = digest(latest_report_);
            // Baseline trend: relative change of rmse_val over the H generations before now.
            const int H = cfg_.outcome_horizon;
            for (const auto& dd : recent_) {
                if (dd.generation == a.pre.generation - H) {
                    a.pre_trend = rel_change(dd.rmse_val, a.pre.rmse_val);
                    break;
                }
            }
        }
        const ActionSpec* spec = find_spec(rq.first);
        const auto st = state_.load();
        auto reject = [&](const char* code, const std::string& msg) {
            a.accepted = false; a.code = code; a.message = msg;
            a.outcome = "rejected"; a.resolved = true;
        };
        if (!agent_enabled_.load()) reject("agent_disabled", "agent actions are disabled");
        else if (st != PipelineState::Running && st != PipelineState::Paused) reject("not_running", "identification is not running");
        else if (!spec) reject("unknown_parameter", "unknown parameter: " + rq.first);
        else if (!std::isfinite(rq.second)) reject("invalid_value", "value must be a finite number");
        else if (spec->budget && !cfg_.allow_budget_actions) reject("budget_locked", "parameter changes the evaluation budget (allowBudgetActions=false)");
        else {
            double value = rq.second;
            if (spec->integer) value = std::round(value);
            a.old_value = current_value_locked(spec->name);
            const int cooldown = spec->cooldown >= 0 ? spec->cooldown : cfg_.action_cooldown;
            auto it = last_change_gen_.find(spec->name);
            if (value < spec->min || value > spec->max) {
                std::ostringstream m;
                m << "value " << value << " outside [" << spec->min << ", " << spec->max << "]";
                reject("out_of_range", m.str());
            } else if (spec->kind != "event" && std::isfinite(a.old_value) &&
                       std::abs(value - a.old_value) > spec->max_step + 1e-12) {
                std::ostringstream m;
                m << "|change| " << std::abs(value - a.old_value) << " exceeds maxStep " << spec->max_step;
                reject("step_too_large", m.str());
            } else if (it != last_change_gen_.end() && a.generation_received - it->second < cooldown) {
                reject("cooldown", "parameter changed at generation " + std::to_string(it->second) +
                       "; cooldown " + std::to_string(cooldown) + " generations");
            } else if (spec->kind != "event" && std::isfinite(a.old_value) &&
                       std::abs(value - a.old_value) < 1e-12) {
                reject("no_change", "value equals the current value");
            } else {
                a.accepted = true;
                a.code = "accepted";
                a.message = cfg_.sync_mode ? "queued; applied before the next generation"
                                           : "queued; applied at the next generation boundary";
                a.new_value = value;
                a.outcome = "pending";
                last_change_gen_[spec->name] = a.generation_received;
            }
        }
        actions_.push_back(a);
        if (a.accepted) pending_.push_back(static_cast<int>(actions_.size()) - 1);
        if (i) out += ",";
        out += a.to_json();
    }
    return out + "]}";
}

void IdentificationPipeline::apply_action_locked(ActionRecord& a) {
    const ActionSpec* spec = find_spec(a.param);
    if (!spec || !de_) return;
    const double v = a.new_value;
    if (spec->kind == "de") {
        de_->apply_tuning(a.param, v);
        if (a.param == "stagnationLimit") cfg_.de.stagnation_limit = static_cast<int>(v);
    } else if (spec->kind == "event") {
        if (a.param == "triggerRestart") de_->trigger_restart(v);
    } else {
        if      (a.param == "complexityPenalty")  gamma_override_ = v;
        else if (a.param == "noInputPenalty")     cfg_.weights.zeta = v;
        else if (a.param == "freeRunPenalty")     cfg_.free_run_penalty = v;
        else if (a.param == "freeRunHorizon")     cfg_.weights.free_run_horizon = static_cast<int>(v);
        else if (a.param == "denominatorPenalty") cfg_.weights.beta = v;
        else if (a.param == "stabilityPenalty")   cfg_.weights.eta = v;
        else if (a.param == "exponentPenalty")    cfg_.weights.delta = v;
        else if (a.param == "alpha")              cfg_.weights.alpha = v;
        push_weights_locked();
    }
    a.generation_applied = generation_.load();
    a.effective_value = effective_value_locked(a.param);
}

void IdentificationPipeline::apply_pending_locked() {
    for (int idx : pending_)
        if (idx >= 0 && idx < static_cast<int>(actions_.size())) apply_action_locked(actions_[idx]);
    pending_.clear();
}

int IdentificationPipeline::apply_tuning(const std::string& param, double value,
                                         const std::string& reason, const std::string& source) {
    std::ostringstream j;
    j << "{\"param\":" << str(param) << ",\"value\":" << num(value, 17)
      << ",\"reason\":" << str(reason) << ",\"source\":" << str(source) << "}";
    const std::string res = apply_action_json(j.str());
    json::Value v;
    if (!json::parse(res, v)) return 1;
    const json::Value* results = v.get("results");
    if (!results || results->items().empty()) return 1;
    const auto& r = results->items()[0];
    if (r.bool_or("accepted", false)) return 0;
    return r.string_or("code", "") == "unknown_parameter" ? -1 : 1;
}

void IdentificationPipeline::set_agent_enabled(bool enabled) { agent_enabled_.store(enabled); }

std::string IdentificationPipeline::tuning_log_json() const {
    std::lock_guard<std::mutex> lk(control_mutex_);
    std::string s = "[";
    for (size_t i = 0; i < actions_.size(); ++i) {
        if (i) s += ",";
        s += actions_[i].to_json();
    }
    return s + "]";
}

// ── Finalization ──────────────────────────────────────────────────────────

void IdentificationPipeline::post_process(Chromosome& champ) {
    std::ostringstream log;
    const FitnessWeights w = de_->current_weights();
    IndividualEvaluator ev(w);
    const double* vd = val_rows_ > 0 ? val_data_.data() : nullptr;
    Chromosome cur = champ;
    ev.evaluate(cur, train_data_.data(), train_rows_, vd, val_rows_, raw_cols_, cfg_.output_col);
    const double f0 = cur.fitness;
    log << "{\"initialFitness\":" << num(f0);

    if (cfg_.enable_pruner && cur.evaluated) {
        AutomaticPruner pruner(cfg_.prune);
        PruneResult pr = pruner.prune(cur, ev, train_data_.data(), train_rows_, vd, val_rows_,
                                      raw_cols_, cfg_.output_col);
        log << ",\"pruner\":{\"removed\":" << pr.removed_indices.size()
            << ",\"fitnessBefore\":" << num(pr.fitness_before)
            << ",\"fitnessAfter\":" << num(pr.fitness_after)
            << ",\"evaluations\":" << pr.evaluations << "}";
        if (pr.pruned_chromosome.evaluated && pr.fitness_after <= cur.fitness) cur = pr.pruned_chromosome;
    }
    if (cfg_.enable_refiner && cur.evaluated && cur.is_rational()) {
        LocalRefiner refiner(cfg_.refine);
        RefineResult rr = refiner.refine(cur, train_data_.data(), train_rows_, raw_cols_, cfg_.output_col);
        bool accepted = false;
        if (rr.coefficients.size() == cur.coefficients.size()) {
            Chromosome trial = cur;
            trial.coefficients = rr.coefficients;
            ev.evaluate(trial, train_data_.data(), train_rows_, vd, val_rows_, raw_cols_, cfg_.output_col,
                        /*refit=*/false);
            if (trial.evaluated && trial.fitness < cur.fitness) { cur = trial; accepted = true; }
        }
        log << ",\"refiner\":{\"iterations\":" << rr.iterations
            << ",\"sseBefore\":" << num(rr.initial_sse) << ",\"sseAfter\":" << num(rr.final_sse)
            << ",\"accepted\":" << json::boolean(accepted) << "}";
    }
    log << ",\"finalFitness\":" << num(cur.fitness) << "}";
    if (cur.evaluated) {
        cur.contexts_survived = champ.contexts_survived;
        cur.worst_fitness_seen = champ.worst_fitness_seen;
        champ = std::move(cur);
    }
    std::lock_guard<std::mutex> lk(results_mutex_);
    post_processing_log_ = log.str();
}

std::string IdentificationPipeline::segment_metrics_json(const Chromosome& c) const {
    const int ctx = cfg_.de.max_delay;
    const double bound = divergence_bound();
    const int rows = raw_rows_, cols = raw_cols_, out = cfg_.output_col;
    std::ostringstream j;
    SegmentMetrics tr = evaluate_segment(c, norm_data_.data(), rows, cols, out,
                                         0, train_end_, ctx, bound, normalizer_.get(), "train");
    j << "{\"train\":" << tr.to_json();
    if (val_end_ > train_end_) {
        SegmentMetrics va = evaluate_segment(c, norm_data_.data(), rows, cols, out,
                                             train_end_ - ctx, val_end_, train_end_, bound,
                                             normalizer_.get(), "validation");
        j << ",\"validation\":" << va.to_json();
    }
    if (rows > test_start_) {
        const bool contiguous = test_start_ == val_end_;
        const int seg_start = contiguous ? test_start_ - ctx : test_start_;
        const int score = contiguous ? test_start_ + cfg_.test_transient
                                     : test_start_ + std::max(ctx, cfg_.test_transient);
        SegmentMetrics te = evaluate_segment(c, norm_data_.data(), rows, cols, out,
                                             seg_start, rows, score, bound, normalizer_.get(), "test");
        j << ",\"test\":" << te.to_json();
    }
    j << "}";
    return j.str();
}

static std::string normalizer_json(const Normalizer* n, NormalizerType t, double lo, double hi) {
    std::ostringstream j;
    j << "{\"type\":" << str(t == NormalizerType::MinMax ? "minmax" : t == NormalizerType::RobustScaler ? "robust" : "zscore")
      << ",\"lo\":" << num(lo) << ",\"hi\":" << num(hi) << ",\"columns\":[";
    if (n) {
        for (int i = 0; i < n->num_cols(); ++i) {
            if (i) j << ",";
            const auto& c = n->col_norm(i);
            j << "{\"shift\":" << num(c.shift, 17) << ",\"scale\":" << num(c.scale, 17)
              << ",\"bounded\":" << json::boolean(c.bounded) << "}";
        }
    }
    j << "],\"formula\":\"bounded: x_n = lo + (x - shift)/scale*(hi-lo); unbounded: x_n = (x - shift)/scale\"}";
    return j.str();
}

void IdentificationPipeline::finalize(const std::string& reason) {
    bool expected = false;
    if (!finalized_.compare_exchange_strong(expected, true)) return;
    if (!de_) return;
    Chromosome champ = de_->best_chromosome();
    if (champ.evaluated) post_process(champ);

    std::string actions, schema, cfg_json;
    int n_acc = 0, n_rej = 0;
    {
        std::lock_guard<std::mutex> lk(control_mutex_);
        apply_pending_locked();
        for (auto& a : actions_) {
            if (a.accepted && !a.resolved) {
                a.resolved = true; a.outcome = "inconclusive";
                a.outcome_note += (a.outcome_note.empty() ? "" : ";") + std::string("run_ended");
            }
            if (a.source != "reflex") (a.accepted ? n_acc : n_rej)++;
        }
        cfg_json = cfg_.to_json();
    }
    actions = tuning_log_json();

    std::string segments = champ.evaluated ? segment_metrics_json(champ) : "null";
    const long long evals = de_->evaluations();
    std::ostringstream j;
    {
        std::lock_guard<std::mutex> lk(results_mutex_);
        elapsed_s_ = std::chrono::duration<double>(std::chrono::steady_clock::now() - t_start_).count();
        j << "{\"schema\":\"aegis.final_report/1\""
          << ",\"build\":" << build_info_json()
          << ",\"stopReason\":" << str(reason.empty() ? "unknown" : reason)
          << ",\"generations\":" << generation_.load()
          << ",\"evaluations\":" << evals
          << ",\"elapsedSeconds\":" << num(elapsed_s_, 8)
          << ",\"finalPhase\":" << phase_.load()
          << ",\"config\":" << cfg_json
          << ",\"data\":{\"rows\":" << raw_rows_ << ",\"cols\":" << raw_cols_
          << ",\"hashFnv1a64\":" << str(data_hash_)
          << ",\"trainEnd\":" << train_end_ << ",\"valEnd\":" << val_end_ << ",\"testStart\":" << test_start_
          << ",\"divergenceBound\":" << num(divergence_bound())
          << ",\"normalization\":" << normalizer_json(normalizer_.get(), cfg_.normalizer_type, cfg_.norm_lo, cfg_.norm_hi)
          << "}"
          << ",\"model\":" << (champ.evaluated ? chromosome_structure_json(champ) : "null");
        if (champ.evaluated) {
            RationalModel rm(champ);
            j << ",\"equation\":" << str(rm.equation_string())
              << ",\"numRegressors\":" << champ.num_regressors()
              << ",\"numFactors\":" << champ.num_terms()
              << ",\"numParameters\":" << champ.num_regressors() + 1
              << ",\"isRational\":" << json::boolean(champ.is_rational())
              << ",\"maxDelay\":" << champ.max_delay()
              << ",\"maxExponent\":" << num(champ.max_exponent())
              << ",\"canonicalFitness\":" << num(champ.fitness)
              << ",\"err\":" << json::num_array(champ.err)
              << ",\"stability\":{\"isStable\":" << json::boolean(champ.stability.is_stable)
              << ",\"minAbsDenominator\":" << num(champ.stability.min_abs_denominator)
              << ",\"denominatorSignChanges\":" << champ.stability.denominator_sign_changes
              << ",\"freeRunDivergedInHorizon\":" << json::boolean(champ.stability.free_run_diverged)
              << ",\"linearSpectralRadius\":" << num(StabilityAnalyzer::linear_spectral_radius(champ, cfg_.output_col))
              << "}";
        }
        j << ",\"metrics\":" << segments
          << ",\"postProcessing\":" << (post_processing_log_.empty() ? "null" : post_processing_log_)
          << ",\"agent\":{\"accepted\":" << n_acc << ",\"rejected\":" << n_rej << "}"
          << ",\"actions\":" << actions
          << "}";
        final_report_ = j.str();
        if (champ.evaluated) best_chromosome_ = champ;
    }
    const auto s = state_.load();
    if (s == PipelineState::Running || s == PipelineState::Paused) state_.store(PipelineState::Completed);
}

// ── JSON views ────────────────────────────────────────────────────────────

std::string IdentificationPipeline::final_report_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    return final_report_.empty() ? "{\"status\":\"not_available\"}" : final_report_;
}

std::string IdentificationPipeline::last_error() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    return last_error_;
}

std::string IdentificationPipeline::config_json() const {
    std::lock_guard<std::mutex> lk(control_mutex_);
    return cfg_.to_json();
}

std::string IdentificationPipeline::history_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    std::string s = "[";
    for (size_t i = 0; i < history_.size(); ++i) {
        if (i) s += ",";
        s += history_[i];
    }
    return s + "]";
}

std::string IdentificationPipeline::status_json() const {
    GenerationReport rpt;
    bool fin = finalized_.load();
    double elapsed;
    {
        std::lock_guard<std::mutex> lk(results_mutex_);
        rpt = latest_report_;
        elapsed = elapsed_s_;
    }
    std::ostringstream j;
    j << "{\"state\":" << str(pipeline_state_str(state_.load()))
      << ",\"generation\":" << generation_.load()
      << ",\"evaluations\":" << rpt.evaluations
      << ",\"bestFitness\":" << num(best_fitness_.load())
      << ",\"rmseTrain\":" << num(rpt.rmse_train)
      << ",\"rmseVal\":" << num(rpt.rmse_val)
      << ",\"rmseTest\":null"
      << ",\"bic\":" << num(rpt.bic) << ",\"aic\":" << num(rpt.aic)
      << ",\"diversity\":" << num(rpt.population_diversity)
      << ",\"stagnation\":" << rpt.global_stagnation
      << ",\"phase\":" << phase_.load()
      << ",\"phaseName\":" << str(phase_name_int(phase_.load()))
      << ",\"stopReason\":" << str(rpt.stop_reason)
      << ",\"finalReportAvailable\":" << json::boolean(fin)
      << ",\"syncMode\":" << json::boolean(cfg_.sync_mode)
      << ",\"elapsedMs\":" << static_cast<long long>(elapsed * 1000.0)
      << "}";
    return j.str();
}

std::string IdentificationPipeline::best_model_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    const auto& c = best_chromosome_;
    if (!c.evaluated) return "{\"status\":\"not_available\"}";
    // Test metrics are only exposed after the run has been finalized.
    double rmse_test = std::numeric_limits<double>::quiet_NaN(), r2_test = rmse_test,
           rmse_test_fr = rmse_test, r2_test_fr = rmse_test;
    if (finalized_.load() && !final_report_.empty()) {
        json::Value fr;
        if (json::parse(final_report_, fr)) {
            if (const json::Value* m = fr.get("metrics")) if (const json::Value* t = m->get("test")) {
                rmse_test = t->number_or("rmseOneStep", rmse_test);
                r2_test = t->number_or("r2OneStep", r2_test);
                rmse_test_fr = t->number_or("rmseFreeRun", rmse_test_fr);
                r2_test_fr = t->number_or("r2FreeRun", r2_test_fr);
            }
        }
    }
    std::ostringstream j;
    j << "{\"outputCol\":" << cfg_.output_col
      << ",\"powerMode\":" << str(power_mode_name(c.power_mode))
      << ",\"numRegressors\":" << c.num_regressors()
      << ",\"isRational\":" << json::boolean(c.is_rational())
      << ",\"maxDelay\":" << c.max_delay()
      << ",\"maxExponent\":" << num(c.max_exponent())
      << ",\"fitness\":" << num(c.fitness)
      << ",\"sse\":" << num(c.sse)
      << ",\"rmseTrain\":" << num(c.metrics.rmse_train)
      << ",\"rmseVal\":" << num(c.metrics.rmse_val)
      << ",\"rmseTest\":" << num(rmse_test)
      << ",\"r2Train\":" << num(c.metrics.r2_train)
      << ",\"r2Val\":" << num(c.metrics.r2_val)
      << ",\"r2Test\":" << num(r2_test)
      << ",\"rmseTestFreeRun\":" << num(rmse_test_fr)
      << ",\"r2TestFreeRun\":" << num(r2_test_fr)
      << ",\"testEvaluated\":" << json::boolean(finalized_.load())
      << ",\"bic\":" << num(c.metrics.bic)
      << ",\"aic\":" << num(c.metrics.aic)
      << ",\"fpe\":" << num(c.metrics.fpe)
      << ",\"mdl\":" << num(c.metrics.mdl)
      << ",\"freeRunRmse\":" << num(c.metrics.rmse_free_run)
      << ",\"inputContributionRatio\":" << num(c.metrics.input_contribution_ratio)
      << ",\"residualInputCorr\":" << num(c.metrics.residual_input_corr)
      << ",\"contextsSurvived\":" << c.contexts_survived
      << ",\"worstFitnessSeen\":" << num(c.worst_fitness_seen)
      << ",\"intercept\":" << num(c.intercept, 17)
      << ",\"coefficients\":" << json::num_array(c.coefficients, 17)
      << ",\"err\":" << json::num_array(c.err)
      << ",\"isStable\":" << json::boolean(c.stability.is_stable)
      << ",\"normalization\":" << normalizer_json(normalizer_.get(), cfg_.normalizer_type, cfg_.norm_lo, cfg_.norm_hi)
      << ",\"regressors\":[";
    for (size_t i = 0; i < c.regressors.size(); ++i) {
        if (i) j << ",";
        const auto& reg = c.regressors[i];
        j << "{\"terms\":[";
        for (size_t t = 0; t < reg.terms.size(); ++t) {
            if (t) j << ",";
            const auto& term = reg.terms[t];
            j << "{\"variable\":" << term.variable << ",\"delay\":" << term.delay
              << ",\"exponent\":" << num(term.exponent, 17)
              << ",\"isDenominator\":" << json::boolean(term.is_denominator) << "}";
        }
        j << "]}";
    }
    j << "]}";
    return j.str();
}

std::string IdentificationPipeline::snapshot_json() const {
    // Control-side information first (lock order: control → results).
    std::ostringstream params, agent;
    {
        std::lock_guard<std::mutex> lk(control_mutex_);
        params << "{";
        for (size_t i = 0; i < specs_.size(); ++i) {
            if (specs_[i].kind == "event") continue;
            if (params.tellp() > 1) params << ",";
            params << str(specs_[i].name) << ":" << num(current_value_locked(specs_[i].name));
        }
        params << "}";
        int acc = 0, rej = 0;
        const ActionRecord* last = nullptr;
        for (const auto& a : actions_) {
            if (a.source == "reflex") continue;
            (a.accepted ? acc : rej)++;
            last = &a;
        }
        agent << "{\"enabled\":" << json::boolean(agent_enabled_.load())
              << ",\"actionsAccepted\":" << acc << ",\"actionsRejected\":" << rej
              << ",\"pending\":" << pending_.size()
              << ",\"lastAction\":" << (last ? last->to_json() : "null") << "}";
    }
    GenerationReport r;
    double elapsed;
    {
        std::lock_guard<std::mutex> lk(results_mutex_);
        r = latest_report_;
        elapsed = elapsed_s_;
    }
    FitnessWeights w = de_ ? de_->current_weights() : FitnessWeights();
    const auto& fb = r.fitness_breakdown;
    const auto& st = r.stability;
    const auto& dg = r.diagnostics;
    std::ostringstream j;
    j << "{\"schema\":\"aegis.snapshot/2\""
      << ",\"state\":" << str(pipeline_state_str(state_.load()))
      << ",\"syncMode\":" << json::boolean(cfg_.sync_mode)
      << ",\"generation\":" << r.generation
      << ",\"evaluations\":" << r.evaluations
      << ",\"elapsedMs\":" << static_cast<long long>(elapsed * 1000.0)
      << ",\"phase\":" << r.phase << ",\"phase_name\":" << str(r.phase_name)
      << ",\"best_fitness\":" << num(r.best_fitness)
      << ",\"rmse_train\":" << num(r.rmse_train)
      << ",\"rmse_validation\":" << num(r.rmse_val)
      << ",\"rmse_test\":null"
      << ",\"r2_train\":" << num(r.r2_train)
      << ",\"r2_validation\":" << num(r.r2_val)
      << ",\"bic\":" << num(r.bic) << ",\"aic\":" << num(r.aic)
      << ",\"free_run_rmse\":" << num(r.free_run_rmse)
      << ",\"free_run_rmse_val_full\":" << num(dg.free_run_rmse_val_full)
      << ",\"free_run_r2_val_full\":" << num(dg.free_run_r2_val_full)
      << ",\"input_contribution_ratio\":" << num(r.input_contribution_ratio)
      << ",\"residual_input_corr\":" << num(r.residual_input_corr)
      << ",\"num_terms\":" << r.num_terms
      << ",\"num_factors\":" << r.num_factors
      << ",\"max_delay\":" << r.best_max_delay
      << ",\"max_exponent\":" << num(r.best_max_exponent)
      << ",\"is_rational\":" << json::boolean(r.best_is_rational)
      << ",\"coefficients\":" << json::num_array(r.best_coefficients)
      << ",\"intercept\":" << num(r.best_intercept)
      << ",\"exponents\":" << json::num_array(r.best_exponents)
      << ",\"err\":" << json::num_array(r.best_err)
      << ",\"term_labels\":" << json::str_array(r.best_term_labels)
      << ",\"fitness_breakdown\":{\"rmse\":" << num(fb.rmse) << ",\"bic_term\":" << num(fb.bic_term)
      << ",\"denom_term\":" << num(fb.denom_term) << ",\"complexity_term\":" << num(fb.complexity_term)
      << ",\"exponent_term\":" << num(fb.exponent_term) << ",\"stability_term\":" << num(fb.stability_term)
      << ",\"no_input_term\":" << num(fb.no_input_term) << ",\"free_run_term\":" << num(fb.free_run_term) << "}"
      << ",\"stability\":{\"is_stable\":" << json::boolean(st.is_stable)
      << ",\"min_abs_denominator\":" << num(st.min_abs_denominator)
      << ",\"denominator_sign_changes\":" << st.denominator_sign_changes
      << ",\"free_run_diverged\":" << json::boolean(st.free_run_diverged)
      << ",\"free_run_val_diverged\":" << json::boolean(dg.free_run_val_diverged)
      << ",\"linear_spectral_radius\":" << num(dg.linear_spectral_radius)
      << ",\"penalty\":" << num(st.penalty) << "}"
      << ",\"residual_autocorr\":" << json::num_array(r.residual_autocorr)
      << ",\"residual_acf_bound\":" << num(dg.residual_acf_bound)
      << ",\"residual_acf_max_abs\":" << num(dg.residual_acf_max_abs)
      << ",\"residual_white\":" << json::boolean(dg.residual_white)
      << ",\"residual_input_ccf_max\":" << num(dg.residual_input_ccf_max)
      << ",\"residual_split\":" << str(dg.residual_split)
      << ",\"is_stable\":" << json::boolean(r.is_stable)
      << ",\"overfitting\":" << json::boolean(r.overfitting)
      << ",\"underfitting\":" << json::boolean(r.underfitting)
      << ",\"overfit_gap_ratio\":" << num(dg.overfit_gap_ratio)
      << ",\"alerts\":" << str(r.alerts)
      << ",\"population_diversity\":" << num(r.population_diversity)
      << ",\"population_variance\":" << num(r.population_variance)
      << ",\"fitness_mean\":" << num(r.fitness_mean)
      << ",\"fitness_median\":" << num(r.fitness_median)
      << ",\"unique_structures\":" << r.unique_structures
      << ",\"structure_entropy\":" << num(r.structure_entropy)
      << ",\"success_rate\":" << num(r.success_rate)
      << ",\"mu_f\":" << num(r.mu_f) << ",\"mu_cr\":" << num(r.mu_cr)
      << ",\"stagnation\":" << r.stagnation
      << ",\"global_stagnation\":" << r.global_stagnation
      << ",\"mean_num_regressors\":" << num(r.mean_num_regressors)
      << ",\"islands\":[";
    for (size_t i = 0; i < r.islands.size(); ++i) {
        const auto& is = r.islands[i];
        if (i) j << ",";
        j << "{\"id\":" << is.id << ",\"role\":" << str(is.role)
          << ",\"best_fitness\":" << num(is.best_fitness) << ",\"mean_fitness\":" << num(is.mean_fitness)
          << ",\"median_fitness\":" << num(is.median_fitness) << ",\"std_fitness\":" << num(is.std_fitness)
          << ",\"worst_fitness\":" << num(is.worst_fitness) << ",\"stagnation\":" << is.stagnation
          << ",\"success_rate\":" << num(is.success_rate) << ",\"mu_f\":" << num(is.mu_f)
          << ",\"mu_cr\":" << num(is.mu_cr) << ",\"unique_structures\":" << is.unique_structures
          << ",\"population_size\":" << is.population_size
          << ",\"mean_num_regressors\":" << num(is.mean_num_regressors)
          << ",\"best_rmse_val\":" << num(is.best_rmse_val) << "}";
    }
    j << "],\"island_roles\":" << json::str_array(r.island_roles)
      << ",\"parameters\":" << params.str()
      << ",\"effective_weights\":{\"alpha\":" << num(w.alpha) << ",\"beta\":" << num(w.beta)
      << ",\"gamma\":" << num(w.gamma) << ",\"delta\":" << num(w.delta) << ",\"eta\":" << num(w.eta)
      << ",\"zeta\":" << num(w.zeta) << ",\"theta\":" << num(w.theta)
      << ",\"free_run_horizon\":" << w.free_run_horizon << "}"
      << ",\"agent\":" << agent.str()
      << ",\"stop_reason\":" << str(r.stop_reason)
      << ",\"best_contexts_survived\":" << r.best_contexts_survived
      << ",\"best_worst_fitness_seen\":" << num(r.best_worst_fitness_seen)
      << "}";
    return j.str();
}

// ── External models / migrants ────────────────────────────────────────────

std::string IdentificationPipeline::evaluate_model_json(const std::string& model_json, bool refit) {
    json::Value v;
    std::string err;
    if (!json::parse(model_json, v, &err)) return "{\"error\":" + str("invalid JSON: " + err) + "}";
    Chromosome c;
    if (!chromosome_from_json(v, c, cfg_.de.power_mode, &err)) return "{\"error\":" + str(err) + "}";
    for (const auto& reg : c.regressors)
        for (const auto& t : reg.terms)
            if (t.variable >= raw_cols_) return "{\"error\":\"variable index out of range\"}";
    if (norm_data_.empty()) {
        if (raw_data_.empty()) return "{\"error\":\"no data loaded\"}";
        std::lock_guard<std::mutex> lk(control_mutex_);
        prepare_data();
    }
    FitnessWeights w = de_ ? de_->current_weights() : phase_weights(cfg_.curriculum ? 3 : -1, cfg_.weights.gamma);
    IndividualEvaluator ev(w);
    const bool has_coef = c.coefficients.size() == c.regressors.size() && !c.coefficients.empty();
    ev.evaluate(c, train_data_.data(), train_rows_, val_rows_ > 0 ? val_data_.data() : nullptr, val_rows_,
                raw_cols_, cfg_.output_col, refit || !has_coef);
    if (!c.evaluated) return "{\"error\":\"model could not be evaluated (degenerate or too long delays)\"}";
    std::ostringstream j;
    j << "{\"model\":" << chromosome_structure_json(c)
      << ",\"refitted\":" << json::boolean(refit || !has_coef)
      << ",\"canonicalFitness\":" << num(c.fitness)
      << ",\"numRegressors\":" << c.num_regressors()
      << ",\"numParameters\":" << c.num_regressors() + 1
      << ",\"maxDelay\":" << c.max_delay()
      << ",\"isRational\":" << json::boolean(c.is_rational())
      << ",\"err\":" << json::num_array(c.err)
      << ",\"metrics\":" << segment_metrics_json(c) << "}";
    return j.str();
}

bool IdentificationPipeline::inject_individual(const std::string& json_text) {
    if (!de_ || json_text.empty()) return false;
    json::Value v;
    if (!json::parse(json_text, v)) return false;
    Chromosome c;
    if (!chromosome_from_json(v, c, cfg_.de.power_mode)) return false;
    c.coefficients.clear();
    c.evaluated = false;
    de_->inject_migrant(c);
    return true;
}

} // namespace aegis
