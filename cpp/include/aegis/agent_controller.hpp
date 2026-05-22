#pragma once
#include <string>
#include <vector>
#include <functional>
#include <thread>
#include <mutex>
#include <atomic>
#include <memory>

#ifdef __EMSCRIPTEN__
  using SocketFd = int;
  #define INVALID_SOCK (-1)
  #define SOCK_ERR     (-1)
#elif defined(_WIN32)
  #include <winsock2.h>
  #include <ws2tcpip.h>
  using SocketFd = SOCKET;
  #define INVALID_SOCK INVALID_SOCKET
  #define SOCK_ERR     SOCKET_ERROR
#else
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <unistd.h>
  using SocketFd = int;
  #define INVALID_SOCK (-1)
  #define SOCK_ERR     (-1)
#endif

namespace aegis {

/** JSON payload broadcast to connected agent clients each generation. */
struct AgentBroadcast {
    std::string json; // pre-serialized JSON
};

/** A suggestion received from an AI agent. */
struct AgentSuggestion {
    std::string param_name;
    double      proposed_value = 0.0;
    std::string reason;
};

/** Log entry for accepted/rejected tuning actions. */
struct TuningLogEntry {
    bool        accepted;
    std::string param_name;
    double      old_value;
    double      new_value;
    std::string reason;
    std::string rejection_reason;
    int         generation;
};

/**
 * WebSocket server (RFC 6455) for real-time bidirectional agent communication.
 *
 * Listens on localhost:port. Each connected client:
 *   - Receives JSON broadcast frames from the engine every generation.
 *   - Can send JSON suggestion frames (agent → engine).
 *
 * Multiple concurrent agents are supported (one thread per client).
 *
 * Thread safety: broadcast() and stop() are safe to call from any thread.
 */
class AgentController {
public:
    using SuggestionHandler = std::function<bool(const AgentSuggestion&, TuningLogEntry&)>;

    explicit AgentController(int port = 8765);
    ~AgentController();

    /** Start the accept loop in a background thread. Non-blocking. */
    bool start();

    /** Gracefully stop all connections and the accept loop. */
    void stop();

    /** Broadcast a JSON string to all connected clients. Returns client count. */
    int broadcast(const std::string& json);

    /** Broadcast a GenerationReport (serialized internally). */
    int broadcast_report(const std::string& json_payload);

    /** Register the callback invoked when an agent sends a suggestion.
     *  Return true to accept the suggestion, false to reject.
     *  The handler must fill in log_entry fields. */
    void on_suggestion(SuggestionHandler handler);

    int         client_count() const;
    int         port()         const { return port_; }
    bool        running()      const { return running_; }

    const std::vector<TuningLogEntry>& tuning_log() const { return log_; }

private:
    int                 port_;
    SocketFd            server_fd_ = INVALID_SOCK;
    std::atomic<bool>   running_{false};
    std::thread         accept_thread_;

    struct ClientConn;
    std::vector<std::shared_ptr<ClientConn>> clients_;
    mutable std::mutex clients_mutex_;

    SuggestionHandler   suggestion_handler_;
    std::vector<TuningLogEntry> log_;
    mutable std::mutex  log_mutex_;

    void accept_loop();
    void client_loop(std::shared_ptr<ClientConn> conn);
    bool do_handshake(SocketFd fd, std::string& client_key);
    void send_frame(SocketFd fd, const std::string& payload, uint8_t opcode = 0x01);
    bool recv_frame(SocketFd fd, std::string& payload, uint8_t& opcode);
    void remove_client(SocketFd fd);

    // RFC 6455 helpers (implemented in agent_controller.cpp)
    static std::string sha1_base64(const std::string& input);
    static std::string base64_encode(const unsigned char* data, size_t len);
    static void        sha1(const unsigned char* msg, size_t len, unsigned char out[20]);

    // JSON parsing (minimal, no external deps)
    static bool parse_suggestion(const std::string& json, AgentSuggestion& out);
};

/** Build the broadcast JSON payload from individual fields. */
std::string build_broadcast_json(
    int    generation,
    double best_fitness,
    double rmse_train,
    double rmse_val,
    double rmse_test,
    double bic,
    double aic,
    double population_diversity,
    int    stagnation,
    double mu_f,
    double mu_cr,
    int    num_terms,
    bool   is_stable,
    bool   overfitting,
    bool   underfitting,
    bool   pe_ok,
    const std::vector<double>& residual_autocorr,
    const std::vector<double>& best_coefficients,
    const std::vector<double>& best_exponents,
    const std::string& alerts
);

} // namespace aegis
