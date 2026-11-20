// frols_baseline.cpp — Forward-Regression Orthogonal Least Squares (FROLS,
// Billings 2013; Chen, Billings & Luo 1989) for polynomial NARX models.
//
// The candidate dictionary contains every monomial of degree 1..L in the
// lagged signals y(k-1..ny) and u_i(k-1..nu) (plus the intercept, always
// included). Terms are selected greedily by the Error Reduction Ratio on the
// (centred) training split. The number of terms is then chosen either by the
// validation free-run RMSE ("val-sim") or by BIC on the training split
// ("bic"). Every candidate model is evaluated through aegis_evaluate_model(),
// i.e. with exactly the same normalization, splits and metric code as AEGIS.
//
// Usage:
//   aegis_frols --data <est.csv> [--data-test <test.csv>] [--config <json|file>]
//               --ny 4 --nu 4 --degree 3 --max-terms 20 --output <file.json>

#include "aegis/aegis_api.h"
#include "aegis/json_lite.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

using aegis::json::Value;

static std::string take(char* p) {
    if (!p) return std::string();
    std::string s(p);
    aegis_free_string(p);
    return s;
}

static bool read_csv(const std::string& path, std::vector<double>& data, int& rows, int& cols) {
    std::ifstream f(path);
    if (!f.is_open()) return false;
    std::string line;
    char sep = 0;
    data.clear(); rows = 0; cols = 0;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        if (!sep) sep = line.find('\t') != std::string::npos ? '\t' :
                        line.find(';') != std::string::npos ? ';' :
                        line.find(',') != std::string::npos ? ',' : ' ';
        std::vector<double> row;
        std::istringstream ss(line);
        std::string tok;
        bool ok = true;
        while (std::getline(ss, tok, sep)) {
            tok.erase(0, tok.find_first_not_of(" \t"));
            tok.erase(tok.find_last_not_of(" \t") + 1);
            if (tok.empty()) continue;
            char* end = nullptr;
            double v = std::strtod(tok.c_str(), &end);
            if (!end || *end) { ok = false; break; }
            row.push_back(v);
        }
        if (!ok || row.empty()) continue;
        if (cols == 0) cols = static_cast<int>(row.size());
        if (static_cast<int>(row.size()) != cols) return false;
        data.insert(data.end(), row.begin(), row.end());
        ++rows;
    }
    return rows > 0;
}

struct Factor { int var; int delay; };
using Monomial = std::vector<Factor>; // repeated factors = powers

static void enumerate(const std::vector<Factor>& base, int degree, size_t start,
                      Monomial& cur, std::vector<Monomial>& out) {
    if (!cur.empty()) out.push_back(cur);
    if (static_cast<int>(cur.size()) == degree) return;
    for (size_t i = start; i < base.size(); ++i) {
        cur.push_back(base[i]);
        enumerate(base, degree, i, cur, out);
        cur.pop_back();
    }
}

static std::string monomial_json(const Monomial& m) {
    // Merge repeated factors into integer exponents.
    std::vector<std::pair<Factor, int>> f;
    for (const auto& x : m) {
        bool merged = false;
        for (auto& g : f) if (g.first.var == x.var && g.first.delay == x.delay) { ++g.second; merged = true; }
        if (!merged) f.push_back({x, 1});
    }
    std::ostringstream j;
    j << "{\"terms\":[";
    for (size_t i = 0; i < f.size(); ++i) {
        if (i) j << ",";
        j << "{\"variable\":" << f[i].first.var << ",\"delay\":" << f[i].first.delay
          << ",\"exponent\":" << f[i].second << ",\"isDenominator\":false}";
    }
    j << "]}";
    return j.str();
}

static std::string monomial_label(const Monomial& m, int out_col) {
    std::string s;
    for (const auto& x : m) {
        if (!s.empty()) s += "*";
        s += (x.var == out_col ? "y" : "u" + std::to_string(x.var)) + "(k-" + std::to_string(x.delay) + ")";
    }
    return s;
}

