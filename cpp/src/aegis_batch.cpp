// aegis_batch.cpp — reproducible multi-seed batch runner for AEGIS.
//
// Each run is executed in lockstep (syncMode) with an explicit seed, so a run
// is bit-for-bit reproducible for a given binary, data and configuration.
//
// Usage:
//   aegis_batch --data <est.csv> [--data-test <test.csv>] [--config <json|file>]
//               [--runs N] [--seed-start S] [--jobs J] [--output DIR]
//               [--label NAME] [--verbose]
//
// Outputs:  <output>/run_<seed>.json  (final report + history + wall time)
//           <output>/summary.json      (one line per run)

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#  include <direct.h>
#  define MKDIR(p) _mkdir(p)
#else
#  include <sys/stat.h>
#  define MKDIR(p) mkdir(p, 0755)
#endif

#include "aegis/aegis_api.h"
#include "aegis/json_lite.hpp"

using aegis::json::Value;

static std::string take(char* p) {
    if (!p) return std::string();
    std::string s(p);
    aegis_free_string(p);
    return s;
}

static bool read_csv(const std::string& path, std::vector<double>& data, int& rows, int& cols,
                     std::string* header) {
    std::ifstream f(path);
    if (!f.is_open()) { std::cerr << "[batch] cannot open " << path << "\n"; return false; }
    std::vector<std::vector<double>> mat;
    std::string line;
    char sep = 0;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        if (sep == 0) {
            if (line.find('\t') != std::string::npos) sep = '\t';
            else if (line.find(';') != std::string::npos) sep = ';';
            else if (line.find(',') != std::string::npos) sep = ',';
            else sep = ' ';
        }
        std::vector<double> row;
        std::istringstream ss(line);
        std::string tok;
        bool ok = true;
        while (std::getline(ss, tok, sep)) {
            tok.erase(0, tok.find_first_not_of(" \t"));
            tok.erase(tok.find_last_not_of(" \t") + 1);
            if (tok.empty()) continue;
            char* end = nullptr;
            const double v = std::strtod(tok.c_str(), &end);
            if (!end || *end != '\0' || !std::isfinite(v)) { ok = false; break; }
            row.push_back(v);
        }
        if (!ok) {
            if (mat.empty() && header && header->empty()) { *header = line; continue; }
            std::cerr << "[batch] non-numeric row skipped in " << path << ": " << line.substr(0, 60) << "\n";
            continue;
        }
        if (!row.empty()) mat.push_back(std::move(row));
    }
    if (mat.empty()) { std::cerr << "[batch] no numeric data in " << path << "\n"; return false; }
    cols = static_cast<int>(mat[0].size());
    for (const auto& r : mat)
        if (static_cast<int>(r.size()) != cols) { std::cerr << "[batch] ragged rows in " << path << "\n"; return false; }
    rows = static_cast<int>(mat.size());
    data.clear();
    data.reserve(static_cast<size_t>(rows) * cols);
    for (const auto& r : mat) data.insert(data.end(), r.begin(), r.end());
    return true;
}

static std::string iso_timestamp() {
    auto now = std::time(nullptr);
    std::tm tm{};
#ifdef _WIN32
    localtime_s(&tm, &now);
#else
    localtime_r(&now, &tm);
#endif
    std::ostringstream os;
    os << std::put_time(&tm, "%Y-%m-%dT%H:%M:%S");
    return os.str();
}

static void usage(const char* prog) {
    std::cout
        << "AEGIS batch runner (" << aegis_version() << ")\n\n"
        << "  " << prog << " --data <est.csv> [options]\n\n"
        << "  --data <file>        estimation data (CSV/TSV; optional header row)\n"
        << "  --data-test <file>   separate test record (appended; testStartRow set automatically)\n"
        << "  --config <arg>       JSON object or path to a JSON file (see docs/CONFIGURATION.md)\n"
        << "  --runs <N>           independent runs (default 10)\n"
        << "  --seed-start <S>     first seed (default 1); run i uses seed S+i\n"
        << "  --jobs <J>           runs executed in parallel (default 1)\n"
        << "  --output <dir>       output directory (default aegis_results)\n"
        << "  --label <name>       condition label stored in every record\n"
        << "  --set key=value      override one configuration key (value parsed as JSON)\n"
        << "  --verbose            progress every 100 generations\n";
}

