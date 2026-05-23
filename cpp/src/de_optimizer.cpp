#include "aegis/de_optimizer.hpp"
#include "aegis/safe_power.hpp"
#include <algorithm>
#include <numeric>
#include <cmath>
#include <cassert>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#include <stdexcept>
#include <sstream>
#include <chrono>
#include <unordered_set>
#include <thread>

namespace aegis {

// ─────────────────────────────────────────────────────────────────────────
//  Island implementation
// ─────────────────────────────────────────────────────────────────────────

Island::Island(int id, const DEConfig& cfg, uint64_t seed,
               const double* train_data, int train_rows,
               const double* val_data,   int val_rows,
               int cols, int output_col,
               const FitnessWeights& weights)
    : id_(id), cfg_(cfg), rng_(seed),
      evaluator_(weights),
      train_data_(train_data), train_rows_(train_rows),
      val_data_(val_data),     val_rows_(val_rows),
      cols_(cols),             output_col_(output_col),
      mu_f_(cfg.mu_f),         mu_cr_(cfg.mu_cr)
{
    pop_.reserve(cfg_.population_size);
    for (int i = 0; i < cfg_.population_size; ++i)
        pop_.push_back(random_chromosome());

    // Evaluate initial population
    for (auto& c : pop_) {
        evaluator_.evaluate(c, train_data_, train_rows_,
                            val_data_, val_rows_, cols_, output_col_);
    }
}

// ── Chromosome factory ────────────────────────────────────────────────────

Chromosome Island::random_chromosome() {
    std::uniform_int_distribution<int> rn_reg(1, cfg_.max_regressors);
    std::uniform_int_distribution<int> rn_terms(1, cfg_.max_terms_per_reg);
    std::uniform_int_distribution<int> rn_var(0, cfg_.num_variables - 1);
    std::uniform_int_distribution<int> rn_delay(1, cfg_.max_delay);
    std::uniform_real_distribution<double> rn_exp(cfg_.pmin, cfg_.pmax);
    std::uniform_real_distribution<double> rn_denom(0.0, 1.0);

    Chromosome c;
    int n_reg = rn_reg(rng_);
    c.regressors.resize(n_reg);

    for (auto& reg : c.regressors) {
        int n_terms = rn_terms(rng_);
        reg.terms.resize(n_terms);
        bool is_denom = (rn_denom(rng_) < 0.3); // 30% chance denominator
        for (auto& t : reg.terms) {
            t.variable      = rn_var(rng_);
            t.delay         = rn_delay(rng_);
            t.exponent      = quantize_exponent(rn_exp(rng_), cfg_.pmin, cfg_.pmax);
            t.is_denominator= is_denom;
        }
    }
    return c;
}

// ── PRNG helpers ──────────────────────────────────────────────────────────

double Island::gauss_rand(double mean, double std) {
    static std::normal_distribution<double> nd;
    return nd(rng_) * std + mean;
}

double Island::cauchy_rand(double loc, double scale) {
    // Cauchy from uniform: tan(π*(U - 0.5))
    std::uniform_real_distribution<double> u(0.0, 1.0);
    double val;
    do { val = loc + scale * std::tan(M_PI * (u(rng_) - 0.5)); }
    while (!std::isfinite(val));
    return val;
}

// ── Lehmer mean ───────────────────────────────────────────────────────────

double Island::lehmer_mean(const std::vector<double>& v) const {
    if (v.empty()) return mu_f_;
    double s2 = 0.0, s1 = 0.0;
    for (double x : v) { s2 += x * x; s1 += x; }
    return s1 < 1e-30 ? mu_f_ : s2 / s1;
}

// ── JADE mutation ─────────────────────────────────────────────────────────

Chromosome Island::mutate_jade(int target_idx, double& f_i, double& cr_i) {
    // Sample F ~ Cauchy(μF, 0.1) clipped to (0, 2]
    do { f_i = cauchy_rand(mu_f_, 0.1); } while (f_i <= 0.0);
    f_i = std::min(f_i, 2.0);

    // Sample CR ~ N(μCR, 0.1) clipped to [0, 1]
    cr_i = clamp(gauss_rand(mu_cr_, 0.1), 0.0, 1.0);

    const int sz = static_cast<int>(pop_.size());
    if (sz < 4) return pop_[target_idx];

    // Pick best (top 20%)
    int p_top = std::max(1, static_cast<int>(sz * 0.2));
    std::vector<int> sorted_idx(sz);
    std::iota(sorted_idx.begin(), sorted_idx.end(), 0);
    std::partial_sort(sorted_idx.begin(), sorted_idx.begin() + p_top,
                      sorted_idx.end(),
                      [&](int a, int b){ return pop_[a].fitness < pop_[b].fitness; });

    std::uniform_int_distribution<int> pick_best(0, p_top - 1);
    int pbest = sorted_idx[pick_best(rng_)];

    // Pick two distinct random individuals (not target, not pbest)
    std::vector<int> pool;
    pool.reserve(sz - 2);
    for (int i = 0; i < sz; ++i)
        if (i != target_idx && i != pbest) pool.push_back(i);

    std::shuffle(pool.begin(), pool.end(), rng_);
    int r1 = pool[0], r2 = pool[1];

    // DE/current-to-pbest/1: v = x_i + F*(x_pbest - x_i) + F*(x_r1 - x_r2)
    // Applied structurally (per-regressor, per-term-field)
    // We blend at the gene (Term) level.

    const auto& xi    = pop_[target_idx];
    const auto& xbest = pop_[pbest];
    const auto& xr1   = pop_[r1];
    const auto& xr2   = pop_[r2];

    Chromosome mutant;
    int max_r = std::max({
        (int)xi.regressors.size(),
        (int)xbest.regressors.size(),
        (int)xr1.regressors.size()
    });
    max_r = std::min(max_r, cfg_.max_regressors);

    std::uniform_real_distribution<double> u01(0.0, 1.0);

    for (int j = 0; j < max_r; ++j) {
        // Randomly pick the base for this regressor slot
        const auto* src_xbest = (j < (int)xbest.regressors.size()) ? &xbest.regressors[j] : nullptr;
        const auto* src_xi    = (j < (int)xi.regressors.size())    ? &xi.regressors[j]    : nullptr;
        const auto* src_r1    = (j < (int)xr1.regressors.size())   ? &xr1.regressors[j]   : nullptr;
        const auto* src_r2    = (j < (int)xr2.regressors.size())   ? &xr2.regressors[j]   : nullptr;

        Regressor new_reg;
        // Use xi or xbest as base; mutate delays/exponents
        const auto* base = (src_xi && u01(rng_) > 0.5) ? src_xi : src_xbest;
        if (!base && src_r1) base = src_r1;
        if (!base) break;

        new_reg.terms = base->terms;

        // Perturb exponents: p_new = p_xi + F*(p_best - p_xi) + F*(p_r1 - p_r2)
        int max_terms = std::max({
            (int)new_reg.terms.size(),
            src_r1 ? (int)src_r1->terms.size() : 0,
            src_r2 ? (int)src_r2->terms.size() : 0
        });
        for (int t = 0; t < (int)new_reg.terms.size() && t < max_terms; ++t) {
            auto& term = new_reg.terms[t];
            // Exponent mutation
            double xi_e  = term.exponent;
            double b_e   = src_xbest && t < (int)src_xbest->terms.size()
                         ? src_xbest->terms[t].exponent : xi_e;
            double r1_e  = src_r1 && t < (int)src_r1->terms.size()
                         ? src_r1->terms[t].exponent : xi_e;
            double r2_e  = src_r2 && t < (int)src_r2->terms.size()
                         ? src_r2->terms[t].exponent : xi_e;
            double ne    = xi_e + f_i * (b_e - xi_e) + f_i * (r1_e - r2_e);
            term.exponent = quantize_exponent(ne, cfg_.pmin, cfg_.pmax);

            // Delay mutation (integer, discrete)
            double xi_d  = term.delay;
            double b_d   = src_xbest && t < (int)src_xbest->terms.size()
                         ? src_xbest->terms[t].delay : xi_d;
            double r1_d  = src_r1 && t < (int)src_r1->terms.size()
                         ? src_r1->terms[t].delay : xi_d;
            double r2_d  = src_r2 && t < (int)src_r2->terms.size()
                         ? src_r2->terms[t].delay : xi_d;
            double nd    = xi_d + f_i * (b_d - xi_d) + f_i * (r1_d - r2_d);
            term.delay   = std::max(1, std::min(cfg_.max_delay, (int)std::round(nd)));

            // Variable mutation (rare: swap variable index)
            if (u01(rng_) < 0.1) {
                std::uniform_int_distribution<int> rn_var(0, cfg_.num_variables - 1);
                term.variable = rn_var(rng_);
            }
        }
        mutant.regressors.push_back(new_reg);
    }
    if (mutant.regressors.empty()) return pop_[target_idx];
    return mutant;
}

// ── Binomial crossover ───────────────────────────────────────────────────

Chromosome Island::crossover_binomial(
    const Chromosome& target, const Chromosome& mutant, double cr
) {
    Chromosome trial;
    std::uniform_real_distribution<double> u01(0.0, 1.0);
    std::uniform_int_distribution<int>     jrand(0, std::max(
        (int)target.regressors.size(), (int)mutant.regressors.size()) - 1);

    int j_rand = jrand(rng_);
    int max_r  = std::max((int)target.regressors.size(),
                           (int)mutant.regressors.size());
    for (int j = 0; j < max_r; ++j) {
        bool take_mutant = (u01(rng_) < cr) || (j == j_rand);
        if (take_mutant && j < (int)mutant.regressors.size()) {
            trial.regressors.push_back(mutant.regressors[j]);
        } else if (j < (int)target.regressors.size()) {
            trial.regressors.push_back(target.regressors[j]);
        }
    }
    if (trial.regressors.empty()) trial = target;
    return trial;
}

// ── JADE generation end ──────────────────────────────────────────────────

void Island::jade_end_generation() {
    if (!success_f_.empty())
        mu_f_  = (1.0 - cfg_.jade_c) * mu_f_  + cfg_.jade_c * lehmer_mean(success_f_);
    if (!success_cr_.empty())
        mu_cr_ = (1.0 - cfg_.jade_c) * mu_cr_ + cfg_.jade_c *
                  (std::accumulate(success_cr_.begin(), success_cr_.end(), 0.0) /
                   success_cr_.size());
    mu_f_  = clamp(mu_f_,  0.01, 0.99);
    mu_cr_ = clamp(mu_cr_, 0.01, 0.99);
    success_f_.clear();
    success_cr_.clear();
    success_count_ = 0;
    trial_count_   = 0;
}

// ── run_generation ───────────────────────────────────────────────────────

void Island::run_generation() {
    const int sz = static_cast<int>(pop_.size());

    // Sort pop to find elites
    std::vector<int> idx(sz);
    std::iota(idx.begin(), idx.end(), 0);
    std::sort(idx.begin(), idx.end(),
              [&](int a, int b){ return pop_[a].fitness < pop_[b].fitness; });

    std::vector<Chromosome> new_pop(sz);
    // Keep elites
    for (int e = 0; e < std::min(cfg_.elitism_count, sz); ++e)
        new_pop[e] = pop_[idx[e]];

    for (int i = 0; i < sz; ++i) {
        ++trial_count_;
        double f_i, cr_i;
        Chromosome mutant = mutate_jade(i, f_i, cr_i);
        Chromosome trial  = crossover_binomial(pop_[i], mutant, cr_i);

        // Evaluate trial
        evaluator_.evaluate(trial, train_data_, train_rows_,
                            val_data_, val_rows_, cols_, output_col_);

        bool replace = trial.evaluated && trial.fitness < pop_[i].fitness;
        // Never replace an elite
        bool is_elite = false;
        for (int e = 0; e < std::min(cfg_.elitism_count, sz); ++e)
            if (idx[e] == i) { is_elite = true; break; }

        if (replace && !is_elite) {
            new_pop[i] = trial;
            ++success_count_;
            success_f_.push_back(f_i);
            success_cr_.push_back(cr_i);
        } else {
            if (!is_elite) new_pop[i] = pop_[i];
        }
    }
    pop_ = new_pop;

    // Stagnation tracking
    double cur_best = best_fitness();
    if (cur_best < prev_best_ - 1e-12) stagnation_ = 0;
    else                                ++stagnation_;
    prev_best_ = cur_best;

    jade_end_generation();
    ++generation_;
}

Chromosome Island::best_chromosome() const {
    return *std::min_element(pop_.begin(), pop_.end(),
        [](const Chromosome& a, const Chromosome& b){
            return a.fitness < b.fitness;
        });
}

double Island::best_fitness() const {
    return best_chromosome().fitness;
}

double Island::success_rate() const {
    return (trial_count_ > 0) ? static_cast<double>(success_count_) / trial_count_ : 0.0;
}

void Island::accept_migrants(const std::vector<Chromosome>& migrants) {
    if (migrants.empty()) return;
    // Sort current population, replace worst
    std::vector<int> idx(pop_.size());
    std::iota(idx.begin(), idx.end(), 0);
    std::partial_sort(idx.begin(), idx.begin() + (int)migrants.size(), idx.end(),
        [&](int a, int b){ return pop_[a].fitness > pop_[b].fitness; }); // worst first
    for (size_t m = 0; m < migrants.size() && m < idx.size(); ++m)
        pop_[idx[m]] = migrants[m];
}

void Island::update_config(const DEConfig& new_cfg) {
    cfg_ = new_cfg;
    mu_f_  = new_cfg.mu_f;
    mu_cr_ = new_cfg.mu_cr;
}

// ─────────────────────────────────────────────────────────────────────────
//  DifferentialEvolutionOptimizer
// ─────────────────────────────────────────────────────────────────────────

void DifferentialEvolutionOptimizer::initialize(
    const double* train_data, int train_rows,
    const double* val_data,   int val_rows,
    const double* test_data,  int test_rows,
    int cols, int output_col,
    const FitnessWeights& weights
) {
    train_data_ = train_data; train_rows_ = train_rows;
    val_data_   = val_data;   val_rows_   = val_rows;
    test_data_  = test_data;  test_rows_  = test_rows;
    cols_       = cols;       output_col_ = output_col;

    islands_.clear();
    for (int i = 0; i < cfg_.num_islands; ++i) {
        uint64_t seed = static_cast<uint64_t>(std::chrono::steady_clock::now()
                        .time_since_epoch().count()) + i * 104729ULL;
        islands_.push_back(std::make_unique<Island>(
            i, cfg_, seed,
            train_data_, train_rows_, val_data_, val_rows_,
            cols_, output_col_, weights
        ));
    }
}

void DifferentialEvolutionOptimizer::migrate() {
    if (islands_.size() < 2) return;
    int n = static_cast<int>(islands_.size());
    int n_migrants = std::max(1, static_cast<int>(
        cfg_.population_size * cfg_.migration_rate));

    for (int i = 0; i < n; ++i) {
        auto& src = *islands_[i];
        auto& dst = *islands_[(i + 1) % n];

        // Pick best n_migrants from src
        auto& pop = src.population();
        std::vector<int> idx(pop.size());
        std::iota(idx.begin(), idx.end(), 0);
        std::partial_sort(idx.begin(), idx.begin() + n_migrants, idx.end(),
            [&](int a, int b){ return pop[a].fitness < pop[b].fitness; });

        std::vector<Chromosome> migrants;
        for (int m = 0; m < n_migrants && m < (int)idx.size(); ++m)
            migrants.push_back(pop[idx[m]]);

        dst.accept_migrants(migrants);
    }
}

GenerationReport DifferentialEvolutionOptimizer::build_report(int generation) const {
    GenerationReport r;
    r.generation = generation;

    Chromosome best = best_chromosome();
    r.best_fitness  = best.fitness;
    r.num_terms     = best.num_regressors();

    if (!best.coefficients.empty()) {
        r.best_coefficients = best.coefficients;
    }
    for (const auto& reg : best.regressors)
        for (const auto& t : reg.terms)
            r.best_exponents.push_back(t.exponent);

    // Aggregate island stats
    if (!islands_.empty()) {
        r.mu_f  = islands_[0]->mu_f();
        r.mu_cr = islands_[0]->mu_cr();
        r.stagnation = 0;
        for (const auto& isl : islands_)
            r.stagnation = std::max(r.stagnation, isl->stagnation());

        // Diversity: unique hashes
        std::unordered_set<uint32_t> hashes;
        double var_sum = 0.0; int pop_count = 0;
        for (const auto& isl : islands_) {
            for (const auto& c : isl->population()) {
                hashes.insert(c.structural_hash());
                if (c.evaluated && std::isfinite(c.fitness)) {
                    var_sum += c.fitness;
                    ++pop_count;
                }
            }
        }
        double mean_fit = pop_count > 0 ? var_sum / pop_count : 0.0;
        double var = 0.0;
        for (const auto& isl : islands_)
            for (const auto& c : isl->population())
                if (c.evaluated && std::isfinite(c.fitness)) {
                    double d = c.fitness - mean_fit;
                    var += d * d;
                }
        if (pop_count > 1) var /= pop_count;
        r.population_diversity = std::sqrt(var);
    }

    if (!best.err.empty())
        r.residual_autocorr = best.err; // reuse slot for now

    return r;
}

#ifndef __EMSCRIPTEN__
void DifferentialEvolutionOptimizer::run_async(
    ProgressCallback on_progress, ShouldStopFn should_stop
) {
    stop_flag_.store(false);
    worker_thread_ = std::thread([this, on_progress, should_stop] {
        int global_stagnation = 0;
        double prev_best = std::numeric_limits<double>::infinity();

        for (int gen = 0; gen < cfg_.max_generations; ++gen) {
            if (stop_flag_.load()) break;

            // Check pause (set by apply_tuning with pause-like semantics)
            // Pause is handled externally by the pipeline.

            // Check external stop
            if (should_stop && should_stop()) break;

            // Run one generation on each island (parallelised by thread pool)
            {
                std::lock_guard<std::mutex> lk(islands_mutex_);
                for (auto& isl : islands_) {
                    isl->run_generation();
                }
            }

            // Migration
            if (cfg_.migration_interval > 0 && gen % cfg_.migration_interval == 0) {
                std::lock_guard<std::mutex> lk(islands_mutex_);
                migrate();
            }

            // Stagnation tracking
            double cur = best_chromosome().fitness;
            if (cur < prev_best - 1e-12) global_stagnation = 0;
            else                          ++global_stagnation;
            prev_best = cur;

            if (global_stagnation >= cfg_.stagnation_limit) break;

            // Build and emit progress report
            GenerationReport rpt;
            {
                std::lock_guard<std::mutex> lk(islands_mutex_);
                rpt = build_report(gen);
            }
            if (on_progress) on_progress(rpt);
        }
    });
}
#endif // !__EMSCRIPTEN__

int DifferentialEvolutionOptimizer::run_steps(
    int n, ProgressCallback on_progress, ShouldStopFn should_stop
) {
    int ran = 0;
    for (int i = 0; i < n; ++i) {
        if (current_gen_ >= cfg_.max_generations) break;
        if (global_stagnation_sync_ >= cfg_.stagnation_limit) break;
        if (should_stop && should_stop()) break;

        for (auto& isl : islands_)
            isl->run_generation();

        if (cfg_.migration_interval > 0 && current_gen_ % cfg_.migration_interval == 0)
            migrate();

        double cur = best_chromosome().fitness;
        if (cur < prev_best_sync_ - 1e-12) global_stagnation_sync_ = 0;
        else                                ++global_stagnation_sync_;
        prev_best_sync_ = cur;

        GenerationReport rpt;
        {
            std::lock_guard<std::mutex> lk(islands_mutex_);
            rpt = build_report(current_gen_);
        }
        if (on_progress) on_progress(rpt);

        ++current_gen_;
        ++ran;
    }
    return ran;
}

bool DifferentialEvolutionOptimizer::is_done() const {
    return current_gen_ >= cfg_.max_generations ||
           global_stagnation_sync_ >= cfg_.stagnation_limit;
}

void DifferentialEvolutionOptimizer::stop() {
    stop_flag_.store(true);
    if (worker_thread_.joinable()) worker_thread_.join();
}

void DifferentialEvolutionOptimizer::wait() {
    if (worker_thread_.joinable()) worker_thread_.join();
}

Chromosome DifferentialEvolutionOptimizer::best_chromosome() const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    Chromosome best;
    best.fitness = std::numeric_limits<double>::infinity();
    for (const auto& isl : islands_) {
        Chromosome b = isl->best_chromosome();
        if (b.fitness < best.fitness) best = b;
    }
    return best;
}

void DifferentialEvolutionOptimizer::apply_tuning(
    const std::string& param, double value
) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    if (param == "mutationFactor") {
        cfg_.mu_f = value;
        for (auto& isl : islands_) {
            DEConfig nc = isl->config(); nc.mu_f = value;
            isl->update_config(nc);
        }
    } else if (param == "crossoverRate") {
        cfg_.mu_cr = value;
        for (auto& isl : islands_) {
            DEConfig nc = isl->config(); nc.mu_cr = value;
            isl->update_config(nc);
        }
    } else if (param == "migrationRate") {
        cfg_.migration_rate = value;
    } else if (param == "migrationInterval") {
        cfg_.migration_interval = static_cast<int>(value);
    } else if (param == "stagnationLimit") {
        cfg_.stagnation_limit = static_cast<int>(value);
    }
    // Other params are reflected in cfg_ for next iteration
}

} // namespace aegis
