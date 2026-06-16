// aegis_batch.cpp — CLI batch runner for AEGIS
// Runs N independent identification experiments, saves one JSON per run.
//
// Usage:
//   aegis_batch --data <csv> [--runs N] [--seed-start S] [--output DIR]
//               [--max-gen G] [--islands NI] [--pop-size NP]
//               [--output-col C] [--config <json|file>] [--verbose]
//
// Each run saves:  <output>/run_NN.json   (metrics + fitness history)
// Summary:         <output>/summary.json  (all runs, key metrics)

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <cstring>
#include <algorithm>
#include <stdexcept>

#ifdef _WIN32
#  include <windows.h>
#  include <direct.h>
#  define SLEEP_MS(ms) Sleep(ms)
#  define MKDIR(p)     _mkdir(p)
#else
#  include <unistd.h>
#  include <sys/stat.h>
#  define SLEEP_MS(ms) usleep((ms) * 1000)
#  define MKDIR(p)     mkdir(p, 0755)
#endif

#include "aegis/aegis_api.h"

// ─── Tiny JSON helpers ─────────────────────────────────────────────────────

static std::string json_escape(const std::string& s) {
    std::string r;
    r.reserve(s.size());
    for (unsigned char c : s) {
        if      (c == '"')  r += "\\\"";
        else if (c == '\\') r += "\\\\";
        else if (c == '\n') r += "\\n";
        else if (c == '\r') r += "\\r";
        else                r += c;
    }
    return r;
}

// Extract the raw value string for a JSON key (handles strings and numbers).
static std::string json_get(const std::string& json, const std::string& key) {
    std::string needle = "\"" + key + "\":";
    auto pos = json.find(needle);
    if (pos == std::string::npos) return "";
    pos += needle.size();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) ++pos;
    if (pos >= json.size()) return "";
    if (json[pos] == '"') {
        ++pos;
        auto end = json.find('"', pos);
        return end == std::string::npos ? "" : json.substr(pos, end - pos);
    }
    auto end = json.find_first_of(",}\n]", pos);
    std::string v = json.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
    // trim
    v.erase(v.find_last_not_of(" \t\r\n") + 1);
    return v;
}

// ─── CSV reader ────────────────────────────────────────────────────────────

static bool read_csv(const std::string& path,
                     std::vector<double>& data, int& rows, int& cols) {
    std::ifstream f(path);
    if (!f.is_open()) {
        std::cerr << "[batch] Cannot open data file: " << path << "\n";
        return false;
    }

    // Read all lines, auto-detect separator
    std::vector<std::vector<double>> mat;
    std::string line;
    char sep = 0;

    while (std::getline(f, line)) {
        if (line.empty()) continue;

        // Detect separator from first candidate line
        if (sep == 0) {
            // Try to find a numeric character; if none, assume header
            bool has_num = false;
            for (char c : line) {
                if (std::isdigit(static_cast<unsigned char>(c)) ||
                    c == '-' || c == '+') { has_num = true; break; }
            }
            if (!has_num) continue;
            if      (line.find('\t') != std::string::npos) sep = '\t';
            else if (line.find(';')  != std::string::npos) sep = ';';
            else                                            sep = ',';
        }

        // Skip non-numeric lines (remaining headers/comments)
        bool has_num = false;
        for (char c : line) {
            if (std::isdigit(static_cast<unsigned char>(c)) ||
                c == '-' || c == '+') { has_num = true; break; }
        }
        if (!has_num) continue;

        std::vector<double> row;
        std::istringstream ss(line);
        std::string tok;
        while (std::getline(ss, tok, sep)) {
            // trim whitespace
            tok.erase(tok.find_last_not_of(" \t\r") + 1);
            tok.erase(0, tok.find_first_not_of(" \t"));
            try { row.push_back(std::stod(tok)); }
            catch (...) { row.push_back(0.0); }
        }
        if (!row.empty()) mat.push_back(std::move(row));
    }

    if (mat.empty()) {
        std::cerr << "[batch] No numeric data found in: " << path << "\n";
        return false;
    }

    rows = static_cast<int>(mat.size());
    cols = static_cast<int>(mat[0].size());
    data.assign(rows * cols, 0.0);
    for (int r = 0; r < rows; ++r)
        for (int c = 0; c < static_cast<int>(mat[r].size()) && c < cols; ++c)
            data[r * cols + c] = mat[r][c];

    return true;
}

// ─── Utilities ─────────────────────────────────────────────────────────────

