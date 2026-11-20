#include "aegis/de_optimizer.hpp"
#include "aegis/safe_power.hpp"
#include <algorithm>
#include <numeric>
#include <cmath>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#include <stdexcept>
#include <sstream>
#include <chrono>
#include <unordered_map>
#include <unordered_set>
#include <thread>

namespace aegis {

// ─────────────────────────────────────────────────────────────────────────
//  Regressor label helpers
// ─────────────────────────────────────────────────────────────────────────

static std::string make_term_label(const Term& t, int num_variables, int output_col) {
    std::string label;
    if (t.variable == output_col) {
        label = "y";
    } else {
        label = (num_variables <= 2) ? "u" : "u" + std::to_string(t.variable + 1);
    }
    label += "(k-" + std::to_string(t.delay) + ")";
    double ex = t.exponent;
    if (std::abs(ex - 1.0) > 1e-9) {
        double ex_round = std::round(ex);
        if (std::abs(ex - ex_round) < 1e-9) {
            label += "^" + std::to_string(static_cast<int>(ex_round));
        } else {
            std::ostringstream ss;
            ss.precision(4);
            ss << "^" << ex;
            label += ss.str();
        }
    }
    return label;
}

static std::string make_regressor_label(const Regressor& reg, int num_variables, int output_col) {
    if (reg.terms.empty()) return "const";
    std::string label;
    for (const auto& t : reg.terms) {
        if (!label.empty()) label += "*";
        label += make_term_label(t, num_variables, output_col);
    }
    if (reg.is_denominator()) label += " [den]";
    return label;
}

static void fitness_stats(const std::vector<Chromosome>& pop, IslandReport& r) {
    std::vector<double> f;
    f.reserve(pop.size());
    for (const auto& c : pop)
        if (c.evaluated && std::isfinite(c.fitness)) f.push_back(c.fitness);
    if (f.empty()) return;
    std::sort(f.begin(), f.end());
    const size_t n = f.size();
    double mean = std::accumulate(f.begin(), f.end(), 0.0) / static_cast<double>(n);
    double var = 0.0;
    for (double v : f) var += (v - mean) * (v - mean);
    var /= static_cast<double>(n);
    r.best_fitness   = f.front();
    r.worst_fitness  = f.back();
    r.mean_fitness   = mean;
    r.median_fitness = (n % 2) ? f[n / 2] : 0.5 * (f[n / 2 - 1] + f[n / 2]);
    r.std_fitness    = std::sqrt(var);
}

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
    for (auto& c : pop_) evaluate(c);
}

void Island::evaluate(Chromosome& c) {
    evaluator_.evaluate(c, train_data_, train_rows_, val_data_, val_rows_, cols_, output_col_);
}

// ── Chromosome factory ────────────────────────────────────────────────────

Term Island::random_term(bool denom) {
    std::uniform_int_distribution<int> rn_var(0, std::max(0, cfg_.num_variables - 1));
    std::uniform_int_distribution<int> rn_delay(1, std::max(1, cfg_.max_delay));
    std::uniform_real_distribution<double> rn_exp(cfg_.pmin, std::max(cfg_.pmin, cfg_.pmax));
    Term t;
    t.variable = rn_var(rng_);
    t.delay = rn_delay(rng_);
    t.exponent = quantize_exponent(rn_exp(rng_), cfg_.pmin, cfg_.pmax, cfg_.exponent_step);
    t.is_denominator = denom;
    return t;
}

Regressor Island::random_regressor() {
    std::uniform_int_distribution<int> rn_terms(1, std::max(1, cfg_.max_terms_per_reg));
    std::uniform_real_distribution<double> u01(0.0, 1.0);
    const bool denom = u01(rng_) < cfg_.denominator_probability;
    Regressor reg;
    const int n_terms = rn_terms(rng_);
    for (int t = 0; t < n_terms; ++t) reg.terms.push_back(random_term(denom));
    return reg;
}

Chromosome Island::random_chromosome() {
    std::uniform_int_distribution<int> rn_reg(1, std::max(1, cfg_.max_regressors));
    Chromosome c;
    c.power_mode = cfg_.power_mode;
    const int n_reg = rn_reg(rng_);
    for (int j = 0; j < n_reg; ++j) c.regressors.push_back(random_regressor());
    repair(c);
    return c;
}

void Island::repair(Chromosome& c) {
    c.power_mode = cfg_.power_mode;
    for (auto& reg : c.regressors) {
        if (static_cast<int>(reg.terms.size()) > cfg_.max_terms_per_reg)
            reg.terms.resize(cfg_.max_terms_per_reg);
        for (auto& t : reg.terms) {
            t.variable = std::max(0, std::min(cfg_.num_variables - 1, t.variable));
            t.delay = std::max(1, std::min(cfg_.max_delay, t.delay));
            t.exponent = quantize_exponent(t.exponent, cfg_.pmin, cfg_.pmax, cfg_.exponent_step);
            if (cfg_.denominator_probability <= 0.0) t.is_denominator = false;
        }
    }
    c.canonicalize();
    if (static_cast<int>(c.regressors.size()) > cfg_.max_regressors)
        c.regressors.resize(cfg_.max_regressors);
    if (c.regressors.empty()) c.regressors.push_back(random_regressor());
    c.invalidate();
}

