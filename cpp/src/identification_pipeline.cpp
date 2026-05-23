#include "aegis/identification_pipeline.hpp"
#include "aegis/metrics.hpp"
#include "aegis/overfitting_detector.hpp"
#include "aegis/underfitting_detector.hpp"
#include "aegis/excitation_analyzer.hpp"
#include "aegis/residual_analyzer.hpp"
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <cstring>
#include <map>

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

    de.num_islands      = geti("numIslands",       3);
    de.population_size  = geti("populationSize",  50);
    de.max_generations  = geti("maxGenerations",5000);
    de.stagnation_limit = geti("stagnationLimit", 500);
    de.mu_f             = getd("mutationFactor",  0.5);
    de.mu_cr            = getd("crossoverRate",   0.9);
    de.elitism_count    = geti("elitismCount",      2);
    de.migration_interval=geti("migrationInterval",20);
    de.migration_rate   = getd("migrationRate",  0.1);
    de.max_regressors   = geti("maxRegressors",    8);
    de.max_terms_per_reg= geti("maxTermsPerReg",   3);
    de.pmin             = getd("pmin",            0.5);
    de.pmax             = getd("pmax",            5.0);
    de.max_delay        = geti("maxDelay",         20);
    de.num_threads      = geti("numThreads",        0);

    weights.alpha = getd("alpha",           1.0);
    weights.beta  = getd("denominatorPenalty", 0.1);
    weights.gamma = getd("complexityPenalty",0.01);
    weights.delta = getd("exponentPenalty",  0.01);
    weights.eta   = getd("stabilityPenalty",  1.0);
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
    cfg_.from_json(json_config);
    if (cfg_.output_col < 0) cfg_.output_col = raw_cols_ - 1;
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
        {"mutationFactor",   {0.0, 2.0}},
        {"crossoverRate",    {0.0, 1.0}},
        {"migrationRate",    {0.0, 0.5}},
        {"migrationInterval",{5,   200}},
        {"stagnationLimit",  {50,  5000}},
        {"complexityPenalty",{0.0, 10.0}},
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

bool IdentificationPipeline::start() {
    if (state_.load() == PipelineState::Running) return false;
    if (raw_data_.empty()) return false;

    state_.store(PipelineState::Running);

    // Normalise and split
    normalizer_ = std::make_unique<Normalizer>(cfg_.normalizer_type, 1e-6, 1.0);
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

    de_ = std::make_unique<DifferentialEvolutionOptimizer>(cfg_.de);
    de_->initialize(
        train_data_.data(), train_rows_,
        val_rows_ > 0 ? val_data_.data() : nullptr, val_rows_,
        test_rows_ > 0 ? test_data_.data() : nullptr, test_rows_,
        raw_cols_, cfg_.output_col, cfg_.weights
    );

#ifndef __EMSCRIPTEN__
    setup_agent();

    de_->run_async(
        [this](const GenerationReport& rpt) {
            generation_.store(rpt.generation);
            best_fitness_.store(rpt.best_fitness);
            {
                std::lock_guard<std::mutex> lk(results_mutex_);
                latest_report_ = rpt;
            }
            if (agent_) {
                std::string json = build_broadcast_json(
                    rpt.generation, rpt.best_fitness,
                    rpt.rmse_train, rpt.rmse_val, rpt.rmse_test,
                    rpt.bic, rpt.aic, rpt.population_diversity,
                    rpt.stagnation, rpt.mu_f, rpt.mu_cr, rpt.num_terms,
                    rpt.is_stable, rpt.overfitting, rpt.underfitting, rpt.pe_ok,
                    rpt.residual_autocorr, rpt.best_coefficients,
                    rpt.best_exponents, rpt.alerts
                );
                agent_->broadcast(json);
            }
        },
        [this]() -> bool {
            return state_.load() == PipelineState::Stopped;
        }
    );

    // Monitor in background thread for completion
    worker_thread_ = std::thread([this] {
        de_->wait();
        if (state_.load() == PipelineState::Running)
            state_.store(PipelineState::Completed);
        // Store final best
        std::lock_guard<std::mutex> lk(results_mutex_);
        best_chromosome_ = de_->best_chromosome();
    });
#endif // !__EMSCRIPTEN__

    return true;
}

int IdentificationPipeline::step(int n) {
    if (state_.load() != PipelineState::Running) return 0;
    if (!de_) return 0;

    int ran = de_->run_steps(n,
        [this](const GenerationReport& rpt) {
            generation_.store(rpt.generation);
            best_fitness_.store(rpt.best_fitness);
            std::lock_guard<std::mutex> lk(results_mutex_);
            latest_report_ = rpt;
        },
        [this]() -> bool {
            auto s = state_.load();
            return s == PipelineState::Stopped || s == PipelineState::Paused;
        }
    );

    if (de_->is_done() && state_.load() == PipelineState::Running) {
        std::lock_guard<std::mutex> lk(results_mutex_);
        best_chromosome_ = de_->best_chromosome();
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
      << "\"stagnation\":"   << rpt.stagnation
      << "}";
    return j.str();
}

std::string IdentificationPipeline::best_model_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    const auto& c = best_chromosome_;
    if (!c.evaluated) return "{\"status\":\"not_available\"}";

    std::ostringstream j;
    j << "{"
      << "\"numRegressors\":"   << c.num_regressors() << ","
      << "\"isRational\":"      << json_bool(c.is_rational()) << ","
      << "\"maxDelay\":"        << c.max_delay() << ","
      << "\"maxExponent\":"     << json_dbl(c.max_exponent()) << ","
      << "\"fitness\":"         << json_dbl(c.fitness) << ","
      << "\"sse\":"             << json_dbl(c.sse) << ","
      << "\"coefficients\":"    << json_arr(c.coefficients) << ","
      << "\"err\":"             << json_arr(c.err)
      << "}";
    return j.str();
}

std::string IdentificationPipeline::snapshot_json() const {
    std::lock_guard<std::mutex> lk(results_mutex_);
    const auto& r = latest_report_;
    return build_broadcast_json(
        r.generation, r.best_fitness, r.rmse_train, r.rmse_val, r.rmse_test,
        r.bic, r.aic, r.population_diversity, r.stagnation, r.mu_f, r.mu_cr,
        r.num_terms, r.is_stable, r.overfitting, r.underfitting, r.pe_ok,
        r.residual_autocorr, r.best_coefficients, r.best_exponents, r.alerts
    );
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