static std::string iso_timestamp() {
    auto now = std::time(nullptr);
    auto tm  = *std::localtime(&now);
    std::ostringstream os;
    os << std::put_time(&tm, "%Y-%m-%dT%H:%M:%S");
    return os.str();
}

static void make_dir(const std::string& path) {
    MKDIR(path.c_str());
}

static std::string pad2(int n) {
    return (n < 10 ? "0" : "") + std::to_string(n);
}

static void print_usage(const char* prog) {
    std::cout
        << "AEGIS Batch Runner — v" << aegis_version() << "\n\n"
        << "Usage:\n"
        << "  " << prog << " --data <csv> [options]\n\n"
        << "Options:\n"
        << "  --data        <file>   CSV/TSV input file (required)\n"
        << "  --runs        <N>      Number of independent runs (default: 10)\n"
        << "  --seed-start  <S>      First random seed (default: 0)\n"
        << "  --output      <dir>    Output directory (default: aegis_results/)\n"
        << "  --config      <arg>    JSON string OR path to .json config file\n"
        << "  --max-gen     <G>      Max generations override (default: 5000)\n"
        << "  --islands     <NI>     Islands override (default: 3)\n"
        << "  --pop-size    <NP>     Population per island override (default: 50)\n"
        << "  --output-col  <C>      0-based output column index (default: last)\n"
        << "  --verbose              Print progress every 200 generations\n"
        << "  --help                 Show this message\n\n"
        << "Examples:\n"
        << "  " << prog << " --data WH_estimation_uy.csv --runs 10 --output results/wh/\n"
        << "  " << prog << " --data data.csv --runs 5 --islands 3 --pop-size 50 --max-gen 3000\n";
}

// ─── Main ──────────────────────────────────────────────────────────────────