// ── PRNG helpers ──────────────────────────────────────────────────────────

double Island::gauss_rand(double mean, double std) {
    std::normal_distribution<double> nd;
    return nd(rng_) * std + mean;
}

double Island::cauchy_rand(double loc, double scale) {
    std::uniform_real_distribution<double> u(0.0, 1.0);
    double val;
    do { val = loc + scale * std::tan(M_PI * (u(rng_) - 0.5)); }
    while (!std::isfinite(val));
    return val;
}

double Island::lehmer_mean(const std::vector<double>& v) const {
    if (v.empty()) return mu_f_;
    double s2 = 0.0, s1 = 0.0;
    for (double x : v) { s2 += x * x; s1 += x; }
    return s1 < 1e-30 ? mu_f_ : s2 / s1;
}

// ── Mutation (DE on variable-length structures) ───────────────────────────

static const Term* term_at(const Chromosome& c, int j, int t) {
    if (j < 0 || j >= static_cast<int>(c.regressors.size())) return nullptr;
    const auto& r = c.regressors[j];
    if (t < 0 || t >= static_cast<int>(r.terms.size())) return nullptr;
    return &r.terms[t];
}

Chromosome Island::mutate(int target_idx, double& f_i, double& cr_i) {
    const bool jade = cfg_.strategy == MutationStrategy::JadeCurrentToPBest;
    if (jade) {
        // F ~ Cauchy(μF, 0.1), regenerated if ≤ 0, truncated to 1 (JADE).
        do { f_i = cauchy_rand(mu_f_, 0.1); } while (f_i <= 0.0);
        f_i = std::min(f_i, 1.0);
        cr_i = clamp(gauss_rand(mu_cr_, 0.1), 0.0, 1.0);
    } else {
        f_i = mu_f_;
        cr_i = mu_cr_;
    }

    const int sz = static_cast<int>(pop_.size());
    if (sz < 4) return pop_[target_idx];
    std::uniform_int_distribution<int> pick(0, sz - 1);
    auto draw_distinct = [&](std::initializer_list<int> excl) {
        int r;
        do {
            r = pick(rng_);
        } while (std::find(excl.begin(), excl.end(), r) != excl.end());
        return r;
    };

    int base_idx, pbest = -1;
    if (jade) {
        // p-best among the top max(2, ⌈p·NP⌉) individuals.
        const int p_top = std::max(2, std::min(sz, static_cast<int>(std::ceil(cfg_.jade_p * sz))));
        std::vector<int> idx(sz);
        std::iota(idx.begin(), idx.end(), 0);
        std::partial_sort(idx.begin(), idx.begin() + p_top, idx.end(),
            [&](int a, int b) { return pop_[a].fitness < pop_[b].fitness; });
        std::uniform_int_distribution<int> pb(0, p_top - 1);
        pbest = idx[pb(rng_)];
        base_idx = target_idx;
    } else {
        base_idx = draw_distinct({target_idx});
    }
    const int r1 = draw_distinct({target_idx, base_idx, pbest});
    const int r2 = draw_distinct({target_idx, base_idx, pbest, r1});

    const Chromosome& xb  = pop_[base_idx];               // x_i (JADE) or x_r0 (rand1)
    const Chromosome* xpb = pbest >= 0 ? &pop_[pbest] : nullptr;
    const Chromosome& xr1 = pop_[r1];
    const Chromosome& xr2 = pop_[r2];

    // Length (number of regressors) follows the same DE rule.
    auto len = [](const Chromosome& c) { return static_cast<double>(c.regressors.size()); };
    double nlen = len(xb) + f_i * (len(xr1) - len(xr2));
    if (xpb) nlen += f_i * (len(*xpb) - len(xb));
    const int n_v = std::max(1, std::min(cfg_.max_regressors, static_cast<int>(std::lround(nlen))));

    std::uniform_real_distribution<double> u01(0.0, 1.0);
    std::uniform_int_distribution<int> rn_var(0, std::max(0, cfg_.num_variables - 1));

    Chromosome mutant;
    mutant.power_mode = cfg_.power_mode;
    for (int j = 0; j < n_v; ++j) {
        const bool in_b  = j < static_cast<int>(xb.regressors.size());
        const bool in_pb = xpb && j < static_cast<int>(xpb->regressors.size());
        Regressor base;
        if (in_b && in_pb)      base = (u01(rng_) < 0.5) ? xb.regressors[j] : xpb->regressors[j];
        else if (in_b)          base = xb.regressors[j];
        else if (in_pb)         base = xpb->regressors[j];
        else if (j < static_cast<int>(xr1.regressors.size())) base = xr1.regressors[j];
        else if (j < static_cast<int>(xr2.regressors.size())) base = xr2.regressors[j];
        else                    base = random_regressor();

        for (int t = 0; t < static_cast<int>(base.terms.size()); ++t) {
            Term& term = base.terms[t];
            const Term* tb  = term_at(xb, j, t);
            const Term* tpb = xpb ? term_at(*xpb, j, t) : nullptr;
            const Term* t1  = term_at(xr1, j, t);
            const Term* t2  = term_at(xr2, j, t);
            const double e0 = tb ? tb->exponent : term.exponent;
            const double d0 = tb ? static_cast<double>(tb->delay) : static_cast<double>(term.delay);
            double ne = e0, nd = d0;
            if (tpb) { ne += f_i * (tpb->exponent - e0); nd += f_i * (tpb->delay - d0); }
            if (t1 && t2) { ne += f_i * (t1->exponent - t2->exponent); nd += f_i * (t1->delay - t2->delay); }
            term.exponent = quantize_exponent(ne, cfg_.pmin, cfg_.pmax, cfg_.exponent_step);
            term.delay = std::max(1, std::min(cfg_.max_delay, static_cast<int>(std::lround(nd))));
            if (u01(rng_) < cfg_.variable_mutation_rate) term.variable = rn_var(rng_);
        }
        mutant.regressors.push_back(std::move(base));
    }
    if (u01(rng_) < cfg_.structural_mutation_rate) structural_mutation(mutant);
    if (mutant.regressors.empty()) mutant.regressors.push_back(random_regressor());
    return mutant;
}

