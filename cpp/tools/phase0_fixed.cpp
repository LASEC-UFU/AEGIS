// phase0_fixed.cpp — Phase 0, experiments E1 (capacity with fixed structures,
// QR) and E2 (Levenberg–Marquardt on the training simulation error) as
// pre-registered in experiments/phase0/PHASE0_PREREG.md.
//
// Only the estimation file is read; there is deliberately no test option and
// files whose name contains "test" are refused. Every metric comes from the
// core evaluator (aegis_evaluate_model -> evaluate_segment).
//
// Usage:
//   aegis_phase0 --bench <name> --data <est.csv> --config <aegis_full.json>
//                --train-end N --val-end M --dce-ny a --dce-nu b --dce-degree d
//                [--champions <dir with run_*.json>] [--max-q 150] [--no-lm]
//                --output <file.jsonl>
#include "aegis/aegis_api.h"
#include "aegis/json_lite.hpp"
#include "aegis/model_io.hpp"
#include "phase0_core.hpp"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>

using aegis::json::Value;
namespace fs = std::filesystem;

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
        if (!ok || row.empty()) continue; // header
        if (cols == 0) cols = static_cast<int>(row.size());
        if (static_cast<int>(row.size()) != cols) return false;
        data.insert(data.end(), row.begin(), row.end());
        ++rows;
    }
    return rows > 0;
}

static std::string read_file(const std::string& path) {
    std::ifstream f(path);
    return std::string(std::istreambuf_iterator<char>(f), {});
}

/** One data variant (rows/columns) with its own pipeline and normalized copy. */
struct Variant {
    std::string name;
    std::vector<double> raw, norm;
    int rows = 0, cols = 0, out = 1, train_end = 0, val_end = 0;
    double bound = 10.0;
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
        // Min-max [-1, 1] on the training rows (same as the core normalizer).
        norm.assign(raw.size(), 0.0);
        for (int c = 0; c < cols; ++c) {
            double lo = 1e300, hi = -1e300;
            for (int r = 0; r < train_end; ++r) {
                lo = std::min(lo, raw[static_cast<size_t>(r) * cols + c]);
                hi = std::max(hi, raw[static_cast<size_t>(r) * cols + c]);
            }
            const double rng = hi - lo;
            for (int r = 0; r < rows; ++r)
                norm[static_cast<size_t>(r) * cols + c] =
                    rng < 1e-30 ? 0.0 : -1.0 + 2.0 * (raw[static_cast<size_t>(r) * cols + c] - lo) / rng;
        }
        double m = 0.0;
        for (int r = 0; r < train_end; ++r) m = std::max(m, std::abs(norm[static_cast<size_t>(r) * cols + out]));
        bound = 10.0 * std::max(m, 1e-6); // IndividualEvaluator::kDivergenceFactor
        return true;
    }
    Value evaluate(const std::string& model, bool refit) const {
        Value v;
        if (!aegis::json::parse(take(aegis_evaluate_model(pipe, model.c_str(), refit ? 1 : 0)), v))
            v = Value::make_object();
        return v;
    }
};

static std::string seg_json(const Value& res, const char* seg) {
    const Value* m = res.get("metrics");
    const Value* s = m ? m->get(seg) : nullptr;
    if (!s) return "null";
    std::ostringstream j;
    j << "{\"rmseFreeRunOrig\":" << aegis::json::num(s->number_or("rmseFreeRunOrig", NAN))
      << ",\"rmseOneStepOrig\":" << aegis::json::num(s->number_or("rmseOneStepOrig", NAN))
      << ",\"rmseFreeRun\":" << aegis::json::num(s->number_or("rmseFreeRun", NAN))
      << ",\"freeRunDiverged\":" << aegis::json::boolean(s->bool_or("freeRunDiverged", false))
      << ",\"n\":" << s->int_or("n", 0) << ",\"scoreStart\":" << s->int_or("scoreStart", 0) << "}";
    return j.str();
}

struct Spec {
    std::string id, family;
    std::string model;        // model JSON (no coefficients)
    std::string extra;        // extra JSON fields (seeds, original coefficient check)
    std::string original;     // original fitted model JSON (champions), may be empty
};