int main(int argc, char* argv[]) {

    // Default parameters
    std::string data_path;
    std::string output_dir  = "aegis_results";
    std::string user_config;
    int  num_runs    = 10;
    int  seed_start  = 0;
    int  max_gen     = 5000;
    int  num_islands = 3;
    int  pop_size    = 50;
    int  output_col  = -1;   // -1 = last column
    bool verbose     = false;

    // Argument parsing
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto need_next = [&]() -> std::string {
            if (i + 1 < argc) return argv[++i];
            std::cerr << "[batch] Missing value for " << a << "\n";
            std::exit(1);
        };

        if      (a == "--data")        data_path  = need_next();
        else if (a == "--runs")        num_runs   = std::stoi(need_next());
        else if (a == "--seed-start")  seed_start = std::stoi(need_next());
        else if (a == "--output")      output_dir = need_next();
        else if (a == "--config")      user_config = need_next();
        else if (a == "--max-gen")     max_gen    = std::stoi(need_next());
        else if (a == "--islands")     num_islands = std::stoi(need_next());
        else if (a == "--pop-size")    pop_size   = std::stoi(need_next());
        else if (a == "--output-col")  output_col = std::stoi(need_next());
        else if (a == "--verbose")     verbose    = true;
        else if (a == "--help" || a == "-h") { print_usage(argv[0]); return 0; }
        else { std::cerr << "[batch] Unknown option: " << a << "\n"; print_usage(argv[0]); return 1; }
    }

    if (data_path.empty()) {
        std::cerr << "[batch] --data is required\n";
        print_usage(argv[0]);
        return 1;
    }

    // Load CSV
    std::vector<double> raw_data;
    int rows = 0, cols = 0;
    if (!read_csv(data_path, raw_data, rows, cols)) return 1;
    if (output_col < 0) output_col = cols - 1;

    std::cout << "╔══════════════════════════════════════════════════╗\n"
              << "║  AEGIS Batch Runner  v" << aegis_version() << std::string(28 - strlen(aegis_version()), ' ') << "║\n"
              << "╚══════════════════════════════════════════════════╝\n\n"
              << "  Data   : " << data_path << " (" << rows << " rows × " << cols << " cols)\n"
              << "  Output : " << output_col << " (column index)\n"
              << "  Runs   : " << num_runs << "  (seeds " << seed_start
                               << " to " << (seed_start + num_runs - 1) << ")\n"
              << "  Config : islands=" << num_islands << "  pop=" << pop_size
                               << "  max_gen=" << max_gen << "\n"
              << "  Saving : " << output_dir << "/\n\n";

    make_dir(output_dir);

    // If user_config is a file path (not a JSON literal), read it
    if (!user_config.empty() && user_config.front() != '{') {
        std::ifstream cf(user_config);
        if (!cf.is_open()) {
            std::cerr << "[batch] Cannot open config file: " << user_config << "\n";
            return 1;
        }
        user_config = std::string(std::istreambuf_iterator<char>(cf), {});
    }

    // ── Run loop ────────────────────────────────────────────────────────

    std::string summary_array;   // JSON array of run summaries
    int ok_count = 0;

    for (int run = 0; run < num_runs; ++run) {
        int seed = seed_start + run;
        std::cout << "── Run " << (run + 1) << "/" << num_runs
                  << "  seed=" << seed << "  " << iso_timestamp() << " ──\n";

        // Create pipeline
        void* pipeline = aegis_create_pipeline();
        if (!pipeline) {
            std::cerr << "  [ERROR] aegis_create_pipeline() returned null\n";
            continue;
        }

        // Load data
        if (!aegis_load_data(pipeline, raw_data.data(), rows, cols)) {
            std::cerr << "  [ERROR] aegis_load_data() failed\n";
            aegis_destroy_pipeline(pipeline);
            continue;
        }

        // Build config JSON — merge user config with our overrides
        std::ostringstream cfg;
        if (!user_config.empty()) {
            // Strip trailing } and append our fields
            auto pos = user_config.rfind('}');
            cfg << user_config.substr(0, pos)
                << ",\"random_seed\":"   << seed
                << ",\"output_col\":"    << output_col
                << ",\"max_generations\":" << max_gen
                << ",\"num_islands\":"   << num_islands
                << ",\"population_size\":" << pop_size
                << "}";
        } else {
            cfg << "{"
                << "\"random_seed\":"    << seed    << ","
                << "\"output_col\":"     << output_col << ","
                << "\"max_generations\":" << max_gen << ","
                << "\"num_islands\":"    << num_islands << ","
                << "\"population_size\":" << pop_size
                << "}";
        }

        if (!aegis_configure(pipeline, cfg.str().c_str())) {
            std::cerr << "  [ERROR] aegis_configure() failed\n";
            aegis_destroy_pipeline(pipeline);
            continue;
        }

        // Start asynchronous execution
        auto t_wall_start = std::chrono::steady_clock::now();

        if (!aegis_start(pipeline)) {
            std::cerr << "  [ERROR] aegis_start() failed\n";
            aegis_destroy_pipeline(pipeline);
            continue;
        }

        // Poll until complete, collecting fitness history
        struct HistPoint { int gen; double fitness; };
        std::vector<HistPoint> hist;
        int last_gen = -1;
        std::string final_state;

        while (true) {
            SLEEP_MS(200);

            char* raw = aegis_get_status(pipeline);
            if (!raw) continue;
            std::string status(raw);
            aegis_free_string(raw);

            std::string state  = json_get(status, "state");
            std::string gen_s  = json_get(status, "generation");
            std::string fit_s  = json_get(status, "best_fitness");

            int    gen = gen_s.empty()  ? 0   : std::stoi(gen_s);
            double fit = fit_s.empty()  ? 0.0 : std::stod(fit_s);

            if (gen != last_gen) {
                hist.push_back({gen, fit});
                last_gen = gen;
                if (verbose && gen % 200 == 0 && gen > 0) {
                    std::cout << "    gen=" << std::setw(5) << gen
                              << "  fitness=" << std::fixed << std::setprecision(4) << fit << "\n";
                }
            }

            if (state == "completed" || state == "stopped" || state == "error") {
                final_state = state;
                std::cout << "  Done: state=" << state
                          << "  gen=" << gen
                          << "  fitness=" << std::fixed << std::setprecision(4) << fit << "\n";
                break;
            }
        }

        auto t_wall_end = std::chrono::steady_clock::now();
        double elapsed_s = std::chrono::duration<double>(t_wall_end - t_wall_start).count();

        // Retrieve final model and tuning log
        char* model_raw  = aegis_get_best_model(pipeline);
        char* tuning_raw = aegis_get_tuning_log(pipeline);

        std::string model_json  = model_raw  ? std::string(model_raw)  : "{}";
        std::string tuning_json = tuning_raw ? std::string(tuning_raw) : "[]";

        if (model_raw)  aegis_free_string(model_raw);
        if (tuning_raw) aegis_free_string(tuning_raw);

        // Extract key scalar fields
        auto mf = [&](const std::string& k) -> std::string {
            std::string v = json_get(model_json, k);
            return v.empty() ? "null" : v;
        };

        // Build fitness history JSON array
        std::ostringstream hist_json;
        hist_json << "[";
        for (size_t i = 0; i < hist.size(); ++i) {
            if (i) hist_json << ",";
            hist_json << "[" << hist[i].gen << ","
                      << std::fixed << std::setprecision(6) << hist[i].fitness << "]";
        }
        hist_json << "]";

        // Compose run result JSON
        std::ostringstream run_json;
        run_json << "{\n"
                 << "  \"run_id\":         " << run                      << ",\n"
                 << "  \"seed\":           " << seed                     << ",\n"
                 << "  \"method\":         \"AEGIS\",\n"
                 << "  \"timestamp\":      \"" << iso_timestamp()        << "\",\n"
                 << "  \"data_file\":      \"" << json_escape(data_path) << "\",\n"
                 << "  \"elapsed_s\":      " << std::fixed << std::setprecision(2) << elapsed_s << ",\n"
                 << "  \"final_gen\":      " << last_gen                 << ",\n"
                 << "  \"final_state\":    \"" << final_state             << "\",\n"
                 << "  \"r2_train\":       " << mf("r2_train")           << ",\n"
                 << "  \"r2_val\":         " << mf("r2_val")             << ",\n"
                 << "  \"r2_test\":        " << mf("r2_test")            << ",\n"
                 << "  \"rmse_train\":     " << mf("rmse_train")         << ",\n"
                 << "  \"rmse_val\":       " << mf("rmse_val")           << ",\n"
                 << "  \"rmse_test\":      " << mf("rmse_test")          << ",\n"
                 << "  \"num_terms\":      " << mf("num_terms")          << ",\n"
                 << "  \"max_delay\":      " << mf("max_delay")          << ",\n"
                 << "  \"bic\":            " << mf("bic")                << ",\n"
                 << "  \"aic\":            " << mf("aic")                << ",\n"
                 << "  \"config\":         " << cfg.str()                << ",\n"
                 << "  \"best_model\":     " << model_json               << ",\n"
                 << "  \"tuning_log\":     " << tuning_json              << ",\n"
                 << "  \"fitness_history\":" << hist_json.str()          << "\n"
                 << "}\n";

        // Write run file
        std::string run_path = output_dir + "/run_" + pad2(run) + ".json";
        std::ofstream rf(run_path);
        if (rf.is_open()) {
            rf << run_json.str();
            std::cout << "  Saved: " << run_path
                      << "  (" << std::fixed << std::setprecision(1) << elapsed_s << "s)\n";
            ++ok_count;
        } else {
            std::cerr << "  [ERROR] Cannot write: " << run_path << "\n";
        }

        // Append minimal record to summary array
        if (!summary_array.empty()) summary_array += ",\n";
        summary_array +=
            "    {\"run_id\":" + std::to_string(run) +
            ",\"seed\":"        + std::to_string(seed) +
            ",\"elapsed_s\":"   + std::to_string(elapsed_s) +
            ",\"final_gen\":"   + std::to_string(last_gen) +
            ",\"final_state\":\"" + final_state + "\"" +
            ",\"r2_train\":"    + mf("r2_train") +
            ",\"r2_val\":"      + mf("r2_val") +
            ",\"r2_test\":"     + mf("r2_test") +
            ",\"rmse_val\":"    + mf("rmse_val") +
            ",\"rmse_test\":"   + mf("rmse_test") +
            ",\"num_terms\":"   + mf("num_terms") +
            "}";

        aegis_destroy_pipeline(pipeline);
        std::cout << "\n";
    }

    // ── Summary JSON ────────────────────────────────────────────────────

    std::ostringstream summary;
    summary << "{\n"
            << "  \"aegis_version\": \"" << aegis_version()         << "\",\n"
            << "  \"method\":        \"AEGIS\",\n"
            << "  \"timestamp\":     \"" << iso_timestamp()          << "\",\n"
            << "  \"data_file\":     \"" << json_escape(data_path)   << "\",\n"
            << "  \"num_runs\":      " << num_runs                   << ",\n"
            << "  \"ok_runs\":       " << ok_count                   << ",\n"
            << "  \"seed_start\":    " << seed_start                 << ",\n"
            << "  \"max_gen\":       " << max_gen                    << ",\n"
            << "  \"num_islands\":   " << num_islands                << ",\n"
            << "  \"pop_size\":      " << pop_size                   << ",\n"
            << "  \"runs\": [\n"       << summary_array              << "\n  ]\n"
            << "}\n";

    std::string summary_path = output_dir + "/summary.json";
    std::ofstream sf(summary_path);
    if (sf.is_open()) sf << summary.str();

    std::cout << "══════════════════════════════════════════════════\n"
              << "  Complete: " << ok_count << "/" << num_runs << " runs OK\n"
              << "  Summary : " << summary_path << "\n"
              << "══════════════════════════════════════════════════\n";

    return (ok_count == num_runs) ? 0 : 1;
}