void Island::structural_mutation(Chromosome& c) {
    std::uniform_int_distribution<int> op(0, 2);
    const int n = static_cast<int>(c.regressors.size());
    int kind = op(rng_);
    if (kind == 0 && n >= cfg_.max_regressors) kind = 2;
    if (kind == 1 && n <= 1) kind = 0;
    if (kind == 0) {
        c.regressors.push_back(random_regressor());
    } else {
        std::uniform_int_distribution<int> pos(0, std::max(0, n - 1));
        const int p = pos(rng_);
        if (kind == 1) c.regressors.erase(c.regressors.begin() + p);
        else           c.regressors[p] = random_regressor();
    }
}

// ── Binomial crossover (variable length, can shrink and grow) ─────────────

Chromosome Island::crossover_binomial(
    const Chromosome& target, const Chromosome& mutant, double cr
) {
    Chromosome trial;
    trial.power_mode = cfg_.power_mode;
    std::uniform_real_distribution<double> u01(0.0, 1.0);
    const int nt = static_cast<int>(target.regressors.size());
    const int nm = static_cast<int>(mutant.regressors.size());
    const int max_r = std::max(nt, nm);
    std::uniform_int_distribution<int> jrand(0, std::max(0, nm - 1));
    const int j_rand = jrand(rng_);  // guarantees at least one mutant regressor
    for (int j = 0; j < max_r; ++j) {
        const bool take_mutant = (u01(rng_) < cr) || (j == j_rand);
        const Chromosome& src = take_mutant ? mutant : target;
        if (j < static_cast<int>(src.regressors.size()))
            trial.regressors.push_back(src.regressors[j]);
    }
    if (trial.regressors.empty()) trial.regressors = mutant.regressors;
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
}

// ── run_generation ───────────────────────────────────────────────────────

void Island::run_generation() {
    const int sz = static_cast<int>(pop_.size());
    success_count_ = 0;
    trial_count_   = 0;
    const bool jade = cfg_.strategy == MutationStrategy::JadeCurrentToPBest;

    // Synchronous DE: donors are taken from the parent population; every
    // individual produces one trial and greedy selection keeps the better.
    std::vector<Chromosome> new_pop = pop_;
    for (int i = 0; i < sz; ++i) {
        ++trial_count_;
        double f_i, cr_i;
        Chromosome mutant = mutate(i, f_i, cr_i);
        Chromosome trial  = crossover_binomial(pop_[i], mutant, cr_i);
        repair(trial);
        evaluate(trial);
        if (trial.evaluated && trial.fitness < pop_[i].fitness) {
            new_pop[i] = std::move(trial);
            ++success_count_;
            success_f_.push_back(f_i);
            success_cr_.push_back(cr_i);
        }
    }
    pop_ = std::move(new_pop);

    // Triggered hypermutation (JADE only): sustained zero success → widen F.
    if (success_count_ == 0) ++zero_success_streak_;
    else                     zero_success_streak_ = 0;
    if (jade && cfg_.hypermutation && zero_success_streak_ >= cfg_.hypermutation_trigger) {
        mu_f_ = clamp(mu_f_ * cfg_.hypermutation_boost, 0.01, 0.99);
        zero_success_streak_ = 0;
    }

    const double cur_best = best_fitness();
    if (cur_best < prev_best_ - 1e-12) stagnation_ = 0;
    else                                ++stagnation_;
    prev_best_ = cur_best;

    if (cfg_.reinit_ratio > 0.0 && cfg_.reinit_interval > 0 && stagnation_ > 0 &&
        stagnation_ % cfg_.reinit_interval == 0) {
        reinitialize_worst();
    }

    if (jade) jade_end_generation();
    else { success_f_.clear(); success_cr_.clear(); }
    ++generation_;
}