static void run_spec(const Variant& V, const Spec& sp, const std::string& bench, int max_q, bool do_lm,
                     std::ofstream& of) {
    using clock = std::chrono::steady_clock;
    const Value qr = V.evaluate(sp.model, true);
    std::ostringstream line;
    line << "{\"bench\":" << aegis::json::str(bench) << ",\"variant\":" << aegis::json::str(V.name)
         << ",\"id\":" << aegis::json::str(sp.id) << ",\"family\":" << aegis::json::str(sp.family);
    if (qr.has("error") || !qr.get("metrics")) {
        line << ",\"error\":" << aegis::json::str(qr.string_or("error", "evaluation failed")) << "}";
        of << line.str() << "\n" << std::flush;
        std::cout << "  " << sp.id << ": evaluation error\n";
        return;
    }
    aegis::Chromosome c;
    std::string err;
    aegis::chromosome_from_json(qr, c, aegis::PowerMode::Hybrid, &err);
    int zeros = 0;
    for (double v : c.coefficients) if (v == 0.0) ++zeros;
    const int q = static_cast<int>(c.coefficients.size()) + 1;
    line << ",\"K\":" << q << ",\"maxDelay\":" << c.max_delay()
         << ",\"canonicalKey\":" << aegis::json::str(phase0::canonical_key(c))
         << ",\"zeroCoefficients\":" << zeros << sp.extra
         << ",\"qr\":{\"train\":" << seg_json(qr, "train") << ",\"validation\":" << seg_json(qr, "validation")
         << ",\"model\":" << aegis::chromosome_structure_json(c) << "}";
    if (!sp.original.empty()) {
        const Value orig = V.evaluate(sp.original, false);
        aegis::Chromosome co;
        double maxdiff = NAN;
        if (aegis::chromosome_from_json(orig, co, aegis::PowerMode::Hybrid) && co.coefficients.size() == c.coefficients.size()) {
            maxdiff = std::abs(co.intercept - c.intercept);
            for (size_t i = 0; i < c.coefficients.size(); ++i) maxdiff = std::max(maxdiff, std::abs(co.coefficients[i] - c.coefficients[i]));
        }
        line << ",\"original\":{\"maxAbsCoefDiffVsRefit\":" << aegis::json::num(maxdiff)
             << ",\"validation\":" << seg_json(orig, "validation") << "}";
    }

    // Consistency of the Phase-0 simulator with the core evaluator (fatal per structure).
    std::string why;
    phase0::Problem pb{V.norm.data(), V.rows, V.cols, V.out, V.train_end, 40, V.bound};
    const bool sup = phase0::supported(c, &why);
    double rel = NAN;
    bool consistent = false;
    if (sup) {
        const auto sim = phase0::simulate(c, phase0::pack(c), pb);
        const Value* tr = qr.get("metrics")->get("train");
        const double ref = tr ? tr->number_or("rmseFreeRun", NAN) : NAN;
        if (!sim.diverged && sim.n > 0 && std::isfinite(ref)) {
            const double mine = std::sqrt(sim.sse / sim.n);
            rel = std::abs(mine - ref) / std::max(std::abs(ref), 1e-300);
            consistent = rel <= 1e-9;
        }
    }
    line << ",\"consistency\":{\"relDiffTrainFreeRun\":" << aegis::json::num(rel)
         << ",\"ok\":" << aegis::json::boolean(consistent) << "}";

    if (!do_lm) {
        line << ",\"lm\":{\"status\":\"not_requested\"}";
    } else if (!sup) {
        line << ",\"lm\":{\"status\":\"not_run\",\"reason\":" << aegis::json::str(why) << "}";
    } else if (q > max_q) {
        line << ",\"lm\":{\"status\":\"not_run\",\"reason\":\"q above limit\"}";
    } else if (!consistent) {
        line << ",\"lm\":{\"status\":\"consistency_fail\"}";
    } else {
        const auto t0 = clock::now();
        const auto lm = phase0::levenberg_marquardt(c, phase0::pack(c), pb);
        const double secs = std::chrono::duration<double>(clock::now() - t0).count();
        aegis::Chromosome cl = c;
        phase0::unpack(lm.theta, cl);
        const Value ev = V.evaluate(aegis::chromosome_structure_json(cl), false);
        line << ",\"lm\":{\"status\":" << aegis::json::str(lm.status)
             << ",\"iterations\":" << lm.iterations << ",\"accepted\":" << lm.accepted
             << ",\"rejected\":" << lm.rejected << ",\"loss0\":" << aegis::json::num(lm.loss0)
             << ",\"loss\":" << aegis::json::num(lm.loss) << ",\"seconds\":" << aegis::json::num(secs)
             << ",\"train\":" << seg_json(ev, "train") << ",\"validation\":" << seg_json(ev, "validation")
             << ",\"model\":" << aegis::chromosome_structure_json(cl) << "}";
    }
    line << "}";
    of << line.str() << "\n" << std::flush;
    std::cout << "  " << sp.id << " K=" << q << " done\n" << std::flush;
}

