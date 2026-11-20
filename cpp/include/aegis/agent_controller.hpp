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
  #ifndef NOMINMAX
  #define NOMINMAX
  #endif
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

/**
 * WebSocket server (RFC 6455) for external agents, bound to 127.0.0.1.
 *
 *  - Clients receive JSON snapshots broadcast by the engine.
 *  - Text frames sent by a client are passed to the message handler, whose
 *    returned JSON string is sent back as the reply. The pipeline routes them
 *    through the same typed, validated action interface used by every agent.
 *  - Sends use a socket timeout: a slow or stalled client is disconnected and
 *    can never block the evolutionary engine.
 */
class AgentController {
public:
    using MessageHandler = std::function<std::string(const std::string& payload)>;

    explicit AgentController(int port = 8765);
    ~AgentController();

    bool start();
    void stop();

    /** Broadcast a JSON string to all connected clients. Returns clients reached. */
    int broadcast(const std::string& json);

    void on_message(MessageHandler handler);

    int  client_count() const;
    int  port()         const { return port_; }
    bool running()      const { return running_; }

    static constexpr int kSendTimeoutMs = 200;
    static constexpr size_t kMaxFrame = 64 * 1024;

private:
    int                 port_;
    SocketFd            server_fd_ = INVALID_SOCK;
    std::atomic<bool>   running_{false};
    std::thread         accept_thread_;

    struct ClientConn;
    std::vector<std::shared_ptr<ClientConn>> clients_;
    mutable std::mutex clients_mutex_;

    MessageHandler      handler_;
    std::mutex          handler_mutex_;

    void accept_loop();
    void client_loop(std::shared_ptr<ClientConn> conn);
    bool do_handshake(SocketFd fd);
    bool send_frame(SocketFd fd, const std::string& payload, uint8_t opcode = 0x01);
    bool recv_frame(SocketFd fd, std::string& payload, uint8_t& opcode);

    static std::string sha1_base64(const std::string& input);
    static std::string base64_encode(const unsigned char* data, size_t len);
    static void        sha1(const unsigned char* msg, size_t len, unsigned char out[20]);
};

} // namespace aegis