void Island::reinitialize_worst() {
    const int sz = static_cast<int>(pop_.size());
    int n_reinit = std::max(1, static_cast<int>(std::ceil(sz * cfg_.reinit_ratio)));
    n_reinit = std::min(n_reinit, sz - std::min(std::max(cfg_.elitism_count, 1), sz));
    if (n_reinit <= 0) return;

    std::vector<int> idx(sz);
    std::iota(idx.begin(), idx.end(), 0);
    std::sort(idx.begin(), idx.end(),
              [&](int a, int b){ return pop_[a].fitness > pop_[b].fitness; }); // worst first
    for (int k = 0; k < n_reinit; ++k) {
        Chromosome c = random_chromosome();
        evaluate(c);
        pop_[idx[k]] = std::move(c);
    }
}

void Island::restart(double ratio) {
    const double saved_ratio = cfg_.reinit_ratio;
    cfg_.reinit_ratio = ratio;
    reinitialize_worst();
    cfg_.reinit_ratio = saved_ratio;
    mu_f_  = cfg_.mu_f;
    mu_cr_ = cfg_.mu_cr;
    success_f_.clear();
    success_cr_.clear();
    success_count_ = 0;
    trial_count_   = 0;
    zero_success_streak_ = 0;
    stagnation_ = 0;
    prev_best_ = best_fitness();
}

const Chromosome& Island::best_ref() const {
    return *std::min_element(pop_.begin(), pop_.end(),
        [](const Chromosome& a, const Chromosome& b){ return a.fitness < b.fitness; });
}

Chromosome Island::best_chromosome() const { return best_ref(); }

double Island::best_fitness() const { return best_ref().fitness; }

double Island::success_rate() const {
    return (trial_count_ > 0) ? static_cast<double>(success_count_) / trial_count_ : 0.0;
}

void Island::accept_migrants(const std::vector<Chromosome>& migrants) {
    if (migrants.empty()) return;
    const size_t count = std::min(migrants.size(), pop_.size());
    std::vector<int> idx(pop_.size());
    std::iota(idx.begin(), idx.end(), 0);
    std::partial_sort(idx.begin(), idx.begin() + static_cast<long>(count), idx.end(),
        [&](int a, int b){ return pop_[a].fitness > pop_[b].fitness; }); // worst first
    for (size_t m = 0; m < count; ++m) pop_[idx[m]] = migrants[m];
}

void Island::reevaluate(Chromosome& c) const {
    evaluator_.evaluate(c, train_data_, train_rows_, val_data_, val_rows_, cols_, output_col_);
    if (!c.evaluated || !std::isfinite(c.fitness)) return;
    ++c.contexts_survived;
    if (std::isnan(c.worst_fitness_seen) || c.fitness > c.worst_fitness_seen)
        c.worst_fitness_seen = c.fitness;
}

void Island::reevaluate_population() {
    for (auto& c : pop_) evaluate(c);
    stagnation_ = 0;
    prev_best_ = best_fitness();
}

void Island::update_weights(const FitnessWeights& w) {
    const bool horizon_changed = w.free_run_horizon != evaluator_.weights().free_run_horizon;
    evaluator_.weights() = w;
    if (horizon_changed) {
        reevaluate_population();
        return;
    }
    for (auto& c : pop_) {
        if (!evaluator_.rescore(c, output_col_)) {
            c.evaluated = false;
            c.fitness = std::numeric_limits<double>::infinity();
        }
    }
    stagnation_ = 0;
    prev_best_ = best_fitness();
}

void Island::set_validation_window(const double* val_data, int val_rows) {
    val_data_ = val_data;
    val_rows_ = val_rows;
    reevaluate_population();
}

void Island::update_config(const DEConfig& new_cfg) {
    cfg_ = new_cfg; // JADE means mu_f_/mu_cr_ intentionally preserved
}