int main(int argc, char* argv[]) {
    std::string data_path, test_path, output_dir = "aegis_results", user_config, label = "aegis";
    int runs = 10, seed_start = 1, jobs = 1;
    bool verbose = false;
    std::vector<std::string> overrides;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 < argc) return argv[++i];
            std::cerr << "[batch] missing value for " << a << "\n";
            std::exit(2);
        };
        if      (a == "--data")       data_path = next();
        else if (a == "--data-test")  test_path = next();
        else if (a == "--config")     user_config = next();
        else if (a == "--runs")       runs = std::stoi(next());
        else if (a == "--seed-start") seed_start = std::stoi(next());
        else if (a == "--jobs")       jobs = std::max(1, std::stoi(next()));
        else if (a == "--output")     output_dir = next();
        else if (a == "--label")      label = next();
        else if (a == "--verbose")    verbose = true;
        else if (a == "--set")        overrides.push_back(next());
        else if (a == "--help" || a == "-h") { usage(argv[0]); return 0; }
        else { std::cerr << "[batch] unknown option " << a << "\n"; usage(argv[0]); return 2; }
    }
    if (data_path.empty()) { usage(argv[0]); return 2; }

    std::vector<double> data;
    int rows = 0, cols = 0;
    std::string header;
    if (!read_csv(data_path, data, rows, cols, &header)) return 1;
    int est_rows = rows;
    if (!test_path.empty()) {
        std::vector<double> td;
        int trows = 0, tcols = 0;
        std::string th;
        if (!read_csv(test_path, td, trows, tcols, &th)) return 1;
        if (tcols != cols) { std::cerr << "[batch] test file has a different number of columns\n"; return 1; }
        data.insert(data.end(), td.begin(), td.end());
        rows += trows;
    }

    if (!user_config.empty() && user_config.front() != '{') {
        std::ifstream cf(user_config);
        if (!cf.is_open()) { std::cerr << "[batch] cannot open config " << user_config << "\n"; return 1; }
        user_config.assign(std::istreambuf_iterator<char>(cf), {});
    }
    Value base = Value::make_object();
    if (!user_config.empty()) {
        std::string err;
        if (!aegis::json::parse(user_config, base, &err) || !base.is_object()) {
            std::cerr << "[batch] invalid config JSON: " << err << "\n";
            return 1;
        }
    }
    // --set key=value overrides (value parsed as JSON, else taken as a string).
    for (const auto& kv : overrides) {
        const auto eq = kv.find('=');
        if (eq == std::string::npos) { std::cerr << "[batch] --set expects key=value\n"; return 2; }
        Value val;
        const std::string rhs = kv.substr(eq + 1);
        if (!aegis::json::parse(rhs, val)) val = Value::make_string(rhs);
        base.set(kv.substr(0, eq), val);
    }
    // Separate test record: estimation rows are split into train/validation.
    if (!test_path.empty()) {
        if (!base.has("trainEndRow")) {
            const double tr = base.number_or("trainRatio", 0.8);
            base.set("trainEndRow", Value::make_number(std::floor(est_rows * tr)));
        }
        if (!base.has("valEndRow")) base.set("valEndRow", Value::make_number(est_rows));
        base.set("testStartRow", Value::make_number(est_rows));
    }
    base.set("syncMode", Value::make_bool(true));
    base.set("webSocketPort", Value::make_number(0));
    if (!base.has("numThreads")) base.set("numThreads", Value::make_number(1));

    MKDIR(output_dir.c_str());
    std::cout << "AEGIS batch: " << data_path << (test_path.empty() ? "" : " + " + test_path)
              << " (" << rows << "x" << cols << "), runs=" << runs << ", seeds " << seed_start
              << ".." << seed_start + runs - 1 << ", jobs=" << jobs << ", label=" << label << "\n";

    std::mutex io_mutex;
    std::vector<std::string> summary(runs);
    std::atomic<int> next_run{0}, ok_runs{0};

    auto worker = [&]() {
        while (true) {
            const int run = next_run.fetch_add(1);
            if (run >= runs) break;
            const int seed = seed_start + run;
            Value cfgv = base;
            cfgv.set("randomSeed", Value::make_number(seed));
            const std::string cfg = cfgv.dump();

            void* p = aegis_create_pipeline();
            if (!p) continue;
            auto fail = [&](const char* what) {
                std::lock_guard<std::mutex> lk(io_mutex);
                std::cerr << "[batch] seed " << seed << ": " << what << " failed: "
                          << take(aegis_get_last_error(p)) << "\n";
                aegis_destroy_pipeline(p);
            };
            if (aegis_load_data(p, data.data(), rows, cols) != 0) { fail("load_data"); continue; }
            if (aegis_configure(p, cfg.c_str()) != 0) { fail("configure"); continue; }
            const auto t0 = std::chrono::steady_clock::now();
            if (aegis_start(p) != 0) { fail("start"); continue; }
            int last_report = 0;
            while (true) {
                const int ran = aegis_step(p, 25);
                if (ran <= 0) break;
                if (verbose) {
                    Value st;
                    if (aegis::json::parse(take(aegis_get_status(p)), st)) {
                        const int g = st.int_or("generation", 0);
                        if (g / 100 > last_report / 100) {
                            std::lock_guard<std::mutex> lk(io_mutex);
                            std::cout << "  seed " << seed << " gen " << g << " best "
                                      << st.number_or("bestFitness", NAN) << " phase "
                                      << st.int_or("phase", 0) << "\n";
                        }
                        last_report = g;
                    }
                }
            }
            const double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            const std::string report = take(aegis_get_final_report(p));
            const std::string history = take(aegis_get_history(p));
            aegis_destroy_pipeline(p);

            std::ostringstream rec;
            rec << "{\"schema\":\"aegis.batch_run/1\",\"label\":" << aegis::json::str(label)
                << ",\"seed\":" << seed << ",\"timestamp\":" << aegis::json::str(iso_timestamp())
                << ",\"dataFile\":" << aegis::json::str(data_path)
                << ",\"testFile\":" << aegis::json::str(test_path)
                << ",\"wallSeconds\":" << aegis::json::num(wall)
                << ",\"report\":" << report << ",\"history\":" << history << "}\n";
            const std::string path = output_dir + "/run_" + std::to_string(seed) + ".json";
            std::ofstream rf(path);
            rf << rec.str();

            Value rv;
            std::ostringstream line;
            line << "{\"seed\":" << seed << ",\"wallSeconds\":" << aegis::json::num(wall);
            if (aegis::json::parse(report, rv)) {
                line << ",\"stopReason\":" << aegis::json::str(rv.string_or("stopReason", ""))
                     << ",\"generations\":" << rv.int_or("generations", 0)
                     << ",\"evaluations\":" << aegis::json::num(rv.number_or("evaluations", NAN))
                     << ",\"numRegressors\":" << rv.int_or("numRegressors", 0);
                if (const Value* m = rv.get("metrics")) {
                    for (const char* split : {"train", "validation", "test"}) {
                        if (const Value* s = m->get(split)) {
                            line << ",\"" << split << "RmseFreeRun\":" << aegis::json::num(s->number_or("rmseFreeRun", NAN))
                                 << ",\"" << split << "RmseOneStep\":" << aegis::json::num(s->number_or("rmseOneStep", NAN))
                                 << ",\"" << split << "RmseFreeRunOrig\":" << aegis::json::num(s->number_or("rmseFreeRunOrig", NAN));
                        }
                    }
                }
                ok_runs.fetch_add(1);
            }
            line << "}";
            summary[run] = line.str();
            std::lock_guard<std::mutex> lk(io_mutex);
            std::cout << "  seed " << seed << " done in " << std::fixed << std::setprecision(1) << wall
                      << " s -> " << path << "\n";
        }
    };
    std::vector<std::thread> pool;
    for (int j = 0; j < std::min(jobs, runs); ++j) pool.emplace_back(worker);
    for (auto& t : pool) t.join();

    std::ofstream sf(output_dir + "/summary.json");
    sf << "{\"schema\":\"aegis.batch_summary/1\",\"label\":" << aegis::json::str(label)
       << ",\"version\":" << aegis::json::str(aegis_version())
       << ",\"build\":" << aegis_build_info()
       << ",\"dataFile\":" << aegis::json::str(data_path) << ",\"testFile\":" << aegis::json::str(test_path)
       << ",\"rows\":" << rows << ",\"cols\":" << cols
       << ",\"config\":" << base.dump() << ",\"runs\":[\n";
    bool first = true;
    for (const auto& s : summary) {
        if (s.empty()) continue;
        if (!first) sf << ",\n";
        sf << "  " << s;
        first = false;
    }
    sf << "\n]}\n";
    std::cout << "completed " << ok_runs.load() << "/" << runs << " runs\n";
    return ok_runs.load() == runs ? 0 : 1;
}
