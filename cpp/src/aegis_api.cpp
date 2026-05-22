#include "aegis/aegis_api.h"
#include "aegis/identification_pipeline.hpp"
#include "aegis/agent_controller.hpp"
#include <cstring>
#include <string>
#include <new>

using namespace aegis;

// ── String helpers ─────────────────────────────────────────────────────────

static char* dup_string(const std::string& s) {
    char* p = new (std::nothrow) char[s.size() + 1];
    if (!p) return nullptr;
    std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

// ── Pipeline API ───────────────────────────────────────────────────────────

extern "C" {

AEGIS_API void* aegis_create_pipeline(void) {
    try { return new IdentificationPipeline(); }
    catch (...) { return nullptr; }
}

AEGIS_API void aegis_destroy_pipeline(void* pipeline) {
    delete static_cast<IdentificationPipeline*>(pipeline);
}

AEGIS_API int aegis_load_data(
    void* pipeline, const double* data, int rows, int cols
) {
    if (!pipeline || !data) return -1;
    auto* p = static_cast<IdentificationPipeline*>(pipeline);
    return p->load_data(data, rows, cols) ? 0 : -1;
}

AEGIS_API int aegis_configure(void* pipeline, const char* json_config) {
    if (!pipeline || !json_config) return -1;
    auto* p = static_cast<IdentificationPipeline*>(pipeline);
    return p->configure(std::string(json_config)) ? 0 : -1;
}

AEGIS_API int aegis_start(void* pipeline) {
    if (!pipeline) return -1;
    return static_cast<IdentificationPipeline*>(pipeline)->start() ? 0 : -1;
}

AEGIS_API int aegis_pause(void* pipeline) {
    if (!pipeline) return -1;
    static_cast<IdentificationPipeline*>(pipeline)->pause();
    return 0;
}

AEGIS_API int aegis_resume(void* pipeline) {
    if (!pipeline) return -1;
    static_cast<IdentificationPipeline*>(pipeline)->resume();
    return 0;
}

AEGIS_API int aegis_stop(void* pipeline) {
    if (!pipeline) return -1;
    static_cast<IdentificationPipeline*>(pipeline)->stop();
    return 0;
}

AEGIS_API char* aegis_get_status(void* pipeline) {
    if (!pipeline) return dup_string("{\"error\":\"null pipeline\"}");
    return dup_string(static_cast<IdentificationPipeline*>(pipeline)->status_json());
}

AEGIS_API char* aegis_get_best_model(void* pipeline) {
    if (!pipeline) return dup_string("{\"error\":\"null pipeline\"}");
    return dup_string(static_cast<IdentificationPipeline*>(pipeline)->best_model_json());
}

AEGIS_API char* aegis_get_snapshot(void* pipeline) {
    if (!pipeline) return dup_string("{\"error\":\"null pipeline\"}");
    return dup_string(static_cast<IdentificationPipeline*>(pipeline)->snapshot_json());
}

AEGIS_API void aegis_free_string(char* ptr) {
    delete[] ptr;
}

AEGIS_API int aegis_apply_tuning(
    void* pipeline, const char* param_name, double new_value, const char* reason
) {
    if (!pipeline || !param_name) return -1;
    return static_cast<IdentificationPipeline*>(pipeline)->apply_tuning(
        std::string(param_name),
        new_value,
        reason ? std::string(reason) : std::string()
    );
}

AEGIS_API char* aegis_get_tuning_log(void* pipeline) {
    if (!pipeline) return dup_string("[]");
    return dup_string(static_cast<IdentificationPipeline*>(pipeline)->tuning_log_json());
}

// ── Agent server (standalone) ──────────────────────────────────────────────

AEGIS_API void* aegis_create_agent_server(int port) {
    try { return new AgentController(port); }
    catch (...) { return nullptr; }
}

AEGIS_API void aegis_destroy_agent_server(void* server) {
    delete static_cast<AgentController*>(server);
}

AEGIS_API int aegis_agent_server_start(void* server) {
    if (!server) return -1;
    return static_cast<AgentController*>(server)->start() ? 0 : -1;
}

AEGIS_API void aegis_agent_server_stop(void* server) {
    if (server) static_cast<AgentController*>(server)->stop();
}

AEGIS_API int aegis_agent_broadcast(void* server, const char* json) {
    if (!server || !json) return 0;
    return static_cast<AgentController*>(server)->broadcast(std::string(json));
}

AEGIS_API int aegis_agent_client_count(void* server) {
    if (!server) return 0;
    return static_cast<AgentController*>(server)->client_count();
}

AEGIS_API const char* aegis_version(void) {
    return "AEGIS C++ Core 1.0.0";
}

} // extern "C"
