// evaluate_models.cpp — re-evaluates saved models on a dataset with the AEGIS
// metric code (same normalization, splits and free-run protocol).
//
// Inputs are run files produced by aegis_batch (report.model), by aegis_frols
// (selectedByValidationSimulation.model / selectedByBic.model) or by the
// legacy HEAD runner (bestModel). Models without "powerMode" use the
// configuration's powerMode (pass {"powerMode":"legacy"} for HEAD models).
//
// Usage:
//   aegis_evaluate_models --data est.csv [--data-test test.csv] --config <json|file>
//                         [--refit 0|1] --output out.jsonl run1.json run2.json ...

#include "aegis/aegis_api.h"
#include "aegis/json_lite.hpp"

#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

using aegis::json::Value;

static std::string take(char* p) { std::string s = p ? p : ""; aegis_free_string(p); return s; }

static bool read_csv(const std::string& path, std::vector<double>& data, int& rows, int& cols) {
    std::ifstream f(path);
    if (!f.is_open()) return false;
    std::string line;
    rows = 0; cols = 0;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        std::stringstream ss(line);
        std::string tok;
        std::vector<double> r;
        bool ok = true;
        while (std::getline(ss, tok, ',')) {
            char* end = nullptr;
            const double v = std::strtod(tok.c_str(), &end);
            if (end == tok.c_str()) { ok = false; break; }
            r.push_back(v);
        }
        if (!ok || r.empty()) continue;
        if (!cols) cols = static_cast<int>(r.size());
        if (static_cast<int>(r.size()) != cols) return false;
        data.insert(data.end(), r.begin(), r.end());
        ++rows;
    }
    return rows > 0;
}

static std::string slurp(const std::string& p) {
    std::ifstream f(p);
    return std::string(std::istreambuf_iterator<char>(f), {});
}

int main(int argc, char** argv) {
    std::string data_path, test_path, cfg_arg = "{}", out_path = "evaluations.jsonl";
    int refit = 0;
    std::vector<std::string> inputs;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() { return i + 1 < argc ? std::string(argv[++i]) : std::string(); };
        if (a == "--data") data_path = next();
        else if (a == "--data-test") test_path = next();
        else if (a == "--config") cfg_arg = next();
        else if (a == "--refit") refit = std::stoi(next());
        else if (a == "--output") out_path = next();
        else inputs.push_back(a);
    }
    std::vector<double> data;
    int rows = 0, cols = 0;
    if (!read_csv(data_path, data, rows, cols)) { std::cerr << "cannot read " << data_path << "\n"; return 1; }
    const int est_rows = rows;
    if (!test_path.empty()) {
        std::vector<double> td; int tr = 0, tc = 0;
        if (!read_csv(test_path, td, tr, tc) || tc != cols) { std::cerr << "cannot read test\n"; return 1; }
        data.insert(data.end(), td.begin(), td.end());
        rows += tr;
    }
    if (!cfg_arg.empty() && cfg_arg.front() != '{') cfg_arg = slurp(cfg_arg);
    Value cfg;
    if (!aegis::json::parse(cfg_arg, cfg)) { std::cerr << "invalid config\n"; return 1; }
    if (!test_path.empty()) {
        if (!cfg.has("trainEndRow"))
            cfg.set("trainEndRow", Value::make_number(std::floor(est_rows * cfg.number_or("trainRatio", 0.8))));
        if (!cfg.has("valEndRow")) cfg.set("valEndRow", Value::make_number(est_rows));
        cfg.set("testStartRow", Value::make_number(est_rows));
    }
    cfg.set("webSocketPort", Value::make_number(0));
    void* p = aegis_create_pipeline();
    if (aegis_load_data(p, data.data(), rows, cols) != 0 || aegis_configure(p, cfg.dump().c_str()) != 0) {
        std::cerr << "configure failed: " << take(aegis_get_last_error(p)) << "\n";
        return 1;
    }
    std::ofstream out(out_path);
    int n_ok = 0;
    for (const auto& in : inputs) {
        Value run;
        if (!aegis::json::parse(slurp(in), run)) { std::cerr << "skip (invalid JSON) " << in << "\n"; continue; }
        std::vector<std::pair<std::string, const Value*>> models;
        if (const Value* r = run.get("report"); r && r->get("model") && !r->get("model")->is_null())
            models.emplace_back("aegis", r->get("model"));
        if (const Value* b = run.get("bestModel"); b && b->has("regressors"))
            models.emplace_back("legacy_head", b);
        if (const Value* v = run.get("selectedByValidationSimulation"); v && v->get("model"))
            models.emplace_back("frols_valsim", v->get("model"));
        if (const Value* v = run.get("selectedByBic"); v && v->get("model"))
            models.emplace_back("frols_bic", v->get("model"));
        for (const auto& [kind, m] : models) {
            const std::string res = take(aegis_evaluate_model(p, m->dump().c_str(), refit));
            Value rv;
            aegis::json::parse(res, rv);
            out << "{\"input\":" << aegis::json::str(in) << ",\"kind\":" << aegis::json::str(kind)
                << ",\"seed\":" << aegis::json::num(run.number_or("seed",
                       run.get("config") ? run.get("config")->number_or("randomSeed", NAN) : NAN))
                << ",\"refit\":" << refit << ",\"testFile\":" << aegis::json::str(test_path)
                << ",\"result\":" << (res.empty() ? "null" : res) << "}\n";
            if (!rv.has("error")) ++n_ok;
            else std::cerr << in << " (" << kind << "): " << rv.string_or("error", "") << "\n";
        }
    }
    aegis_destroy_pipeline(p);
    std::cout << n_ok << " model evaluations -> " << out_path << "\n";
    return 0;
}
