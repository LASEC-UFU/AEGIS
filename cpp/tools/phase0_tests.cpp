// phase0_tests.cpp — tests required by experiments/phase0/PHASE0_PREREG.md §4,
// run before any real-data execution of the Phase-0 tool.
#include "aegis/aegis_api.h"
#include "aegis/json_lite.hpp"
#include "aegis/model_io.hpp"
#include "aegis/rational_model.hpp"
#include "phase0_core.hpp"

#include <cstdio>
#include <iostream>
#include <random>

using namespace aegis;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond, msg) do { if (cond) ++g_pass; else { ++g_fail; std::cerr << "FAIL: " << msg << "\n"; } } while (0)

static Regressor reg(std::initializer_list<Term> t) { Regressor r; r.terms = t; return r; }
static Term T(int var, int delay, double p) { Term t; t.variable = var; t.delay = delay; t.exponent = p; return t; }

/** Random input u in [-1, 1] and a mildly nonlinear stable output, cols = {u, y}. */
static std::vector<double> make_data(int rows, unsigned seed) {
    std::mt19937_64 rng(seed);
    std::uniform_real_distribution<double> U(-1.0, 1.0);
    std::vector<double> d(static_cast<size_t>(rows) * 2, 0.0);
    for (int k = 0; k < rows; ++k) d[static_cast<size_t>(k) * 2] = U(rng);
    for (int k = 2; k < rows; ++k) {
        const double y1 = d[static_cast<size_t>(k - 1) * 2 + 1], u1 = d[static_cast<size_t>(k - 1) * 2];
        d[static_cast<size_t>(k) * 2 + 1] = 0.6 * y1 - 0.1 * y1 * y1 + 0.3 * u1 + 0.05 * U(rng);
    }
    return d;
}

static void test_simulator_matches_core() {
    const int rows = 600;
    auto data = make_data(rows, 7);
    Chromosome c;
    c.power_mode = PowerMode::Hybrid;
    c.regressors = {reg({T(1, 1, 1.0)}), reg({T(0, 1, 2.0)}), reg({T(1, 2, 0.5)}),
                    reg({T(0, 2, 1.0), T(1, 1, 1.0)}), reg({T(0, 3, 3.0)})};
    c.coefficients = {0.55, 0.2, 0.05, -0.1, 0.03};
    c.intercept = 0.01;
    phase0::Problem pb{data.data(), rows, 2, 1, rows, 40, 1e6};
    const auto mine = phase0::simulate(c, phase0::pack(c), pb);
    RationalModel rm(c);
    const auto ref = rm.simulate(data.data(), rows, 2, 1, -1, 1e6);
    const int md = c.max_delay();
    double maxdiff = 0.0;
    for (int k = md; k < rows; ++k) maxdiff = std::max(maxdiff, std::abs(mine.yhat[k] - ref.yhat[k - md]));
    CHECK(!mine.diverged && !ref.diverged, "simulator: no divergence");
    CHECK(maxdiff <= 1e-12, "simulator equals RationalModel::simulate (maxdiff " << maxdiff << ")");
}

static void test_sensitivities_vs_finite_differences() {
    const int rows = 400;
    auto data = make_data(rows, 11);
    Chromosome c;
    c.power_mode = PowerMode::Hybrid;
    c.regressors = {reg({T(1, 1, 1.0)}), reg({T(1, 1, 2.0)}), reg({T(0, 1, 1.0)}),
                    reg({T(1, 2, 1.0), T(0, 1, 1.0)}), reg({T(1, 3, 3.0)})};
    c.coefficients = {0.5, -0.08, 0.3, 0.05, 0.02};
    c.intercept = 0.02;
    phase0::Problem pb{data.data(), rows, 2, 1, rows, 40, 1e6};
    auto theta = phase0::pack(c);
    const auto sim = phase0::simulate(c, theta, pb);
    std::vector<double> S;
    CHECK(phase0::sensitivities(c, theta, pb, sim.yhat, S), "sensitivities: differentiable");
    const int q = static_cast<int>(theta.size());
    double best = 1e300;
    for (double h : {1e-4, 1e-5, 1e-6}) {
        double num = 0.0, den = 0.0;
        for (int j = 0; j < q; ++j) {
            auto tp = theta, tm = theta;
            tp[j] += h; tm[j] -= h;
            const auto sp = phase0::simulate(c, tp, pb), sm = phase0::simulate(c, tm, pb);
            for (int k = 40; k < rows; ++k) {
                const double fd = (sp.yhat[k] - sm.yhat[k]) / (2 * h);
                num = std::max(num, std::abs(fd - S[static_cast<size_t>(k) * q + j]));
                den = std::max(den, std::abs(S[static_cast<size_t>(k) * q + j]));
            }
        }
        best = std::min(best, num / den);
    }
    CHECK(best < 1e-6, "sensitivities agree with central differences (rel " << best << ")");
}

