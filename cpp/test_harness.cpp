#include "aegis/aegis_api.h"
#include <cstdio>
#include <vector>
#include <fstream>
#include <sstream>
#include <string>
#include <thread>
#include <chrono>

int main(int argc, char** argv) {
    // Load WH_estimation_uy.csv (u,y), skip header
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
    printf("Loaded %d rows, %zu values\n", rows, data.size());
    if (rows == 0) {
        std::fprintf(stderr, "Dataset contains no data rows: %s\n", data_path);
        return 1;
    }

    void* p = aegis_create_pipeline();
    printf("pipeline = %p\n", p);
    if (!p) {
        std::fprintf(stderr, "Unable to create pipeline\n");
        return 1;
    }

    int rc = aegis_load_data(p, data.data(), rows, 2);
    printf("load_data rc = %d\n", rc);
    if (rc != 0) {
        aegis_destroy_pipeline(p);
        return 1;
    }

    const char* cfg = "{\"normalizerType\":\"minmax\",\"outputCol\":1,\"numIslands\":3,"
                       "\"populationSize\":50,\"mutationFactor\":0.5,\"crossoverRate\":0.9,"
                       "\"elitismCount\":2,\"migrationInterval\":20,\"migrationRate\":0.1,"
                       "\"maxRegressors\":8,\"maxDelay\":40,\"pmin\":0.5,\"pmax\":3.0,"
                       "\"stagnationLimit\":500,\"complexityPenalty\":0.01,"
                       "\"randomSeed\":42,\"webSocketPort\":0}";
    rc = aegis_configure(p, cfg);
    printf("configure rc = %d\n", rc);
    if (rc != 0) {
        aegis_destroy_pipeline(p);
        return 1;
    }

    rc = aegis_start(p);
    printf("start rc = %d\n", rc);
    if (rc != 0) {
        aegis_destroy_pipeline(p);
        return 1;
    }

    for (int i = 0; i < 10; i++) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        char* status = aegis_get_status(p);
        char* snap = aegis_get_snapshot(p);
        printf("t=%ds status=%s\n", i+1, status);
        printf("t=%ds snap=%s\n", i+1, snap);
        aegis_free_string(status);
        aegis_free_string(snap);
    }

    aegis_stop(p);
    aegis_destroy_pipeline(p);
    return 0;
}
