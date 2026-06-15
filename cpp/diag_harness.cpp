#include "aegis/aegis_api.h"
#include <cstdio>
#include <vector>
#include <fstream>
#include <sstream>
#include <string>
#include <thread>
#include <chrono>

int main() {
    std::vector<double> data;
    std::ifstream f("../../WienerHammersteinFiles/WH_estimation_uy.csv");
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

    void* p = aegis_create_pipeline();
    aegis_load_data(p, data.data(), rows, 2);

    const char* cfg = "{\"normalizerType\":\"minmax\",\"outputCol\":1,\"numIslands\":3,"
                       "\"populationSize\":50,\"mutationFactor\":0.5,\"crossoverRate\":0.9,"
                       "\"elitismCount\":2,\"migrationInterval\":20,\"migrationRate\":0.1,"
                       "\"maxRegressors\":8,\"maxDelay\":20,\"pmin\":0.5,\"pmax\":3.0,"
                       "\"stagnationLimit\":5000,\"complexityPenalty\":1.0,\"webSocketPort\":0}";
    aegis_configure(p, cfg);
    aegis_start(p);

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
    aegis_destroy_pipeline(p);
    return 0;
}