IslandReport Island::report() const {
    IslandReport r;
    r.id = id_;
    fitness_stats(pop_, r);
    r.stagnation = stagnation_;
    r.success_rate = success_rate();
    r.mu_f = mu_f_;
    r.mu_cr = mu_cr_;
    r.population_size = static_cast<int>(pop_.size());
    std::unordered_set<uint32_t> hs;
    double nreg = 0.0;
    for (const auto& c : pop_) { hs.insert(c.structural_hash()); nreg += c.num_regressors(); }
    r.unique_structures = static_cast<int>(hs.size());
    r.mean_num_regressors = pop_.empty() ? 0.0 : nreg / pop_.size();
    r.best_rmse_val = best_ref().metrics.rmse_val;
    return r;
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
    std::lock_guard<std::mutex> lk(islands_mutex_);
    train_data_ = train_data; train_rows_ = train_rows;
    val_data_   = val_data;   val_rows_   = val_rows;
    test_data_  = test_data;  test_rows_  = test_rows;
    cols_       = cols;       output_col_ = output_col;

    canonical_eval_ = IndividualEvaluator(weights);
    canonical_cache_.clear();
    champion_ = Chromosome();
    champion_valid_ = false;
    champion_diag_ = ModelDiagnostics();
    champion_diag_hash_ = 0;
    current_gen_.store(0);
    global_stagnation_ = 0;
    prev_best_ = std::numeric_limits<double>::infinity();
    stop_reason_.clear();
    done_ = false;
    stop_flag_.store(false);

    islands_.clear();
    for (int i = 0; i < cfg_.num_islands; ++i) {
        uint64_t seed = cfg_.random_seed != 0
            ? cfg_.random_seed + static_cast<uint64_t>(i) * 104729ULL
            : static_cast<uint64_t>(std::chrono::steady_clock::now()
                .time_since_epoch().count()) + static_cast<uint64_t>(i) * 104729ULL;
        islands_.push_back(std::make_unique<Island>(
            i, cfg_, seed,
            train_data_, train_rows_, val_data_, val_rows_,
            cols_, output_col_, weights
        ));
    }
    if (static_cast<int>(island_roles_.size()) != cfg_.num_islands)
        island_roles_.assign(cfg_.num_islands, "balanced");
    update_champion_locked();
    prev_best_ = champion_valid_ ? champion_.fitness : prev_best_;
}

Chromosome DifferentialEvolutionOptimizer::canonical_evaluate_locked(const Chromosome& c) {
    const uint64_t h = c.full_hash();
    auto it = canonical_cache_.find(h);
    if (it != canonical_cache_.end()) {
        Chromosome cached = it->second;
        cached.contexts_survived = c.contexts_survived;
        cached.worst_fitness_seen = c.worst_fitness_seen;
        return cached;
    }
    Chromosome copy = c;
    canonical_eval_.evaluate(copy, train_data_, train_rows_, val_data_, val_rows_, cols_, output_col_);
    if (canonical_cache_.size() > 2048) canonical_cache_.clear();
    canonical_cache_.emplace(h, copy);
    return copy;
}

void DifferentialEvolutionOptimizer::update_champion_locked() {
    for (const auto& isl : islands_) {
        const Chromosome& ib = isl->best_ref();
        if (!ib.evaluated) continue;
        Chromosome cand = canonical_evaluate_locked(ib);
        if (!cand.evaluated || !std::isfinite(cand.fitness)) continue;
        if (!champion_valid_ || cand.fitness < champion_.fitness) {
            champion_ = std::move(cand);
            champion_valid_ = true;
        }
    }
}

void DifferentialEvolutionOptimizer::migrate() {
    if (islands_.size() < 2 || cfg_.migration_rate <= 0.0) return;
    const int n = static_cast<int>(islands_.size());
    int n_migrants = std::max(1, static_cast<int>(cfg_.population_size * cfg_.migration_rate));
    n_migrants = std::min(n_migrants, cfg_.population_size);

    for (int i = 0; i < n; ++i) {
        auto& src = *islands_[i];
        auto& dst = *islands_[(i + 1) % n];  // ring topology
        auto& pop = src.population();
        std::vector<int> idx(pop.size());
        std::iota(idx.begin(), idx.end(), 0);
        const int k = std::min<int>(n_migrants, static_cast<int>(idx.size()));
        std::partial_sort(idx.begin(), idx.begin() + k, idx.end(),
            [&](int a, int b){ return pop[a].fitness < pop[b].fitness; });

        // Two-layer filter: reevaluate under the destination's weights and
        // regime; accept only migrants better than the destination's worst.
        double dst_worst = -std::numeric_limits<double>::infinity();
        for (const auto& c : dst.population()) dst_worst = std::max(dst_worst, c.fitness);

        std::vector<Chromosome> migrants;
        for (int m = 0; m < k; ++m) {
            Chromosome cand = pop[idx[m]];
            dst.reevaluate(cand);
            if (cand.evaluated && std::isfinite(cand.fitness) && cand.fitness < dst_worst)
                migrants.push_back(std::move(cand));
        }
        // Escape valve for a stagnant source island.
        if (migrants.empty() && !idx.empty() && src.stagnation() >= cfg_.reinit_interval) {
            Chromosome cand = pop[idx[0]];
            dst.reevaluate(cand);
            if (cand.evaluated && std::isfinite(cand.fitness)) migrants.push_back(std::move(cand));
        }
        if (!migrants.empty()) dst.accept_migrants(migrants);
    }
}