int main(int argc, char** argv) {
    std::string data_path, test_path, cfg_arg, out_path = "frols_result.json";
    int ny = 4, nu = 4, degree = 3, max_terms = 20;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() { return i + 1 < argc ? std::string(argv[++i]) : std::string(); };
        if (a == "--data") data_path = next();
        else if (a == "--data-test") test_path = next();
        else if (a == "--config") cfg_arg = next();
        else if (a == "--ny") ny = std::stoi(next());
        else if (a == "--nu") nu = std::stoi(next());
        else if (a == "--degree") degree = std::stoi(next());
        else if (a == "--max-terms") max_terms = std::stoi(next());
        else if (a == "--output") out_path = next();
        else { std::cerr << "unknown option " << a << "\n"; return 2; }
    }
    if (data_path.empty()) { std::cerr << "--data required\n"; return 2; }

    std::vector<double> data;
    int rows = 0, cols = 0;
    if (!read_csv(data_path, data, rows, cols)) { std::cerr << "cannot read " << data_path << "\n"; return 1; }
    const int est_rows = rows;
    if (!test_path.empty()) {
        std::vector<double> td; int tr = 0, tc = 0;
        if (!read_csv(test_path, td, tr, tc) || tc != cols) { std::cerr << "cannot read test file\n"; return 1; }
        data.insert(data.end(), td.begin(), td.end());
        rows += tr;
    }
    if (!cfg_arg.empty() && cfg_arg.front() != '{') {
        std::ifstream cf(cfg_arg);
        cfg_arg.assign(std::istreambuf_iterator<char>(cf), {});
    }
    Value cfg = Value::make_object();
    if (!cfg_arg.empty() && !aegis::json::parse(cfg_arg, cfg)) { std::cerr << "invalid config\n"; return 1; }
    if (!test_path.empty()) {
        if (!cfg.has("trainEndRow"))
            cfg.set("trainEndRow", Value::make_number(std::floor(est_rows * cfg.number_or("trainRatio", 0.8))));
        if (!cfg.has("valEndRow")) cfg.set("valEndRow", Value::make_number(est_rows));
        cfg.set("testStartRow", Value::make_number(est_rows));
    }
    cfg.set("webSocketPort", Value::make_number(0));
    cfg.set("syncMode", Value::make_bool(true));
    cfg.set("powerMode", Value::make_string("hybrid"));
    const int max_lag = std::max(ny, nu);
    if (!cfg.has("maxDelay") || cfg.int_or("maxDelay", 0) < max_lag)
        cfg.set("maxDelay", Value::make_number(max_lag));

    void* p = aegis_create_pipeline();
    if (aegis_load_data(p, data.data(), rows, cols) != 0 ||
        aegis_configure(p, cfg.dump().c_str()) != 0) {
        std::cerr << "pipeline configuration failed: " << take(aegis_get_last_error(p)) << "\n";
        return 1;
    }
    Value eff;
    aegis::json::parse(take(aegis_get_config(p)), eff);
    const int out_col = eff.int_or("outputCol", cols - 1);

    // Split boundaries — identical formulas to IdentificationPipeline::prepare_data.
    int train_end;
    if (eff.int_or("trainEndRow", -1) >= 0) train_end = eff.int_or("trainEndRow", 0);
    else train_end = static_cast<int>(rows * eff.number_or("trainRatio", 0.7));

    // Min-max normalization to [-1, 1] fitted on the training split only.
    std::vector<double> lo(cols, 1e300), hi(cols, -1e300);
    for (int r = 0; r < train_end; ++r)
        for (int c = 0; c < cols; ++c) {
            lo[c] = std::min(lo[c], data[static_cast<size_t>(r) * cols + c]);
            hi[c] = std::max(hi[c], data[static_cast<size_t>(r) * cols + c]);
        }
    auto norm = [&](int r, int c) {
        const double rng = hi[c] - lo[c];
        if (rng < 1e-30) return 0.0;
        return -1.0 + 2.0 * (data[static_cast<size_t>(r) * cols + c] - lo[c]) / rng;
    };

    // Candidate dictionary.
    std::vector<Factor> base;
    for (int d = 1; d <= ny; ++d) base.push_back({out_col, d});
    for (int c = 0; c < cols; ++c)
        if (c != out_col) for (int d = 1; d <= nu; ++d) base.push_back({c, d});
    std::vector<Monomial> cands;
    Monomial cur;
    enumerate(base, degree, 0, cur, cands);
    const int M = static_cast<int>(cands.size());
    const int N = train_end - max_lag;
    std::cout << "FROLS: " << M << " candidates, " << N << " training samples, degree " << degree
              << ", ny=" << ny << ", nu=" << nu << "\n";
    const auto t0 = std::chrono::steady_clock::now();

    // Centred candidate matrix (column-major) and centred target.
    std::vector<double> W(static_cast<size_t>(M) * N), y(N);
    double ym = 0.0;
    for (int i = 0; i < N; ++i) { y[i] = norm(i + max_lag, out_col); ym += y[i]; }
    ym /= N;
    double sigma = 0.0;
    for (int i = 0; i < N; ++i) { y[i] -= ym; sigma += y[i] * y[i]; }
    std::vector<double> norm0(M);
    for (int j = 0; j < M; ++j) {
        double* w = &W[static_cast<size_t>(j) * N];
        double mean = 0.0;
        for (int i = 0; i < N; ++i) {
            const int k = i + max_lag;
            double v = 1.0;
            for (const auto& f : cands[j]) v *= norm(k - f.delay, f.var);
            w[i] = v;
            mean += v;
        }
        mean /= N;
        double s = 0.0;
        for (int i = 0; i < N; ++i) { w[i] -= mean; s += w[i] * w[i]; }
        norm0[j] = s;
    }
    std::vector<char> active(M, 1);
    std::vector<int> selected;
    std::vector<double> errs;
    for (int step = 0; step < max_terms; ++step) {
        int best = -1; double best_err = -1.0;
        for (int j = 0; j < M; ++j) {
            if (!active[j]) continue;
            const double* w = &W[static_cast<size_t>(j) * N];
            double ww = 0.0, wy = 0.0;
            for (int i = 0; i < N; ++i) { ww += w[i] * w[i]; wy += w[i] * y[i]; }
            if (ww <= 1e-10 * std::max(norm0[j], 1e-300)) { active[j] = 0; continue; }
            const double e = wy * wy / (ww * sigma);
            if (e > best_err) { best_err = e; best = j; }
        }
        if (best < 0) break;
        selected.push_back(best);
        errs.push_back(best_err);
        active[best] = 0;
        const double* q = &W[static_cast<size_t>(best) * N];
        double qq = 0.0;
        for (int i = 0; i < N; ++i) qq += q[i] * q[i];
        for (int j = 0; j < M; ++j) {
            if (!active[j]) continue;
            double* w = &W[static_cast<size_t>(j) * N];
            double dot = 0.0;
            for (int i = 0; i < N; ++i) dot += q[i] * w[i];
            const double a = dot / qq;
            for (int i = 0; i < N; ++i) w[i] -= a * q[i];
        }
    }
    const double select_s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

    // Evaluate every prefix through the AEGIS metric code.
    struct Eval { int k; double val_fr, val_os, bic; std::string json; };
    std::vector<Eval> evals;
    for (size_t k = 1; k <= selected.size(); ++k) {
        std::ostringstream m;
        m << "{\"powerMode\":\"hybrid\",\"regressors\":[";
        for (size_t t = 0; t < k; ++t) { if (t) m << ","; m << monomial_json(cands[selected[t]]); }
        m << "]}";
        const std::string res = take(aegis_evaluate_model(p, m.str().c_str(), 1));
        Value rv;
        if (!aegis::json::parse(res, rv) || rv.has("error")) continue;
        Eval e{static_cast<int>(k), NAN, NAN, NAN, res};
        if (const Value* mt = rv.get("metrics")) {
            if (const Value* v = mt->get("validation")) {
                e.val_fr = v->number_or("rmseFreeRun", NAN);
                e.val_os = v->number_or("rmseOneStep", NAN);
            }
            if (const Value* tr = mt->get("train")) {
                const double rmse = tr->number_or("rmseOneStep", NAN);
                const int n = tr->int_or("n", 1);
                e.bic = n * std::log(rmse * rmse) + (k + 1) * std::log(static_cast<double>(n));
            }
        }
        evals.push_back(std::move(e));
    }
    auto pick = [&](auto key) {
        const Eval* best = nullptr;
        for (const auto& e : evals) {
            const double v = key(e);
            if (!std::isfinite(v)) continue;
            if (!best || v < key(*best)) best = &e;
        }
        return best;
    };
    const Eval* by_val = pick([](const Eval& e) { return e.val_fr; });
    const Eval* by_bic = pick([](const Eval& e) { return e.bic; });
    const double total_s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

    std::ofstream of(out_path);
    of << "{\"schema\":\"aegis.frols/1\",\"method\":\"FROLS\",\"build\":" << aegis_build_info()
       << ",\"dataFile\":" << aegis::json::str(data_path) << ",\"testFile\":" << aegis::json::str(test_path)
       << ",\"ny\":" << ny << ",\"nu\":" << nu << ",\"degree\":" << degree << ",\"maxTerms\":" << max_terms
       << ",\"numCandidates\":" << M << ",\"selectionSeconds\":" << aegis::json::num(select_s)
       << ",\"totalSeconds\":" << aegis::json::num(total_s)
       << ",\"config\":" << take(aegis_get_config(p))
       << ",\"selectedOrder\":[";
    for (size_t t = 0; t < selected.size(); ++t) {
        if (t) of << ",";
        of << "{\"label\":" << aegis::json::str(monomial_label(cands[selected[t]], out_col))
           << ",\"err\":" << aegis::json::num(errs[t]) << "}";
    }
    of << "],\"prefixes\":[";
    for (size_t i = 0; i < evals.size(); ++i) {
        if (i) of << ",";
        of << "{\"k\":" << evals[i].k << ",\"valRmseFreeRun\":" << aegis::json::num(evals[i].val_fr)
           << ",\"valRmseOneStep\":" << aegis::json::num(evals[i].val_os)
           << ",\"trainBic\":" << aegis::json::num(evals[i].bic) << "}";
    }
    of << "],\"selectedByValidationSimulation\":" << (by_val ? by_val->json : "null")
       << ",\"selectedByBic\":" << (by_bic ? by_bic->json : "null") << "}\n";
    aegis_destroy_pipeline(p);
    std::cout << "FROLS done in " << total_s << " s; k(val-sim)=" << (by_val ? by_val->k : 0)
              << ", k(bic)=" << (by_bic ? by_bic->k : 0) << " -> " << out_path << "\n";
    return 0;
}
