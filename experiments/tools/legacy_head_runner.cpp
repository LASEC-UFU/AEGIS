// legacy_head_runner.cpp — runs the ORIGINAL AEGIS core (commit 9e4b1d8) to
// establish the baseline of the code as it was before the audit.
//
// Only the C API that existed in 9e4b1d8 is used (asynchronous native mode,
// camelCase configuration keys). The program records the best model JSON,
// the tuning log and a time series of (elapsed, generation, bestFitness)
// sampled from aegis_get_status. Test metrics are NOT taken from this binary
// (its normalizer clips held-out data); models are re-evaluated afterwards by
// tools/evaluate_models with powerMode=legacy.
//
// Build (MinGW):
//   g++ -O2 -std=c++17 legacy_head_runner.cpp -o legacy_head_runner.exe \
//       -L../bin/head-9e4b1d8 -l:libaegis_core.dll
//
// Usage: legacy_head_runner <data.csv> <config.json-string> <output.json>

#include <chrono>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

extern "C" {
void* aegis_create_pipeline(void);
void  aegis_destroy_pipeline(void*);
int   aegis_load_data(void*, const double*, int, int);
int   aegis_configure(void*, const char*);
int   aegis_start(void*);
int   aegis_stop(void*);
char* aegis_get_status(void*);
char* aegis_get_best_model(void*);
char* aegis_get_tuning_log(void*);
void  aegis_free_string(char*);
const char* aegis_version(void);
}

static std::string take(char* p) { std::string s = p ? p : ""; aegis_free_string(p); return s; }

static std::string field(const std::string& j, const std::string& key) {
    auto p = j.find("\"" + key + "\":");
    if (p == std::string::npos) return "";
    p += key.size() + 3;
    if (j[p] == '"') { auto e = j.find('"', p + 1); return j.substr(p + 1, e - p - 1); }
    auto e = j.find_first_of(",}", p);
    return j.substr(p, e - p);
}

int main(int argc, char** argv) {
    if (argc < 4) { std::cerr << "usage: legacy_head_runner data.csv config output.json\n"; return 2; }
    std::ifstream f(argv[1]);
    std::string line;
    std::vector<double> data;
    int rows = 0, cols = 0;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        std::stringstream ss(line);
        std::string tok;
        std::vector<double> r;
        bool ok = true;
        while (std::getline(ss, tok, ',')) {
            char* end = nullptr;
            double v = std::strtod(tok.c_str(), &end);
            if (end == tok.c_str()) { ok = false; break; }
            r.push_back(v);
        }
        if (!ok || r.empty()) continue;
        cols = static_cast<int>(r.size());
        data.insert(data.end(), r.begin(), r.end());
        ++rows;
    }
    void* p = aegis_create_pipeline();
    if (aegis_load_data(p, data.data(), rows, cols) != 0) { std::cerr << "load failed\n"; return 1; }
    if (aegis_configure(p, argv[2]) != 0) { std::cerr << "configure failed\n"; return 1; }
    const auto t0 = std::chrono::steady_clock::now();
    if (aegis_start(p) != 0) { std::cerr << "start failed\n"; return 1; }
    std::ostringstream series;
    series << "[";
    bool first = true;
    std::string state, last_gen = "-1";
    while (true) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        const std::string st = take(aegis_get_status(p));
        state = field(st, "state");
        const std::string gen = field(st, "generation");
        const double t = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        if (gen != last_gen) {
            if (!first) series << ",";
            series << "[" << t << "," << gen << "," << (field(st, "bestFitness").empty() ? "null" : field(st, "bestFitness")) << "]";
            first = false;
            last_gen = gen;
        }
        if (state == "completed" || state == "stopped" || state == "error") break;
    }
    const double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    const std::string model = take(aegis_get_best_model(p));
    const std::string log = take(aegis_get_tuning_log(p));
    const std::string status = take(aegis_get_status(p));
    series << "]";
    std::ofstream out(argv[3]);
    out << "{\"schema\":\"aegis.legacy_head_run/1\",\"version\":\"" << aegis_version()
        << "\",\"commit\":\"9e4b1d8\",\"config\":" << argv[2] << ",\"wallSeconds\":" << wall
        << ",\"finalStatus\":" << status << ",\"bestModel\":" << model
        << ",\"tuningLogRaw\":" << "\"(not parsed: legacy log may contain unescaped strings)\""
        << ",\"tuningLogLength\":" << log.size()
        << ",\"series\":" << series.str() << "}\n";
    std::ofstream lf(std::string(argv[3]) + ".tuning_log.txt");
    lf << log;
    aegis_destroy_pipeline(p);
    std::cout << "done state=" << state << " wall=" << wall << "s -> " << argv[3] << "\n";
    return 0;
}