bool DifferentialEvolutionOptimizer::check_stop_locked() {
    if (done_) return true;
    const long long evals = [&] {
        long long e = canonical_eval_.evaluations();
        for (const auto& isl : islands_) e += isl->evaluations();
        return e;
    }();
    if (current_gen_.load() >= cfg_.max_generations) stop_reason_ = "max_generations";
    else if (global_stagnation_ >= cfg_.stagnation_limit) stop_reason_ = "stagnation";
    else if (cfg_.max_evaluations > 0 && evals >= cfg_.max_evaluations) stop_reason_ = "max_evaluations";
    done_ = !stop_reason_.empty();
    return done_;
}

GenerationReport DifferentialEvolutionOptimizer::step_generation_locked() {
    const bool parallel = cfg_.num_threads != 1 && islands_.size() > 1;
    if (parallel) {
        std::vector<std::thread> workers;
        workers.reserve(islands_.size());
        for (auto& isl : islands_)
            workers.emplace_back([island = isl.get()] { island->run_generation(); });
        for (auto& w : workers) w.join();
    } else {
        for (auto& isl : islands_) isl->run_generation();
    }
    const int gen = current_gen_.fetch_add(1) + 1;

    if (cfg_.migration_interval > 0 && gen % cfg_.migration_interval == 0) migrate();

    update_champion_locked();
    const double cur = champion_valid_ ? champion_.fitness : std::numeric_limits<double>::infinity();
    const double tol = 1e-12 + 1e-9 * std::abs(prev_best_);
    if (std::isfinite(prev_best_) ? (cur < prev_best_ - tol) : std::isfinite(cur)) global_stagnation_ = 0;
    else ++global_stagnation_;
    prev_best_ = std::min(prev_best_, cur);

    check_stop_locked();
    GenerationReport rpt = build_report_locked();
    rpt.stop_reason = stop_reason_;
    return rpt;
}

GenerationReport DifferentialEvolutionOptimizer::build_report_locked() {
    GenerationReport r;
    r.generation = current_gen_.load();
    r.evaluations = canonical_eval_.evaluations();
    for (const auto& isl : islands_) r.evaluations += isl->evaluations();
    r.global_stagnation = global_stagnation_;
    r.island_roles = island_roles_;

    if (champion_valid_) {
        const Chromosome& best = champion_;
        r.best_fitness   = best.fitness;
        r.num_terms      = best.num_regressors();
        r.num_factors    = best.num_terms();
        r.best_max_delay = best.max_delay();
        r.best_max_exponent = best.max_exponent();
        r.best_is_rational = best.is_rational();
        r.best_contexts_survived  = best.contexts_survived;
        r.best_worst_fitness_seen = best.worst_fitness_seen;
        r.rmse_train = best.metrics.rmse_train;
        r.rmse_val   = best.metrics.rmse_val;
        r.bic        = best.metrics.bic;
        r.aic        = best.metrics.aic;
        r.r2_train   = best.metrics.r2_train;
        r.r2_val     = best.metrics.r2_val;
        r.best_coefficients = best.coefficients;
        r.best_intercept    = best.intercept;
        r.best_err          = best.err;
        for (const auto& reg : best.regressors) {
            for (const auto& t : reg.terms) r.best_exponents.push_back(t.exponent);
            r.best_term_labels.push_back(make_regressor_label(reg, cfg_.num_variables, output_col_));
        }
        r.free_run_rmse            = best.metrics.rmse_free_run;
        r.input_contribution_ratio = best.metrics.input_contribution_ratio;
        r.residual_input_corr      = best.metrics.residual_input_corr;
        r.fitness_breakdown        = best.fitness_breakdown;
        r.stability                = best.stability;

        const uint64_t h = best.full_hash();
        if (h != champion_diag_hash_ || !champion_diag_.valid) {
            champion_diag_ = canonical_eval_.diagnose(best, train_data_, train_rows_,
                                                      val_data_, val_rows_, cols_, output_col_);
            champion_diag_hash_ = h;
        }
        r.diagnostics = champion_diag_;
        r.residual_autocorr = champion_diag_.residual_acf;
        r.is_stable = best.stability.is_stable && !champion_diag_.free_run_val_diverged;
        r.overfitting = champion_diag_.overfitting;
        r.underfitting = champion_diag_.underfitting;

        std::string alerts;
        auto add = [&](const char* a) { if (!alerts.empty()) alerts += "; "; alerts += a; };
        if (best.stability.free_run_diverged) add("free-run diverged within horizon");
        if (champion_diag_.free_run_val_diverged) add("free-run diverged on full validation");
        if (best.is_rational() && std::isfinite(best.stability.min_abs_denominator) &&
            best.stability.min_abs_denominator < StabilityAnalyzer::kDenominatorMargin)
            add("rational denominator close to zero");
        if (best.stability.denominator_sign_changes > 0) add("rational denominator changes sign");
        if (champion_diag_.overfitting) add("overfitting (validation/training RMSE gap)");
        if (champion_diag_.underfitting) add("underfitting");
        if (champion_diag_.valid && !champion_diag_.residual_white) add("residuals not white");
        r.alerts = alerts;
    }

    if (!islands_.empty()) {
        std::unordered_map<uint32_t, int> hash_counts;
        int total = 0;
        double sum_std = 0.0, sum_var = 0.0, sum_sr = 0.0, sum_mf = 0.0, sum_mcr = 0.0,
               sum_mean = 0.0, sum_nreg = 0.0;
        int n_stat = 0;
        std::vector<double> medians;
        for (size_t i = 0; i < islands_.size(); ++i) {
            IslandReport ir = islands_[i]->report();
            ir.role = i < island_roles_.size() ? island_roles_[i] : "balanced";
            if (std::isfinite(ir.std_fitness)) {
                sum_std += ir.std_fitness;
                sum_var += ir.std_fitness * ir.std_fitness;
                sum_mean += ir.mean_fitness;
                medians.push_back(ir.median_fitness);
                ++n_stat;
            }
            sum_sr += ir.success_rate;
            sum_mf += ir.mu_f;
            sum_mcr += ir.mu_cr;
            sum_nreg += ir.mean_num_regressors;
            r.stagnation = std::max(r.stagnation, ir.stagnation);
            for (const auto& c : islands_[i]->population()) {
                ++hash_counts[c.structural_hash()];
                ++total;
            }
            r.islands.push_back(std::move(ir));
        }
        const double ni = static_cast<double>(islands_.size());
        if (n_stat > 0) {
            r.population_diversity = sum_std / n_stat;
            r.population_variance  = sum_var / n_stat;
            r.fitness_mean = sum_mean / n_stat;
            std::sort(medians.begin(), medians.end());
            const size_t m = medians.size();
            r.fitness_median = (m % 2) ? medians[m / 2] : 0.5 * (medians[m / 2 - 1] + medians[m / 2]);
        }
        r.success_rate = sum_sr / ni;
        r.mu_f = sum_mf / ni;
        r.mu_cr = sum_mcr / ni;
        r.mean_num_regressors = sum_nreg / ni;
        r.unique_structures = static_cast<int>(hash_counts.size());
        double entropy = 0.0;
        for (const auto& kv : hash_counts) {
            const double p = static_cast<double>(kv.second) / total;
            entropy -= p * std::log2(p);
        }
        r.structure_entropy = entropy;
    }
    return r;
}