int main(int argc, char** argv) {
    std::string bench, data_path, cfg_path, champ_dir, out_path;
    int train_end = -1, val_end = -1, ny = 0, nu = 0, deg = 0, max_q = 150;
    bool do_lm = true;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() { return i + 1 < argc ? std::string(argv[++i]) : std::string(); };
        if (a == "--bench") bench = next();
        else if (a == "--data") data_path = next();
        else if (a == "--config") cfg_path = next();
        else if (a == "--champions") champ_dir = next();
        else if (a == "--output") out_path = next();
        else if (a == "--train-end") train_end = std::stoi(next());
        else if (a == "--val-end") val_end = std::stoi(next());
        else if (a == "--dce-ny") ny = std::stoi(next());
        else if (a == "--dce-nu") nu = std::stoi(next());
        else if (a == "--dce-degree") deg = std::stoi(next());
        else if (a == "--max-q") max_q = std::stoi(next());
        else if (a == "--no-lm") do_lm = false;
        else { std::cerr << "unknown option " << a << " (there is no test option by design)\n"; return 2; }
    }
    if (bench.empty() || data_path.empty() || cfg_path.empty() || out_path.empty() || train_end <= 0 ||
        val_end <= train_end || ny <= 0 || nu <= 0 || deg <= 0) {
        std::cerr << "missing or invalid arguments\n";
        return 2;
    }
    std::string fname = fs::path(data_path).filename().string();
    std::transform(fname.begin(), fname.end(), fname.begin(), ::tolower);
    if (fname.find("test") != std::string::npos) { std::cerr << "refusing a test file: " << data_path << "\n"; return 2; }

    std::vector<double> raw;
    int rows = 0, cols = 0;
    if (!read_csv(data_path, raw, rows, cols) || cols != 2) { std::cerr << "cannot read 2-column " << data_path << "\n"; return 1; }
    if (val_end != rows) { std::cerr << "val-end must equal the number of estimation rows (" << rows << ")\n"; return 2; }
    const std::string base_cfg = read_file(cfg_path);
    const int out = 1, in = 0;
    std::ofstream of(out_path);
    if (!of) { std::cerr << "cannot write " << out_path << "\n"; return 1; }

    using phase0::Candidate;
    auto lags = [&](int var_y, int var_u, int ylo, int yhi, int ulo, int uhi, int pmin, int pmax) {
        std::vector<Candidate> v;
        for (int p = pmin; p <= pmax; ++p) {
            for (int d = ylo; d <= yhi; ++d) v.push_back({var_y, d, p});
            for (int d = ulo; d <= uhi; ++d) v.push_back({var_u, d, p});
        }
        return v;
    };

    // ── Variant A: exact AEGIS split, delays from 1 ──────────────────────────
    Variant A;
    A.name = "lag1"; A.raw = raw; A.rows = rows; A.cols = cols; A.out = out;
    A.train_end = train_end; A.val_end = val_end;
    std::string err;
    if (!A.init(base_cfg, err)) { std::cerr << err << "\n"; return 1; }
    std::cout << "[phase0] " << bench << " rows=" << rows << " train_end=" << train_end << "\n";

    std::vector<Spec> specs;
    // CHAMP: distinct champions of the 1.1.0 aegis_full runs (only report.model is read).
    if (!champ_dir.empty()) {
        std::map<std::string, Spec> uniq;
        std::map<std::string, std::vector<int>> seeds;
        std::vector<std::string> order;
        for (int s = 1; s <= 10; ++s) {
            const fs::path f = fs::path(champ_dir) / ("run_" + std::to_string(s) + ".json");
            if (!fs::exists(f)) continue;
            Value v;
            if (!aegis::json::parse(read_file(f.string()), v)) continue;
            const Value* rep = v.get("report");
            const Value* model = rep ? rep->get("model") : nullptr;
            if (!model) continue;
            aegis::Chromosome c;
            if (!aegis::chromosome_from_json(*model, c, aegis::PowerMode::Hybrid)) continue;
            const std::string key = phase0::canonical_key(c);
            if (!uniq.count(key)) {
                Spec sp;
                sp.family = "CHAMP";
                aegis::Chromosome bare = c;
                bare.coefficients.clear();
                sp.model = aegis::chromosome_structure_json(bare);
                sp.original = model->dump();
                uniq[key] = sp;
                order.push_back(key);
            }
            seeds[key].push_back(s);
        }
        int idx = 1;
        for (const auto& key : order) {
            Spec sp = uniq[key];
            sp.id = "CHAMP_" + std::to_string(idx++);
            std::ostringstream e;
            e << ",\"seeds\":[";
            for (size_t i = 0; i < seeds[key].size(); ++i) { if (i) e << ","; e << seeds[key][i]; }
            e << "]";
            sp.extra = e.str();
            specs.push_back(sp);
        }
        std::cout << "[phase0] distinct champions: " << order.size() << "\n";
    }
    // ARX_L and PN_DCE.
    specs.push_back({"ARX_L", "ARX_L", phase0::model_json(lags(out, in, 1, ny, 1, nu, 1, 1)), "", ""});
    specs.push_back({"PN_DCE", "PN_DCE", phase0::model_json(lags(out, in, 1, ny, 1, nu, 1, deg)), "", ""});
    // PN_K: FROLS on the univariate dictionary (y 1..10, u 1..20, p 1..3), training rows [40, train_end).
    {
        const auto dict = lags(out, in, 1, 10, 1, 20, 1, 3);
        const auto sel = phase0::frols_select(dict, {}, 39, A.norm.data(), cols, out, 40, train_end);
        for (int K : {4, 9, 20, 40}) {
            if (static_cast<int>(sel.size()) < K - 1) continue;
            std::vector<Candidate> regs;
            for (int t = 0; t < K - 1; ++t) regs.push_back(dict[sel[t]]);
            specs.push_back({"PN_K" + std::to_string(K), "PN_K", phase0::model_json(regs), "", ""});
        }
    }
    // E1b: ARX_L spine forced + m nonlinear terms (p 2..3, same lags).
    {
        auto dict = lags(out, in, 1, ny, 1, nu, 1, 3);
        std::vector<int> forced;
        for (int i = 0; i < static_cast<int>(dict.size()); ++i) if (dict[i].power == 1) forced.push_back(i);
        const auto sel = phase0::frols_select(dict, forced, 5, A.norm.data(), cols, out, 40, train_end);
        for (int m : {1, 3, 5}) {
            const int n = static_cast<int>(forced.size()) + m;
            if (static_cast<int>(sel.size()) < n) continue;
            std::vector<Candidate> regs;
            for (int t = 0; t < n; ++t) regs.push_back(dict[sel[t]]);
            specs.push_back({"E1b_" + std::to_string(m), "E1b", phase0::model_json(regs), "", ""});
        }
    }
    for (const auto& sp : specs) run_spec(A, sp, bench, max_q, do_lm, of);

    // ── Control 1.4: rows-1, delays from 1 vs contemporaneous input ──────────
    Variant B;
    B.name = "rows-1"; B.rows = rows - 1; B.cols = cols; B.out = out;
    B.raw.assign(raw.begin(), raw.begin() + static_cast<size_t>(rows - 1) * cols);
    B.train_end = train_end; B.val_end = rows - 1;
    if (!B.init(base_cfg, err)) { std::cerr << err << "\n"; return 1; }
    run_spec(B, {"ARX_L", "ARX_L", phase0::model_json(lags(out, in, 1, ny, 1, nu, 1, 1)), "", ""}, bench, max_q, do_lm, of);
    run_spec(B, {"PN_DCE", "PN_DCE", phase0::model_json(lags(out, in, 1, ny, 1, nu, 1, deg)), "", ""}, bench, max_q, do_lm, of);

    Variant C;
    C.name = "rows-1+u0"; C.rows = rows - 1; C.cols = 3; C.out = out;
    C.raw.resize(static_cast<size_t>(rows - 1) * 3);
    for (int r = 0; r < rows - 1; ++r) {
        C.raw[static_cast<size_t>(r) * 3 + 0] = raw[static_cast<size_t>(r) * cols + 0];
        C.raw[static_cast<size_t>(r) * 3 + 1] = raw[static_cast<size_t>(r) * cols + 1];
        C.raw[static_cast<size_t>(r) * 3 + 2] = raw[static_cast<size_t>(r + 1) * cols + 0]; // u_lead(k) = u(k+1)
    }
    C.train_end = train_end; C.val_end = rows - 1;
    if (!C.init(base_cfg, err)) { std::cerr << err << "\n"; return 1; }
    // u_lead(k-d) = u(k-d+1): delays 1..nu cover u(k)..u(k-nu+1).
    run_spec(C, {"ARX_L0", "ARX_L0", phase0::model_json(lags(out, 2, 1, ny, 1, nu, 1, 1)), "", ""}, bench, max_q, do_lm, of);
    run_spec(C, {"PN_DCE0", "PN_DCE0", phase0::model_json(lags(out, 2, 1, ny, 1, nu, 1, deg)), "", ""}, bench, max_q, do_lm, of);

    for (Variant* v : {&A, &B, &C}) aegis_destroy_pipeline(v->pipe);
    std::cout << "[phase0] done -> " << out_path << "\n";
    return 0;
}