static void normalize_minmax(std::vector<double>& d, int rows, int cols, int train_end) {
    for (int c = 0; c < cols; ++c) {
        double lo = 1e300, hi = -1e300;
        for (int r = 0; r < train_end; ++r) { lo = std::min(lo, d[static_cast<size_t>(r) * cols + c]); hi = std::max(hi, d[static_cast<size_t>(r) * cols + c]); }
        for (int r = 0; r < rows; ++r) d[static_cast<size_t>(r) * cols + c] = -1.0 + 2.0 * (d[static_cast<size_t>(r) * cols + c] - lo) / (hi - lo);
    }
}

static void test_synthetic_qr_and_lm() {
    // Pre-registered synthetic system, noise-free, development seed 41.
    const int rows = 4000, train_end = 3000;
    std::mt19937_64 rng(41);
    std::uniform_real_distribution<double> U(-1.0, 1.0);
    std::vector<double> raw(static_cast<size_t>(rows) * 2, 0.0);
    for (int k = 0; k < rows; ++k) raw[static_cast<size_t>(k) * 2] = U(rng);
    for (int k = 2; k < rows; ++k)
        raw[static_cast<size_t>(k) * 2 + 1] = 0.5 * raw[static_cast<size_t>(k - 1) * 2 + 1] +
            0.2 * raw[static_cast<size_t>(k - 1) * 2] + 0.1 * std::pow(raw[static_cast<size_t>(k - 2) * 2], 2);
    // In normalized coordinates u^2 also produces a linear u term, so it is included.
    const std::string model = phase0::model_json({{1, 1, 1}, {0, 1, 1}, {0, 2, 1}, {0, 2, 2}});
    void* p = aegis_create_pipeline();
    const std::string cfg = "{\"trainEndRow\":" + std::to_string(train_end) + ",\"valEndRow\":" + std::to_string(rows) +
        ",\"testStartRow\":" + std::to_string(rows) + ",\"outputCol\":1,\"maxDelay\":40,\"webSocketPort\":0,"
        "\"syncMode\":true,\"powerMode\":\"hybrid\",\"numThreads\":1}";
    CHECK(aegis_load_data(p, raw.data(), rows, 2) == 0 && aegis_configure(p, cfg.c_str()) == 0, "synthetic: pipeline");
    char* out = aegis_evaluate_model(p, model.c_str(), 1);
    json::Value v;
    json::parse(out, v);
    aegis_free_string(out);
    const json::Value* tr = v.get("metrics") ? v.get("metrics")->get("train") : nullptr;
    const double rmse = tr ? tr->number_or("rmseFreeRun", 1.0) : 1.0;
    CHECK(rmse < 1e-9, "synthetic: QR recovers the system (train free-run " << rmse << ")");

    Chromosome c;
    CHECK(chromosome_from_json(v, c, PowerMode::Hybrid), "synthetic: parse fitted model");
    std::vector<double> norm = raw;
    normalize_minmax(norm, rows, 2, train_end);
    phase0::Problem pb{norm.data(), rows, 2, 1, train_end, 40, 10.0};
    const auto sim = phase0::simulate(c, phase0::pack(c), pb);
    CHECK(std::abs(std::sqrt(sim.sse / sim.n) - rmse) <= 1e-9 + 1e-9 * rmse, "synthetic: simulator consistent with evaluator");
    auto theta = phase0::pack(c);
    for (size_t j = 0; j < theta.size(); ++j) theta[j] *= (j % 2 ? 1.2 : 0.8);
    const auto lm = phase0::levenberg_marquardt(c, theta, pb);
    CHECK(lm.loss < 1e-12, "synthetic: LM from 20% perturbation returns to zero loss (" << lm.loss << ", " << lm.status << ")");
    aegis_destroy_pipeline(p);
}