#ifndef __EMSCRIPTEN__
void DifferentialEvolutionOptimizer::run_async(
    ProgressCallback on_progress, ShouldStopFn should_stop
) {
    stop_flag_.store(false);
    worker_thread_ = std::thread([this, on_progress, should_stop] {
        while (!stop_flag_.load()) {
            if (should_stop && should_stop()) {
                std::lock_guard<std::mutex> lk(islands_mutex_);
                if (stop_reason_.empty()) stop_reason_ = "stopped";
                break;
            }
            GenerationReport rpt;
            bool finished;
            {
                std::lock_guard<std::mutex> lk(islands_mutex_);
                if (done_) break;
                rpt = step_generation_locked();
                finished = done_;
            }
            if (on_progress) on_progress(rpt);
            if (finished) break;
        }
    });
}
#endif // !__EMSCRIPTEN__

int DifferentialEvolutionOptimizer::run_steps(
    int n, ProgressCallback on_progress, ShouldStopFn should_stop
) {
    int ran = 0;
    for (int i = 0; i < n; ++i) {
        if (should_stop && should_stop()) break;
        GenerationReport rpt;
        bool finished;
        {
            std::lock_guard<std::mutex> lk(islands_mutex_);
            if (done_) break;
            rpt = step_generation_locked();
            finished = done_;
        }
        if (on_progress) on_progress(rpt);
        ++ran;
        if (finished) break;
    }
    return ran;
}

bool DifferentialEvolutionOptimizer::is_done() const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    return done_;
}

std::string DifferentialEvolutionOptimizer::stop_reason() const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    return stop_reason_;
}

DEConfig DifferentialEvolutionOptimizer::config() const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    return cfg_;
}

long long DifferentialEvolutionOptimizer::evaluations() const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    long long e = canonical_eval_.evaluations();
    for (const auto& isl : islands_) e += isl->evaluations();
    return e;
}

std::vector<IslandReport> DifferentialEvolutionOptimizer::island_reports() const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    std::vector<IslandReport> out;
    for (size_t i = 0; i < islands_.size(); ++i) {
        IslandReport r = islands_[i]->report();
        r.role = i < island_roles_.size() ? island_roles_[i] : "balanced";
        out.push_back(std::move(r));
    }
    return out;
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
    return champion_valid_ ? champion_ : Chromosome();
}

