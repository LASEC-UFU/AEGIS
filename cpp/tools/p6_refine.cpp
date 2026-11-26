// p6_refine.cpp — P6 (experiments/p6/P6_PREREG.md): simulation-error
// refinement of E3 champions with admissibility veto and choice on V_A.
//
//   aegis_p6 --selftest
//   aegis_p6 --bench <name> --data <est.csv> --config <aegis_full.json>
//            --train-end N --val-end M --cell <name> --runs <dir with run_*.json>
//            --output <file.jsonl>
//
// Reads only report.model of each run file. No test file is ever opened.
#include "aegis/aegis_api.h"
#include "aegis/json_lite.hpp"
#include "aegis/model_io.hpp"
#include "p6_core.hpp"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <regex>
#include <sstream>

using aegis::json::Value;
namespace fs = std::filesystem;

static std::string take(char* p) {
    if (!p) return std::string();
    std::string s(p);
    aegis_free_string(p);
    return s;
}
static std::string read_file(const std::string& path) {
    std::ifstream f(path);
    return std::string(std::istreambuf_iterator<char>(f), {});
}
static bool read_csv(const std::string& path, std::vector<double>& data, int& rows, int& cols) {
    std::ifstream f(path);
    if (!f.is_open()) return false;
    std::string line;
    data.clear(); rows = 0; cols = 0;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        std::vector<double> row;
        std::istringstream ss(line);
        std::string tok;
        bool ok = true;
        while (std::getline(ss, tok, ',')) {
            char* end = nullptr;
            const double v = std::strtod(tok.c_str(), &end);
            if (tok.empty() || !end || *end) { ok = false; break; }
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
static std::string num(double v) { return aegis::json::num(v); }

// ── self test: sensitivities vs central differences on a rational model ──────
static int selftest() {
    std::mt19937_64 rng(41);
    std::uniform_real_distribution<double> U(-1.0, 1.0);
    const int rows = 400, cols = 2, out = 1;
    std::vector<double> data(static_cast<size_t>(rows) * cols);
    for (int k = 0; k < rows; ++k) data[static_cast<size_t>(k) * cols] = U(rng);
    // y(k) = (0.3 y(k-1) + 0.4 u(k-1) + 0.1 u(k-2)^1.5) / (1 + 0.2 y(k-1)^2 + 0.1 |u(k-1)|^0.5 y(k-2))
    for (int k = 0; k < rows; ++k) {
        double y = 0.0;
        if (k >= 2) {
            const double y1 = data[(k - 1) * 2 + 1], y2 = data[(k - 2) * 2 + 1];
            const double u1 = data[(k - 1) * 2], u2 = data[(k - 2) * 2];
            const double n = 0.3 * y1 + 0.4 * u1 + 0.1 * aegis::power_basis(u2, 1.5, aegis::PowerMode::Hybrid);
            const double d = 1.0 + 0.2 * y1 * y1 + 0.1 * aegis::power_basis(u1, 0.5, aegis::PowerMode::Hybrid) * y2;
            y = n / d;
        }
        data[static_cast<size_t>(k) * cols + 1] = y;
    }
    aegis::Chromosome c;
    c.power_mode = aegis::PowerMode::Hybrid;
    auto reg = [](std::vector<aegis::Term> t) { aegis::Regressor r; r.terms = std::move(t); return r; };
    c.regressors = {
        reg({{1, 1, 1.0, false}}), reg({{0, 1, 1.0, false}}), reg({{0, 2, 1.5, false}}),
        reg({{1, 1, 2.0, true}}), reg({{0, 1, 0.5, true}, {1, 2, 1.0, true}}),
        reg({{1, 2, 1.5, false}, {0, 1, 2.0, false}})};
    std::vector<double> th = {0.01, 0.28, 0.42, 0.09, 0.18, 0.12, 0.05};
    p6::Seg s{data.data(), rows, cols, out, 10.0};
    const p6::Sim sim = p6::simulate(c, th, s);
    std::vector<double> S;
    if (sim.diverged || !p6::sensitivities(c, th, s, sim, S)) { std::cout << "selftest: simulate/sensitivities failed\n"; return 1; }
    const int q = static_cast<int>(th.size());
    double worst = 0.0;
    for (double h : {1e-4, 1e-5, 1e-6}) {
        double maxrel = 0.0;
        for (int i = 0; i < q; ++i) {
            auto tp = th, tm = th;
            tp[i] += h; tm[i] -= h;
            const p6::Sim a = p6::simulate(c, tp, s), b = p6::simulate(c, tm, s);
            for (int k : {50, 150, 399}) {
                const double fd = (a.yhat[k] - b.yhat[k]) / (2 * h);
                const double an = S[static_cast<size_t>(k) * q + i];
                maxrel = std::max(maxrel, std::abs(fd - an) / std::max(1e-8, std::abs(fd) + std::abs(an)));
            }
        }
        std::cout << "selftest: h=" << h << " max rel diff " << maxrel << "\n";
        worst = (h == 1e-4) ? maxrel : std::min(worst, maxrel);
    }
    // LM from perturbed coefficients must reduce the training loss.
    std::vector<double> t0 = {0.0, 0.3, 0.4, 0.1, 0.2, 0.1, 0.0}; // true model, then perturbed
    for (size_t i = 0; i < t0.size(); ++i) t0[i] = t0[i] * 1.2 + 0.01;
    const auto lm = p6::levenberg_marquardt(c, t0, s, 10);
    std::cout << "selftest: LM " << lm.status << " loss " << lm.loss0 << " -> " << lm.loss << "\n";
    const bool ok = worst < 1e-6 && lm.loss < 1e-12;
    std::cout << (ok ? "selftest: PASS\n" : "selftest: FAIL\n");
    return ok ? 0 : 1;
}

// ── data variant (pipeline + normalized copy), as in phase0_fixed.cpp ────────
struct Variant {
    std::vector<double> raw, norm;
    int rows = 0, cols = 0, out = 1, train_end = 0, val_end = 0;
    double bound = 10.0, out_scale = 1.0; // original units = normalized × out_scale
    void* pipe = nullptr;
    bool init(const std::string& base_cfg, std::string& err) {
        Value cfg;
        if (!aegis::json::parse(base_cfg, cfg) || !cfg.is_object()) { err = "invalid base config"; return false; }
        cfg.set("trainEndRow", Value::make_number(train_end));
        cfg.set("valEndRow", Value::make_number(val_end));
        cfg.set("testStartRow", Value::make_number(rows));
        cfg.set("outputCol", Value::make_number(out));
        cfg.set("webSocketPort", Value::make_number(0));
        cfg.set("syncMode", Value::make_bool(true));
        cfg.set("powerMode", Value::make_string("hybrid"));
        cfg.set("numThreads", Value::make_number(1));
        pipe = aegis_create_pipeline();
        if (aegis_load_data(pipe, raw.data(), rows, cols) != 0 || aegis_configure(pipe, cfg.dump().c_str()) != 0) {
            err = "pipeline: " + take(aegis_get_last_error(pipe));
            return false;
        }
        norm.assign(raw.size(), 0.0);
        for (int c = 0; c < cols; ++c) {
            double lo = 1e300, hi = -1e300;
            for (int r = 0; r < train_end; ++r) {
                lo = std::min(lo, raw[static_cast<size_t>(r) * cols + c]);
                hi = std::max(hi, raw[static_cast<size_t>(r) * cols + c]);
            }
            const double rng = hi - lo;
            if (c == out) out_scale = rng / 2.0;
            for (int r = 0; r < rows; ++r)
                norm[static_cast<size_t>(r) * cols + c] =
                    rng < 1e-30 ? 0.0 : -1.0 + 2.0 * (raw[static_cast<size_t>(r) * cols + c] - lo) / rng;
        }
        double m = 0.0;
        for (int r = 0; r < train_end; ++r) m = std::max(m, std::abs(norm[static_cast<size_t>(r) * cols + out]));
        bound = 10.0 * std::max(m, 1e-6);
        return true;
    }
    Value evaluate(const std::string& model) const {
        Value v;
        if (!aegis::json::parse(take(aegis_evaluate_model(pipe, model.c_str(), 0)), v)) v = Value::make_object();
        return v;
    }
};

static double core_seg(const Value& ev, const char* seg, const char* key) {
    const Value* m = ev.get("metrics");
    const Value* s = m ? m->get(seg) : nullptr;
    return s ? s->number_or(key, NAN) : NAN;
}

struct Scores {
    bool admissible_traj = false; // no divergence, no clamp
    double train = NAN, va = NAN, vb = NAN, val = NAN; // RMSE, normalized
    double min_abs_den = NAN;
    int sign_changes = 0;
};

static Scores score(const aegis::Chromosome& c, const std::vector<double>& th, const p6::Seg& tr,
                    const p6::Seg& va, int split) {
    Scores r;
    const int md = c.max_delay();
    const p6::Sim a = p6::simulate(c, th, tr);
    const p6::Sim b = p6::simulate(c, th, va);
    r.admissible_traj = !a.diverged && !b.diverged && !a.clamped && !b.clamped;
    if (!r.admissible_traj) return r;
    int n;
    const int s0 = std::max(40, md);
    r.train = std::sqrt(a.sse(s0, tr.rows, tr.data, tr.cols, tr.out, n) / n);
    r.va = std::sqrt(b.sse(40, split, va.data, va.cols, va.out, n) / n);
    r.vb = std::sqrt(b.sse(split, va.rows, va.data, va.cols, va.out, n) / n);
    r.val = std::sqrt(b.sse(40, va.rows, va.data, va.cols, va.out, n) / n);
    if (c.is_rational()) {
        r.min_abs_den = std::min(a.min_abs_den, b.min_abs_den);
        r.sign_changes = a.sign_changes + b.sign_changes;
    }
    return r;
}

int main(int argc, char** argv) {
    std::string bench, data_path, cfg_path, cell, runs_dir, out_path;
    int train_end = 0, val_end = 0;
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (a == "--selftest") return selftest();
        else if (a == "--bench") bench = next();
        else if (a == "--data") data_path = next();
        else if (a == "--config") cfg_path = next();
        else if (a == "--cell") cell = next();
        else if (a == "--runs") runs_dir = next();
        else if (a == "--output") out_path = next();
        else if (a == "--train-end") train_end = std::stoi(next());
        else if (a == "--val-end") val_end = std::stoi(next());
        else { std::cerr << "unknown option " << a << "\n"; return 2; }
    }
    std::string fname = fs::path(data_path).filename().string();
    std::transform(fname.begin(), fname.end(), fname.begin(), ::tolower);
    if (fname.find("test") != std::string::npos) { std::cerr << "refusing a test file\n"; return 2; }
    Variant V;
    if (!read_csv(data_path, V.raw, V.rows, V.cols) || V.cols != 2) { std::cerr << "cannot read data\n"; return 1; }
    if (val_end != V.rows || train_end <= 40 || train_end >= val_end) { std::cerr << "bad split\n"; return 2; }
    V.train_end = train_end; V.val_end = val_end;
    std::string err;
    if (!V.init(read_file(cfg_path), err)) { std::cerr << err << "\n"; return 1; }
    const int vstart = train_end - 40;
    const p6::Seg tr{V.norm.data(), train_end, V.cols, V.out, V.bound};
    const p6::Seg va{V.norm.data() + static_cast<size_t>(vstart) * V.cols, val_end - vstart, V.cols, V.out, V.bound};
    const int split = 40 + (val_end - train_end) / 2; // block row where V_B starts
    std::ofstream of(out_path, std::ios::app);
    if (!of) { std::cerr << "cannot write output\n"; return 1; }

    std::vector<std::pair<int, fs::path>> files;
    for (const auto& e : fs::directory_iterator(runs_dir)) {
        std::smatch m;
        const std::string nm = e.path().filename().string();
        if (std::regex_match(nm, m, std::regex(R"(run_(\d+)\.json)"))) files.push_back({std::stoi(m[1]), e.path()});
    }
    std::sort(files.begin(), files.end());
    for (const auto& [seed, path] : files) {
        Value v;
        if (!aegis::json::parse(read_file(path.string()), v)) continue;
        const Value* rep = v.get("report");
        const Value* model = rep ? rep->get("model") : nullptr;
        std::ostringstream L;
        L << "{\"bench\":" << aegis::json::str(bench) << ",\"cell\":" << aegis::json::str(cell) << ",\"seed\":" << seed;
        aegis::Chromosome c;
        if (!model || !aegis::chromosome_from_json(*model, c, aegis::PowerMode::Hybrid) ||
            c.coefficients.size() != c.regressors.size()) {
            L << ",\"error\":\"model not readable\"}";
            of << L.str() << "\n" << std::flush;
            continue;
        }
        int nden = 0;
        for (const auto& r : c.regressors) nden += r.is_denominator() ? 1 : 0;
        L << ",\"K\":" << c.num_regressors() + 1 << ",\"nDen\":" << nden << ",\"maxDelay\":" << c.max_delay();
        const Value core = V.evaluate(model->dump());
        const std::vector<double> th0 = phase0::pack(c);
        const Scores s0 = score(c, th0, tr, va, split);
        // Consistency with the core evaluator (iteration 0, normalized free-run RMSE).
        const double ct = core_seg(core, "train", "rmseFreeRun"), cv = core_seg(core, "validation", "rmseFreeRun");
        const double rt = std::abs(s0.train - ct) / std::max(std::abs(ct), 1e-300);
        const double rv = std::abs(s0.val - cv) / std::max(std::abs(cv), 1e-300);
        const bool consistent = s0.admissible_traj && rt <= 1e-9 && rv <= 1e-9;
        L << ",\"consistency\":{\"relTrain\":" << num(rt) << ",\"relVal\":" << num(rv)
          << ",\"ok\":" << aegis::json::boolean(consistent) << "}";
        L << ",\"original\":{\"trajOk\":" << aegis::json::boolean(s0.admissible_traj)
          << ",\"train\":" << num(s0.train * V.out_scale) << ",\"vA\":" << num(s0.va * V.out_scale)
          << ",\"vB\":" << num(s0.vb * V.out_scale) << ",\"val\":" << num(s0.val * V.out_scale)
          << ",\"minAbsDen\":" << num(s0.min_abs_den) << ",\"signChanges\":" << s0.sign_changes << "}";
        if (!consistent) {
            L << ",\"status\":\"inconsistent_or_inadmissible_original\"}";
            of << L.str() << "\n" << std::flush;
            std::cout << bench << " " << cell << " seed " << seed << ": skipped (consistency)\n" << std::flush;
            continue;
        }
        const double tau = c.is_rational() ? std::min(0.01, 0.5 * s0.min_abs_den) : 0.0;
        const auto t0 = std::chrono::steady_clock::now();
        const auto lm = p6::levenberg_marquardt(c, th0, tr, std::max(40, c.max_delay()));
        // Veto and choice on V_A among iterate 0 and every accepted iterate.
        int best = 0, n_adm = 0;
        Scores sb = s0;
        for (size_t it = 0; it < lm.accepted.size(); ++it) {
            const Scores si = it == 0 ? s0 : score(c, lm.accepted[it], tr, va, split);
            bool adm = si.admissible_traj;
            if (adm && c.is_rational()) adm = si.sign_changes <= s0.sign_changes && si.min_abs_den >= tau;
            if (!adm) continue;
            ++n_adm;
            if (si.va < sb.va) { sb = si; best = static_cast<int>(it); }
        }
        const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        aegis::Chromosome cr = c;
        phase0::unpack(lm.accepted[best], cr);
        const Value core_r = V.evaluate(aegis::chromosome_structure_json(cr));
        const double cvr = core_seg(core_r, "validation", "rmseFreeRun");
        L << ",\"lm\":{\"status\":" << aegis::json::str(lm.status) << ",\"iterations\":" << lm.iterations
          << ",\"accepted\":" << lm.accepted.size() - 1 << ",\"rejected\":" << lm.rejected
          << ",\"loss0\":" << num(lm.loss0) << ",\"loss\":" << num(lm.loss) << ",\"seconds\":" << num(secs) << "}"
          << ",\"tau\":" << num(tau) << ",\"admissibleIterates\":" << n_adm << ",\"chosenIterate\":" << best
          << ",\"refined\":{\"train\":" << num(sb.train * V.out_scale) << ",\"vA\":" << num(sb.va * V.out_scale)
          << ",\"vB\":" << num(sb.vb * V.out_scale) << ",\"val\":" << num(sb.val * V.out_scale)
          << ",\"minAbsDen\":" << num(sb.min_abs_den) << ",\"signChanges\":" << sb.sign_changes
          << ",\"coreValRelDiff\":" << num(std::abs(sb.val - cvr) / std::max(std::abs(cvr), 1e-300))
          << ",\"model\":" << aegis::chromosome_structure_json(cr) << "}"
          << ",\"ratioVB\":" << num(sb.vb / s0.vb) << "}";
        of << L.str() << "\n" << std::flush;
        std::cout << bench << " " << cell << " seed " << seed << ": " << lm.status << ", iterate " << best
                  << ", " << secs << " s\n" << std::flush;
    }
    return 0;
}
