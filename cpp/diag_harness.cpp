#include "aegis/aegis_api.h"
#include <cstdio>
#include <vector>
#include <fstream>
#include <sstream>
#include <string>
#include <thread>
#include <chrono>

int main(int argc, char** argv) {
    std::vector<double> data;
    const char* data_path = argc > 1
        ? argv[1]
        : "../../../WienerHammersteinFiles/WH_estimation_uy.csv";
    std::ifstream f(data_path);
    if (!f) {
        std::fprintf(stderr, "Unable to open dataset: %s\n", data_path);
        return 1;
    }
    std::string line;
    std::getline(f, line); // header
    int rows = 0;
    while (std::getline(f, line)) {
        std::stringstream ss(line);
        std::string a, b;
        std::getline(ss, a, ',');
        std::getline(ss, b, ',');
        data.push_back(std::stod(a));
        data.push_back(std::stod(b));
        rows++;
    }
    printf("Loaded %d rows\n", rows);
    if (rows == 0) {
        std::fprintf(stderr, "Dataset contains no data rows: %s\n", data_path);
        return 1;
    }

    void* p = aegis_create_pipeline();
    if (!p) {
        std::fprintf(stderr, "Unable to create pipeline\n");
        return 1;
    }
    if (aegis_load_data(p, data.data(), rows, 2) != 0) {
        std::fprintf(stderr, "Unable to load dataset into pipeline\n");
        aegis_destroy_pipeline(p);
        return 1;
    }

    const char* cfg = "{\"normalizerType\":\"minmax\",\"outputCol\":1,\"numIslands\":3,"
                       "\"populationSize\":50,\"mutationFactor\":0.5,\"crossoverRate\":0.9,"
                       "\"elitismCount\":2,\"migrationInterval\":20,\"migrationRate\":0.1,"
                       "\"maxRegressors\":8,\"maxDelay\":40,\"pmin\":0.5,\"pmax\":3.0,"
                       "\"stagnationLimit\":5000,\"complexityPenalty\":0.01,"
                       "\"randomSeed\":42,\"webSocketPort\":0}";
    if (aegis_configure(p, cfg) != 0 || aegis_start(p) != 0) {
        std::fprintf(stderr, "Unable to configure or start pipeline\n");
        aegis_destroy_pipeline(p);
        return 1;
    }

    for (int i = 0; i < 30; i++) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        char* status = aegis_get_status(p);
        char* best = aegis_get_best_model(p);
        printf("t=%ds status=%s\n", i+1, status);
        printf("t=%ds best=%s\n\n", i+1, best);
        aegis_free_string(status);
        aegis_free_string(best);
    }

    aegis_stop(p);
    char* final_best = aegis_get_best_model(p);
    printf("final best=%s\n", final_best);
    aegis_free_string(final_best);
    aegis_destroy_pipeline(p);
    return 0;
}
