// AEGIS C API integration tests: lifecycle, action interface, interruption,
// async mode and the WebSocket agent channel (including a disconnecting and
// a stalled client).

#include "aegis/aegis_api.h"
#include "aegis/json_lite.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#  ifndef NOMINMAX
#  define NOMINMAX
#  endif
#  include <winsock2.h>
#  include <ws2tcpip.h>
using sock_t = SOCKET;
static void sclose(sock_t s) { closesocket(s); }
#else
#  include <arpa/inet.h>
#  include <netinet/in.h>
#  include <sys/socket.h>
#  include <unistd.h>
using sock_t = int;
static void sclose(sock_t s) { close(s); }
#endif

using aegis::json::Value;

namespace {

int g_checks = 0, g_fail = 0;
bool expect(bool c, const char* m) {
    ++g_checks;
    if (!c) { std::fprintf(stderr, "  FAIL: %s\n", m); ++g_fail; }
    return c;
}
std::string take(char* p) { std::string s = p ? p : ""; aegis_free_string(p); return s; }
Value parse(const std::string& s) { Value v; aegis::json::parse(s, v); return v; }

std::vector<double> make_data(int n, unsigned seed) {
    std::mt19937 g(seed);
    std::uniform_real_distribution<double> ud(-1.0, 1.0);
    std::vector<double> d(static_cast<size_t>(n) * 2);
    double y1 = 0.0, y2 = 0.0, u1 = 0.0;
    for (int k = 0; k < n; ++k) {
        const double u = 0.7 * std::sin(0.05 * k) + 0.3 * ud(g);
        const double y = 0.6 * y1 - 0.1 * y2 + 0.5 * std::tanh(1.5 * u1);
        d[2 * k] = u; d[2 * k + 1] = y;
        y2 = y1; y1 = y; u1 = u;
    }
    return d;
}

void* make_pipeline(const std::vector<double>& d, int rows, const std::string& cfg) {
    void* p = aegis_create_pipeline();
    aegis_load_data(p, d.data(), rows, 2);
    if (aegis_configure(p, cfg.c_str()) != 0) {
        std::fprintf(stderr, "configure failed: %s\n", take(aegis_get_last_error(p)).c_str());
    }
    return p;
}

const char* kSmall = "{\"numIslands\":2,\"populationSize\":12,\"maxRegressors\":5,\"maxDelay\":5,"
                     "\"maxGenerations\":30,\"randomSeed\":11,\"syncMode\":true,\"numThreads\":1}";

void test_configuration() {
    std::puts("[configuration]");
    void* p = aegis_create_pipeline();
    expect(aegis_configure(p, "{}") == -1, "configure before load_data fails");
    expect(!take(aegis_get_last_error(p)).empty(), "error message reported");
    auto d = make_data(400, 1);
    aegis_load_data(p, d.data(), 400, 2);
    expect(aegis_configure(p, "{bad json") == -1, "invalid JSON rejected");
    expect(aegis_configure(p, "{\"trainRatio\":0.9,\"validationRatio\":0.2}") == -1, "invalid split rejected");
    expect(aegis_configure(p, "{\"numIslands\":2,\"fooBar\":1}") == 0, "unknown keys accepted");
    expect(take(aegis_get_last_error(p)).find("fooBar") != std::string::npos, "unknown key reported as warning");
    Value cfg = parse(take(aegis_get_config(p)));
    expect(cfg.number_or("randomSeed", 0) > 0, "effective seed recorded when none given");
    expect(cfg.string_or("powerMode", "") == "hybrid", "default power mode is hybrid");
    double bad[2] = {1.0, NAN};
    expect(aegis_load_data(p, bad, 1, 2) != 0, "non-finite data rejected");
    aegis_destroy_pipeline(p);
}

void test_sync_run_and_reproducibility() {
    std::puts("[sync run / reproducibility]");
    auto d = make_data(500, 2);
    void* a = make_pipeline(d, 500, kSmall);
    void* b = make_pipeline(d, 500, kSmall);
    expect(aegis_start(a) == 0 && aegis_start(b) == 0, "start");
    expect(parse(take(aegis_get_best_model(a))).has("status") ||
           !std::isfinite(parse(take(aegis_get_best_model(a))).number_or("rmseTest", NAN)),
           "no test metric before the run");
    aegis_step(a, 5);
    Value mid = parse(take(aegis_get_best_model(a)));
    expect(mid.get("rmseTest") && mid.get("rmseTest")->is_null(), "rmseTest is null during the run (P0-7)");
    expect(parse(take(aegis_get_snapshot(a))).get("rmse_test")->is_null(), "snapshot never carries test metrics");
    while (aegis_step(a, 10) > 0) {}
    while (aegis_step(b, 7) > 0) {}
    Value st = parse(take(aegis_get_status(a)));
    expect(st.string_or("state", "") == "completed", "state completed");
    Value ra = parse(take(aegis_get_final_report(a)));
    Value rb = parse(take(aegis_get_final_report(b)));
    expect(ra.string_or("stopReason", "") == "max_generations", "stop reason recorded");
    expect(ra.get("metrics") && ra.get("metrics")->get("test") && ra.get("metrics")->get("validation"),
           "final report has train/validation/test metrics");
    expect(std::isfinite(ra.get("metrics")->get("test")->number_or("rmseFreeRunOrig", NAN)),
           "free-run test RMSE in original units");
    expect(ra.get("model")->dump() == rb.get("model")->dump(), "same seed + different step sizes → identical model");
    expect(parse(take(aegis_get_history(a))).items().size() == 30, "history has one record per generation");
    Value bm = parse(take(aegis_get_best_model(a)));
    expect(bm.bool_or("testEvaluated", false) && std::isfinite(bm.number_or("rmseTestFreeRun", NAN)),
           "test metrics exposed after completion");

    // Restart on the same handle.
    expect(aegis_start(a) == 0, "restart after completion");
    while (aegis_step(a, 10) > 0) {}
    Value ra2 = parse(take(aegis_get_final_report(a)));
    expect(ra2.get("model")->dump() == ra.get("model")->dump(), "restart with the same seed reproduces the run");
    aegis_destroy_pipeline(a);
    aegis_destroy_pipeline(b);

    // Different seed → (almost surely) different trajectory.
    std::string other = kSmall;
    other.replace(other.find("\"randomSeed\":11"), 15, "\"randomSeed\":12");
    void* c = make_pipeline(d, 500, other);
    aegis_start(c);
    while (aegis_step(c, 10) > 0) {}
    Value rc = parse(take(aegis_get_history(c)));
    void* e = make_pipeline(d, 500, kSmall);
    aegis_start(e);
    while (aegis_step(e, 10) > 0) {}
    Value re = parse(take(aegis_get_history(e)));
    expect(rc.dump() != re.dump(), "different seeds give different histories");
    aegis_destroy_pipeline(c);
    aegis_destroy_pipeline(e);
}

void test_actions() {
    std::puts("[actions]");
    auto d = make_data(500, 3);
    void* p = make_pipeline(d, 500, kSmall);
    expect(aegis_apply_tuning(p, "mutationFactor", 0.6, "before start") == 1, "actions rejected before start");
    aegis_start(p);
    aegis_step(p, 2);
    Value schema = parse(take(aegis_get_action_schema(p)));
    expect(schema.get("parameters") && schema.get("parameters")->items().size() >= 10, "schema published");
    expect(aegis_apply_tuning(p, "notAParam", 1.0, "x") == -1, "unknown parameter → -1");
    auto act = [&](const std::string& j) {
        Value r = parse(take(aegis_apply_action(p, j.c_str())));
        return r.get("results")->items()[0];
    };
    expect(act("{\"param\":\"mutationFactor\",\"value\":5}").string_or("code", "") == "out_of_range", "out of range");
    expect(act("{\"param\":\"mutationFactor\",\"value\":0.95}").string_or("code", "") == "step_too_large", "step too large");
    expect(act("{\"param\":\"stagnationLimit\",\"value\":600}").string_or("code", "") == "budget_locked", "budget locked");
    expect(act("{\"param\":\"crossoverRate\",\"value\":\"x\"}").string_or("code", "") == "invalid_value", "non-numeric value");
    Value ok = act("{\"param\":\"mutationFactor\",\"value\":0.6,\"reason\":\"say \\\"hi\\\"\",\"source\":\"test\"}");
    expect(ok.bool_or("accepted", false), "valid action accepted");
    expect(std::abs(ok.number_or("oldValue", 0) - 0.5) < 1e-12, "old value recorded");
    expect(act("{\"param\":\"mutationFactor\",\"value\":0.7}").string_or("code", "") == "cooldown", "cooldown enforced");
    expect(act("{\"param\":\"complexityPenalty\",\"value\":0.05,\"source\":\"test\"}").bool_or("accepted", false),
           "weight action accepted");
    aegis_step(p, 1);
    Value log = parse(take(aegis_get_tuning_log(p)));
    bool applied = false;
    for (const auto& r : log.items())
        if (r.string_or("param", "") == "complexityPenalty" && r.int_or("generationApplied", -1) >= 0) {
            applied = true;
            expect(std::abs(r.number_or("effectiveValue", 0) - 0.05) < 1e-12, "effective canonical gamma = 0.05");
        }
    expect(applied, "accepted action applied at the next generation");
    Value snap = parse(take(aegis_get_snapshot(p)));
    expect(std::abs(snap.get("parameters")->number_or("mutationFactor", 0) - 0.6) < 1e-12, "snapshot reflects new F");
    aegis_set_agent_enabled(p, 0);
    expect(act("{\"param\":\"crossoverRate\",\"value\":0.8}").string_or("code", "") == "agent_disabled", "kill switch");
    aegis_set_agent_enabled(p, 1);
    Value legacy = parse(take(aegis_apply_action(p, "{\"proposed_changes\":{\"migrationRate\":0.2,\"crossoverRate\":0.8},\"reason\":\"legacy\"}")));
    expect(legacy.get("results")->items().size() == 2, "legacy multi-parameter format");
    expect(parse(take(aegis_apply_action(p, "not json"))).get("results")->items()[0].string_or("code", "") == "invalid_json",
           "malformed action rejected and logged");
    // Outcomes are resolved after outcomeHorizon generations (or marked at run end).
    while (aegis_step(p, 10) > 0) {}
    Value fin = parse(take(aegis_get_final_report(p)));
    bool resolved = true;
    for (const auto& r : fin.get("actions")->items())
        if (r.bool_or("accepted", false)) resolved &= r.bool_or("resolved", false);
    expect(resolved, "all accepted actions resolved in the final report");
    expect(fin.get("agent")->int_or("rejected", 0) >= 6, "rejections counted");
    aegis_destroy_pipeline(p);
}

void test_interruption() {
    std::puts("[interruption / recovery]");
    auto d = make_data(500, 4);
    void* p = make_pipeline(d, 500, kSmall);
    aegis_start(p);
    aegis_step(p, 6);
    aegis_pause(p);
    expect(aegis_step(p, 5) == 0, "paused pipeline does not advance");
    aegis_resume(p);
    expect(aegis_step(p, 2) == 2, "resumed pipeline advances");
    aegis_stop(p);
    Value st = parse(take(aegis_get_status(p)));
    expect(st.string_or("state", "") == "stopped", "stopped state");
    Value fr = parse(take(aegis_get_final_report(p)));
    expect(fr.string_or("stopReason", "") == "stopped" && fr.get("metrics")->has("test"),
           "interrupted run still yields a complete final report");
    expect(fr.int_or("generations", 0) == 8, "generations up to the interruption recorded");
    aegis_destroy_pipeline(p);
}

void test_async_and_destroy() {
    std::puts("[async mode]");
    auto d = make_data(500, 5);
    void* p = make_pipeline(d, 500,
        "{\"numIslands\":2,\"populationSize\":12,\"maxRegressors\":5,\"maxDelay\":5,"
        "\"maxGenerations\":100000,\"stagnationLimit\":100000,\"randomSeed\":3}");
    expect(aegis_start(p) == 0, "async start");
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    expect(aegis_step(p, 5) == 0, "aegis_step is a no-op in async mode");
    const int g1 = parse(take(aegis_get_status(p))).int_or("generation", 0);
    aegis_pause(p);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    const int g2 = parse(take(aegis_get_status(p))).int_or("generation", 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    const int g3 = parse(take(aegis_get_status(p))).int_or("generation", 0);
    expect(g1 > 0 && g2 == g3, "async run advances and pause holds");
    Value r = parse(take(aegis_apply_action(p, "{\"param\":\"migrationRate\",\"value\":0.2}")));
    expect(r.get("results")->items()[0].bool_or("accepted", false), "action accepted while paused");
    aegis_resume(p);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    aegis_stop(p);
    expect(parse(take(aegis_get_final_report(p))).string_or("stopReason", "") == "stopped", "async stop finalises");
    aegis_destroy_pipeline(p);

    // Destroying a running pipeline must be safe.
    void* q = make_pipeline(d, 500, "{\"numIslands\":2,\"populationSize\":12,\"maxGenerations\":100000,\"randomSeed\":4}");
    aegis_start(q);
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    aegis_destroy_pipeline(q);
    expect(true, "destroy while running did not crash");
}

// ── Minimal WebSocket client ───────────────────────────────────────────────

sock_t ws_connect(int port) {
    sock_t s = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_port = htons(static_cast<uint16_t>(port));
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(s, reinterpret_cast<sockaddr*>(&a), sizeof(a)) != 0) { sclose(s); return static_cast<sock_t>(-1); }
    const std::string req =
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
    send(s, req.c_str(), static_cast<int>(req.size()), 0);
    std::string resp;
    char buf[512];
    while (resp.find("\r\n\r\n") == std::string::npos) {
        int r = recv(s, buf, sizeof(buf), 0);
        if (r <= 0) break;
        resp.append(buf, static_cast<size_t>(r));
    }
    expect(resp.find("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=") != std::string::npos, "RFC 6455 accept key");
    return s;
}

void ws_send_text(sock_t s, const std::string& payload) {
    std::string f;
    f.push_back(static_cast<char>(0x81));
    const unsigned char mask[4] = {1, 2, 3, 4};
    if (payload.size() < 126) f.push_back(static_cast<char>(0x80 | payload.size()));
    else { f.push_back(static_cast<char>(0x80 | 126)); f.push_back(static_cast<char>(payload.size() >> 8)); f.push_back(static_cast<char>(payload.size() & 0xFF)); }
    f.append(reinterpret_cast<const char*>(mask), 4);
    for (size_t i = 0; i < payload.size(); ++i) f.push_back(static_cast<char>(payload[i] ^ mask[i & 3]));
    send(s, f.data(), static_cast<int>(f.size()), 0);
}

bool recv_n(sock_t s, char* b, size_t n) {
    size_t got = 0;
    while (got < n) { int r = recv(s, b + got, static_cast<int>(n - got), 0); if (r <= 0) return false; got += r; }
    return true;
}

std::string ws_recv(sock_t s) {
    unsigned char h[2];
    if (!recv_n(s, reinterpret_cast<char*>(h), 2)) return "";
    uint64_t len = h[1] & 0x7F;
    if (len == 126) { unsigned char e[2]; recv_n(s, reinterpret_cast<char*>(e), 2); len = (e[0] << 8) | e[1]; }
    else if (len == 127) { unsigned char e[8]; recv_n(s, reinterpret_cast<char*>(e), 8); len = 0; for (int i = 0; i < 8; ++i) len = (len << 8) | e[i]; }
    std::string p(static_cast<size_t>(len), '\0');
    if (len) recv_n(s, &p[0], static_cast<size_t>(len));
    return p;
}

void test_websocket() {
    std::puts("[websocket]");
#ifdef _WIN32
    WSADATA w; WSAStartup(MAKEWORD(2, 2), &w);
#endif
    auto d = make_data(500, 6);
    void* p = make_pipeline(d, 500,
        "{\"numIslands\":2,\"populationSize\":12,\"maxRegressors\":5,\"maxDelay\":5,"
        "\"maxGenerations\":100000,\"stagnationLimit\":100000,\"randomSeed\":5,\"webSocketPort\":18765}");
    aegis_start(p);
    sock_t s = ws_connect(18765);
    expect(s != static_cast<sock_t>(-1), "client connected");
    // Receive at least one snapshot broadcast.
    std::string msg = ws_recv(s);
    expect(parse(msg).string_or("schema", "") == "aegis.snapshot/2", "snapshot broadcast received");
    ws_send_text(s, "{\"param\":\"crossoverRate\",\"value\":0.8,\"reason\":\"ws test\",\"source\":\"ws-test\"}");
    bool got_reply = false;
    for (int i = 0; i < 200 && !got_reply; ++i) {
        Value v = parse(ws_recv(s));
        if (v.has("results")) {
            got_reply = true;
            expect(v.get("results")->items()[0].bool_or("accepted", false), "action via WebSocket accepted");
        }
    }
    expect(got_reply, "reply to the action received");
    sclose(s); // abrupt disconnect
    const int g1 = parse(take(aegis_get_status(p))).int_or("generation", 0);
    // Stalled client: connects, handshakes and never reads.
    sock_t stalled = ws_connect(18765);
    std::this_thread::sleep_for(std::chrono::milliseconds(1500));
    const int g2 = parse(take(aegis_get_status(p))).int_or("generation", 0);
    expect(g2 > g1 + 3, "engine keeps running after a disconnect and with a stalled client");
    Value log = parse(take(aegis_get_tuning_log(p)));
    bool logged = false;
    for (const auto& r : log.items()) logged |= r.string_or("source", "") == "ws-test";
    expect(logged, "WebSocket action recorded in the pipeline log");
    aegis_stop(p);
    sclose(stalled);
    aegis_destroy_pipeline(p);
}

void test_evaluate_model() {
    std::puts("[evaluate model]");
    auto d = make_data(600, 7);
    void* p = make_pipeline(d, 600, "{\"maxDelay\":3,\"syncMode\":true}");
    const std::string model =
        "{\"powerMode\":\"hybrid\",\"regressors\":[{\"terms\":[{\"variable\":1,\"delay\":1,\"exponent\":1}]},"
        "{\"terms\":[{\"variable\":1,\"delay\":2,\"exponent\":1}]},{\"terms\":[{\"variable\":0,\"delay\":1,\"exponent\":1}]},"
        "{\"terms\":[{\"variable\":0,\"delay\":1,\"exponent\":3}]}]}";
    Value r = parse(take(aegis_evaluate_model(p, model.c_str(), 1)));
    expect(!r.has("error") && r.get("metrics") && r.get("metrics")->has("test"), "external model evaluated on all splits");
    const double fr = r.get("metrics")->get("test")->number_or("rmseFreeRun", NAN);
    const double os = r.get("metrics")->get("test")->number_or("rmseOneStep", NAN);
    expect(std::isfinite(fr) && std::isfinite(os) && os <= fr + 1e-12, "one-step error ≤ free-run error for this model");
    Value bad = parse(take(aegis_evaluate_model(p, "{\"regressors\":[{\"terms\":[{\"variable\":9,\"delay\":1}]}]}", 1)));
    expect(bad.has("error"), "invalid variable index rejected");
    aegis_destroy_pipeline(p);
}

void test_curriculum_off() {
    std::puts("[curriculum off]");
    auto d = make_data(400, 8);
    void* p = make_pipeline(d, 400,
        "{\"numIslands\":1,\"populationSize\":10,\"maxGenerations\":5,\"syncMode\":true,\"curriculum\":false,"
        "\"islandRoles\":false,\"islandRegimes\":false,\"randomSeed\":9}");
    aegis_start(p);
    while (aegis_step(p, 5) > 0) {}
    Value st = parse(take(aegis_get_status(p)));
    expect(st.int_or("phase", 0) == -1, "curriculum disabled → phase -1");
    Value fr = parse(take(aegis_get_final_report(p)));
    int reflex = 0;
    for (const auto& a : fr.get("actions")->items()) reflex += a.string_or("source", "") == "reflex";
    expect(reflex == 0, "no reflex actions without curriculum");
    aegis_destroy_pipeline(p);
}

} // namespace

int main() {
    std::printf("build: %s\n", aegis_build_info());
    test_configuration();
    test_sync_run_and_reproducibility();
    test_actions();
    test_interruption();
    test_async_and_destroy();
    test_websocket();
    test_evaluate_model();
    test_curriculum_off();
    std::printf("%d checks, %d failures\n", g_checks, g_fail);
    if (g_fail == 0) std::puts("All C API tests passed.");
    return g_fail == 0 ? 0 : 1;
}