static void test_legendre_monomial_equivalence() {
    const int rows = 800;
    std::mt19937_64 rng(5);
    std::uniform_real_distribution<double> U(-1.0, 1.0);
    std::vector<double> x(rows), y(rows);
    for (int k = 0; k < rows; ++k) x[k] = U(rng);
    for (int k = 2; k < rows; ++k) y[k] = std::sin(2.0 * x[k - 1]) + 0.3 * x[k - 2] * x[k - 2] * x[k - 2] + 0.05 * U(rng);
    auto fit = [&](bool legendre) {
        const int q = 7; // 1 + 2 lags x 3 powers
        std::vector<double> A(q * q, 0.0), b(q, 0.0), th;
        std::vector<std::vector<double>> X;
        for (int k = 2; k < rows; ++k) {
            std::vector<double> r{1.0};
            for (int d = 1; d <= 2; ++d) {
                const double z = x[k - d];
                if (legendre) { r.push_back(z); r.push_back(0.5 * (3 * z * z - 1)); r.push_back(0.5 * (5 * z * z * z - 3 * z)); }
                else { r.push_back(z); r.push_back(z * z); r.push_back(z * z * z); }
            }
            for (int i = 0; i < q; ++i) { b[i] += r[i] * y[k]; for (int j = 0; j < q; ++j) A[i * q + j] += r[i] * r[j]; }
            X.push_back(r);
        }
        phase0::cholesky_solve(A, b, q, th);
        std::vector<double> pred;
        for (const auto& r : X) { double s = 0.0; for (int i = 0; i < q; ++i) s += r[i] * th[i]; pred.push_back(s); }
        return pred;
    };
    const auto pm = fit(false), pl = fit(true);
    double maxdiff = 0.0;
    for (size_t i = 0; i < pm.size(); ++i) maxdiff = std::max(maxdiff, std::abs(pm[i] - pl[i]));
    CHECK(maxdiff <= 1e-9, "Legendre and monomial bases give the same predictions (maxdiff " << maxdiff << ")");
}

static void test_nondifferentiable_policy() {
    const int rows = 200;
    std::vector<double> d(static_cast<size_t>(rows) * 2, 0.0); // y identically zero
    for (int k = 0; k < rows; ++k) d[static_cast<size_t>(k) * 2] = 0.1 * std::sin(0.1 * k);
    Chromosome c;
    c.power_mode = PowerMode::Hybrid;
    c.regressors = {reg({T(1, 1, 0.5)}), reg({T(0, 1, 1.0)})};
    c.coefficients = {0.1, 0.0};
    c.intercept = 0.0; // y stays exactly 0 -> |y|^0.5 not differentiable
    phase0::Problem pb{d.data(), rows, 2, 1, rows, 40, 10.0};
    const auto lm = phase0::levenberg_marquardt(c, phase0::pack(c), pb);
    CHECK(lm.status == "nondifferentiable_init", "p<1 at zero is flagged, not optimized (" << lm.status << ")");
}

int main() {
    test_simulator_matches_core();
    test_sensitivities_vs_finite_differences();
    test_synthetic_qr_and_lm();
    test_legendre_monomial_equivalence();
    test_nondifferentiable_policy();
    std::cout << "phase0_tests: " << g_pass << " passed, " << g_fail << " failed\n";
    return g_fail == 0 ? 0 : 1;
}
