#include "aegis/aegis_api.h"
#include "aegis/identification_pipeline.hpp"
#include "aegis/agent_controller.hpp"
#include "aegis/model_io.hpp"
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

static IdentificationPipeline* P(void* p) { return static_cast<IdentificationPipeline*>(p); }

// Exceptions must never cross the C ABI.
template <typename F, typename R>
static R guarded(F&& f, R on_error) {
    try { return f(); } catch (...) { return on_error; }
}

extern "C" {

AEGIS_API void* aegis_create_pipeline(void) {
    try { return new IdentificationPipeline(); }
    catch (...) { return nullptr; }
}

AEGIS_API void aegis_destroy_pipeline(void* pipeline) {
    try { delete P(pipeline); } catch (...) {}
}

AEGIS_API int aegis_load_data(void* pipeline, const double* data, int rows, int cols) {
    if (!pipeline || !data) return -1;
    return guarded([&] { return P(pipeline)->load_data(data, rows, cols) ? 0 : -1; }, -1);
}

AEGIS_API int aegis_configure(void* pipeline, const char* json_config) {
    if (!pipeline || !json_config) return -1;
    return guarded([&] { return P(pipeline)->configure(std::string(json_config)) ? 0 : -1; }, -1);
}

AEGIS_API int aegis_start(void* pipeline) {
    if (!pipeline) return -1;
    return guarded([&] { return P(pipeline)->start() ? 0 : -1; }, -1);
}

AEGIS_API int aegis_pause(void* pipeline) {
    if (!pipeline) return -1;
    P(pipeline)->pause();
    return 0;
}

AEGIS_API int aegis_resume(void* pipeline) {
    if (!pipeline) return -1;
    P(pipeline)->resume();
    return 0;
}

AEGIS_API int aegis_stop(void* pipeline) {
    if (!pipeline) return -1;
    return guarded([&] { P(pipeline)->stop(); return 0; }, -1);
}

AEGIS_API int aegis_step(void* pipeline, int num_generations) {
    if (!pipeline) return -1;
    return guarded([&] { return P(pipeline)->step(num_generations); }, -1);
}

AEGIS_API char* aegis_get_status(void* pipeline) {
    if (!pipeline) return dup_string("{\"error\":\"null pipeline\"}");
    return dup_string(guarded([&] { return P(pipeline)->status_json(); }, std::string("{\"error\":\"exception\"}")));
}

AEGIS_API char* aegis_get_best_model(void* pipeline) {
    if (!pipeline) return dup_string("{\"error\":\"null pipeline\"}");
    return dup_string(guarded([&] { return P(pipeline)->best_model_json(); }, std::string("{\"error\":\"exception\"}")));
}

AEGIS_API char* aegis_get_snapshot(void* pipeline) {
    if (!pipeline) return dup_string("{\"error\":\"null pipeline\"}");
    return dup_string(guarded([&] { return P(pipeline)->snapshot_json(); }, std::string("{\"error\":\"exception\"}")));
}

AEGIS_API void aegis_free_string(char* ptr) {
    delete[] ptr;
}

AEGIS_API int aegis_apply_tuning(
    void* pipeline, const char* param_name, double new_value, const char* reason
) {
    if (!pipeline || !param_name) return -1;
    return guarded([&] {
        return P(pipeline)->apply_tuning(std::string(param_name), new_value,
                                         reason ? std::string(reason) : std::string(), "legacy");
    }, 1);
}

AEGIS_API char* aegis_apply_action(void* pipeline, const char* action_json) {
    if (!pipeline || !action_json) return dup_string("{\"error\":\"null argument\"}");
    return dup_string(guarded([&] { return P(pipeline)->apply_action_json(std::string(action_json)); },
                              std::string("{\"error\":\"exception\"}")));
}

AEGIS_API char* aegis_get_action_schema(void* pipeline) {
    if (!pipeline) return dup_string("{}");
    return dup_string(guarded([&] { return P(pipeline)->action_schema_json(); }, std::string("{}")));
}

AEGIS_API int aegis_set_agent_enabled(void* pipeline, int enabled) {
    if (!pipeline) return -1;
    P(pipeline)->set_agent_enabled(enabled != 0);
    return 0;
}

AEGIS_API int aegis_inject_individual(void* pipeline, const char* json) {
    if (!pipeline || !json) return -1;
    return guarded([&] { return P(pipeline)->inject_individual(std::string(json)) ? 0 : -1; }, -1);
}

AEGIS_API char* aegis_get_tuning_log(void* pipeline) {
    if (!pipeline) return dup_string("[]");
    return dup_string(guarded([&] { return P(pipeline)->tuning_log_json(); }, std::string("[]")));
}

AEGIS_API char* aegis_get_config(void* pipeline) {
    if (!pipeline) return dup_string("{}");
    return dup_string(guarded([&] { return P(pipeline)->config_json(); }, std::string("{}")));
}

AEGIS_API char* aegis_get_history(void* pipeline) {
    if (!pipeline) return dup_string("[]");
    return dup_string(guarded([&] { return P(pipeline)->history_json(); }, std::string("[]")));
}

AEGIS_API char* aegis_get_final_report(void* pipeline) {
    if (!pipeline) return dup_string("{\"status\":\"not_available\"}");
    return dup_string(guarded([&] { return P(pipeline)->final_report_json(); },
                              std::string("{\"error\":\"exception\"}")));
}

AEGIS_API char* aegis_get_last_error(void* pipeline) {
    if (!pipeline) return dup_string("null pipeline");
    return dup_string(guarded([&] { return P(pipeline)->last_error(); }, std::string("exception")));
}

AEGIS_API char* aegis_evaluate_model(void* pipeline, const char* model_json, int refit) {
    if (!pipeline || !model_json) return dup_string("{\"error\":\"null argument\"}");
    return dup_string(guarded([&] { return P(pipeline)->evaluate_model_json(std::string(model_json), refit != 0); },
                              std::string("{\"error\":\"exception\"}")));
}

AEGIS_API const char* aegis_build_info(void) {
    static const std::string info = build_info_json();
    return info.c_str();
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
    return "AEGIS C++ Core 1.1.0-audit";
}

} // extern "C"