double DifferentialEvolutionOptimizer::tuning_value(const std::string& p) const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    if (p == "mutationFactor")        return cfg_.mu_f;
    if (p == "crossoverRate")         return cfg_.mu_cr;
    if (p == "migrationRate")         return cfg_.migration_rate;
    if (p == "migrationInterval")     return cfg_.migration_interval;
    if (p == "stagnationLimit")       return cfg_.stagnation_limit;
    if (p == "reinitializationRatio") return cfg_.reinit_ratio;
    if (p == "structuralMutationRate")return cfg_.structural_mutation_rate;
    return std::numeric_limits<double>::quiet_NaN();
}

bool DifferentialEvolutionOptimizer::apply_tuning(
    const std::string& param, double value
) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    if (param == "mutationFactor") {
        cfg_.mu_f = value;
        for (auto& isl : islands_) {
            DEConfig nc = isl->config(); nc.mu_f = value;
            isl->update_config(nc);
            isl->set_mu_f(value);   // μCR is left untouched
        }
    } else if (param == "crossoverRate") {
        cfg_.mu_cr = value;
        for (auto& isl : islands_) {
            DEConfig nc = isl->config(); nc.mu_cr = value;
            isl->update_config(nc);
            isl->set_mu_cr(value);  // μF is left untouched
        }
    } else if (param == "migrationRate") {
        cfg_.migration_rate = value;
    } else if (param == "migrationInterval") {
        cfg_.migration_interval = static_cast<int>(std::lround(value));
    } else if (param == "stagnationLimit") {
        cfg_.stagnation_limit = static_cast<int>(std::lround(value));
    } else if (param == "reinitializationRatio" || param == "structuralMutationRate") {
        if (param == "reinitializationRatio") cfg_.reinit_ratio = value;
        else cfg_.structural_mutation_rate = value;
        for (auto& isl : islands_) {
            DEConfig nc = isl->config();
            nc.reinit_ratio = cfg_.reinit_ratio;
            nc.structural_mutation_rate = cfg_.structural_mutation_rate;
            isl->update_config(nc);
        }
    } else {
        return false; // fitness weights are owned by the pipeline
    }
    return true;
}

void DifferentialEvolutionOptimizer::update_weights(const FitnessWeights& w) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    for (auto& isl : islands_) isl->update_weights(w);
}

FitnessWeights DifferentialEvolutionOptimizer::current_weights() const {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    return canonical_eval_.weights();
}

void DifferentialEvolutionOptimizer::update_weights_for_island(int idx, const FitnessWeights& w) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    if (idx >= 0 && idx < static_cast<int>(islands_.size())) islands_[idx]->update_weights(w);
}

void DifferentialEvolutionOptimizer::set_canonical_weights(const FitnessWeights& w) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    canonical_eval_.weights() = w;
    canonical_cache_.clear();
    if (champion_valid_) {
        Chromosome c = champion_;
        canonical_eval_.evaluate(c, train_data_, train_rows_, val_data_, val_rows_, cols_, output_col_);
        champion_valid_ = c.evaluated && std::isfinite(c.fitness);
        champion_ = std::move(c);
    }
    update_champion_locked();
    champion_diag_hash_ = 0;
    global_stagnation_ = 0;
    prev_best_ = champion_valid_ ? champion_.fitness : std::numeric_limits<double>::infinity();
}

void DifferentialEvolutionOptimizer::trigger_restart(double ratio) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    for (auto& isl : islands_) isl->restart(ratio);
}

void DifferentialEvolutionOptimizer::inject_migrant(const Chromosome& c) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    if (islands_.empty()) return;
    Chromosome copy = c;
    copy.power_mode = cfg_.power_mode;
    islands_[0]->reevaluate(copy);
    if (copy.evaluated && std::isfinite(copy.fitness))
        islands_[0]->accept_migrants({copy});
}

void DifferentialEvolutionOptimizer::set_island_validation_window(
    int idx, const double* val_data, int val_rows
) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    if (idx >= 0 && idx < static_cast<int>(islands_.size()))
        islands_[idx]->set_validation_window(val_data, val_rows);
}

void DifferentialEvolutionOptimizer::set_island_role(int idx, const std::string& name) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    if (static_cast<int>(island_roles_.size()) != static_cast<int>(islands_.size()))
        island_roles_.resize(islands_.size(), "balanced");
    if (idx >= 0 && idx < static_cast<int>(island_roles_.size()))
        island_roles_[idx] = name;
}

void DifferentialEvolutionOptimizer::update_search_space(double pmax, int max_delay) {
    std::lock_guard<std::mutex> lk(islands_mutex_);
    cfg_.pmax      = pmax;
    cfg_.max_delay = max_delay;
    for (auto& isl : islands_) {
        DEConfig nc = isl->config();
        nc.pmax      = pmax;
        nc.max_delay = max_delay;
        isl->update_config(nc);
    }
}

} // namespace aegis
