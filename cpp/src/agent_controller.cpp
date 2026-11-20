#include "aegis/agent_controller.hpp"
#include <cctype>
#include <cstring>
#include <cstdint>
#include <sstream>
#include <algorithm>
#include <stdexcept>
#include <cmath>

#ifndef __EMSCRIPTEN__

#ifdef _WIN32
  #include <winsock2.h>
  #include <ws2tcpip.h>
  using ssize_t_aegis = int;
  static bool wsa_init() {
      WSADATA d; return WSAStartup(MAKEWORD(2,2), &d) == 0;
  }
  static void close_socket(SOCKET s) { closesocket(s); }
  static void shutdown_socket(SOCKET s) { shutdown(s, SD_BOTH); }
  static void set_timeouts(SOCKET s, int send_ms) {
      DWORD tv = static_cast<DWORD>(send_ms);
      setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&tv), sizeof(tv));
  }
#else
  #include <sys/socket.h>
  #include <sys/time.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <unistd.h>
  #include <fcntl.h>
  using ssize_t_aegis = ssize_t;
  static bool wsa_init() { return true; }
  static void close_socket(int s) { ::close(s); }
  static void shutdown_socket(int s) { ::shutdown(s, SHUT_RDWR); }
  static void set_timeouts(int s, int send_ms) {
      timeval tv{send_ms / 1000, (send_ms % 1000) * 1000};
      setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  }
#endif

namespace aegis {

// ─────────────────────────────────────────────────────────────────────────
// SHA-1 (RFC 3174) + Base64 — WebSocket handshake
// ─────────────────────────────────────────────────────────────────────────

void AgentController::sha1(const unsigned char* msg, size_t len, unsigned char out[20]) {
    uint32_t h0=0x67452301u, h1=0xEFCDAB89u, h2=0x98BADCFEu,
             h3=0x10325476u, h4=0xC3D2E1F0u;
    auto rot32 = [](uint32_t x, int n) -> uint32_t { return (x << n) | (x >> (32 - n)); };
    size_t ml  = len;
    size_t pad = 64 - ((ml + 9) % 64);
    if (pad == 64) pad = 0;
    size_t total = ml + 1 + pad + 8;
    std::vector<unsigned char> buf(total, 0);
    std::memcpy(buf.data(), msg, ml);
    buf[ml] = 0x80;
    uint64_t bits = static_cast<uint64_t>(ml) * 8;
    for (int i = 0; i < 8; ++i)
        buf[total - 8 + i] = static_cast<unsigned char>((bits >> (56 - 8 * i)) & 0xFF);
    for (size_t off = 0; off < total; off += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; ++i)
            w[i] = ((uint32_t)buf[off+i*4] << 24) | ((uint32_t)buf[off+i*4+1] << 16) |
                   ((uint32_t)buf[off+i*4+2] << 8) | ((uint32_t)buf[off+i*4+3]);
        for (int i = 16; i < 80; ++i) w[i] = rot32(w[i-3]^w[i-8]^w[i-14]^w[i-16], 1);
        uint32_t a=h0,b=h1,c=h2,d=h3,e=h4;
        for (int i = 0; i < 80; ++i) {
            uint32_t f,k;
            if      (i<20){f=(b&c)|((~b)&d); k=0x5A827999u;}
            else if (i<40){f=b^c^d;          k=0x6ED9EBA1u;}
            else if (i<60){f=(b&c)|(b&d)|(c&d);k=0x8F1BBCDCu;}
            else           {f=b^c^d;          k=0xCA62C1D6u;}
            uint32_t tmp=rot32(a,5)+f+e+k+w[i];
            e=d; d=c; c=rot32(b,30); b=a; a=tmp;
        }
        h0+=a; h1+=b; h2+=c; h3+=d; h4+=e;
    }
    auto wr=[&](int off, uint32_t v){
        out[off]=(v>>24)&0xFF; out[off+1]=(v>>16)&0xFF; out[off+2]=(v>>8)&0xFF; out[off+3]=v&0xFF;
    };
    wr(0,h0); wr(4,h1); wr(8,h2); wr(12,h3); wr(16,h4);
}

std::string AgentController::base64_encode(const unsigned char* data, size_t len) {
    static const char* tab = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve((len + 2) / 3 * 4);
    for (size_t i = 0; i < len; i += 3) {
        uint32_t b = (uint32_t)data[i] << 16;
        if (i+1<len) b |= (uint32_t)data[i+1] << 8;
        if (i+2<len) b |= data[i+2];
        out.push_back(tab[(b>>18)&0x3F]);
        out.push_back(tab[(b>>12)&0x3F]);
        out.push_back((i+1<len) ? tab[(b>>6)&0x3F] : '=');
        out.push_back((i+2<len) ? tab[b&0x3F]      : '=');
    }
    return out;
}

std::string AgentController::sha1_base64(const std::string& input) {
    unsigned char hash[20];
    sha1(reinterpret_cast<const unsigned char*>(input.c_str()), input.size(), hash);
    return base64_encode(hash, 20);
}

// ─────────────────────────────────────────────────────────────────────────
// Frames
// ─────────────────────────────────────────────────────────────────────────

static bool send_all(SocketFd fd, const char* data, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        const int r = send(fd, data + sent, static_cast<int>(len - sent), 0);
        if (r <= 0) return false; // error or send timeout → caller drops the client
        sent += static_cast<size_t>(r);
    }
    return true;
}

bool AgentController::send_frame(SocketFd fd, const std::string& payload, uint8_t opcode) {
    const size_t plen = payload.size();
    std::string frame;
    frame.reserve(plen + 10);
    frame.push_back(static_cast<char>(0x80u | opcode));
    if (plen < 126) {
        frame.push_back(static_cast<char>(plen));
    } else if (plen < 65536) {
        frame.push_back(static_cast<char>(126));
        frame.push_back(static_cast<char>((plen >> 8) & 0xFF));
        frame.push_back(static_cast<char>(plen & 0xFF));
    } else {
        frame.push_back(static_cast<char>(127));
        for (int i = 7; i >= 0; --i)
            frame.push_back(static_cast<char>((static_cast<uint64_t>(plen) >> (i * 8)) & 0xFF));
    }
    frame += payload;
    return send_all(fd, frame.data(), frame.size());
}

static bool recv_exactly(SocketFd fd, void* buf, size_t n) {
    size_t received = 0;
    while (received < n) {
        int r = recv(fd, reinterpret_cast<char*>(buf) + received, static_cast<int>(n - received), 0);
        if (r <= 0) return false;
        received += static_cast<size_t>(r);
    }
    return true;
}

bool AgentController::recv_frame(SocketFd fd, std::string& payload, uint8_t& opcode) {
    uint8_t h[2];
    if (!recv_exactly(fd, h, 2)) return false;
    opcode = h[0] & 0x0F;
    const bool masked = (h[1] & 0x80) != 0;
    uint64_t plen = h[1] & 0x7F;
    if (plen == 126) {
        uint8_t ext[2];
        if (!recv_exactly(fd, ext, 2)) return false;
        plen = (static_cast<uint64_t>(ext[0]) << 8) | ext[1];
    } else if (plen == 127) {
        uint8_t ext[8];
        if (!recv_exactly(fd, ext, 8)) return false;
        plen = 0;
        for (int i = 0; i < 8; ++i) plen = (plen << 8) | ext[i];
    }
    uint8_t mask[4] = {};
    if (masked && !recv_exactly(fd, mask, 4)) return false;
    if (plen > kMaxFrame) return false;
    std::string data(static_cast<size_t>(plen), '\0');
    if (plen > 0 && !recv_exactly(fd, &data[0], static_cast<size_t>(plen))) return false;
    if (masked)
        for (size_t i = 0; i < plen; ++i) data[i] = static_cast<char>(data[i] ^ mask[i & 3]);
    payload = std::move(data);
    return true;
}

bool AgentController::do_handshake(SocketFd fd) {
    std::string req;
    char buf[2048];
    while (req.size() < 16384) {
        int r = recv(fd, buf, sizeof(buf), 0);
        if (r <= 0) return false;
        req.append(buf, static_cast<size_t>(r));
        if (req.find("\r\n\r\n") != std::string::npos) break;
    }
    std::string lower = req;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    auto pos = lower.find("sec-websocket-key:");
    if (pos == std::string::npos) return false;
    pos += 18;
    while (pos < req.size() && req[pos] == ' ') ++pos;
    auto end = req.find("\r\n", pos);
    if (end == std::string::npos) return false;
    const std::string key = req.substr(pos, end - pos);
    const std::string accept = sha1_base64(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    const std::string resp =
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: " + accept + "\r\n\r\n";
    return send_all(fd, resp.c_str(), resp.size());
}

// ─────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────

struct AgentController::ClientConn {
    SocketFd fd;
    std::atomic<bool> active{true};
    std::thread thread;
    std::mutex send_mutex;
    explicit ClientConn(SocketFd f) : fd(f) {}
};

AgentController::AgentController(int port) : port_(port) { wsa_init(); }

AgentController::~AgentController() { stop(); }

bool AgentController::start() {
    if (running_.load()) return true;
    server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd_ == INVALID_SOCK) return false;
    int opt = 1;
    setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&opt), sizeof(opt));
    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(static_cast<uint16_t>(port_));
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0 ||
        listen(server_fd_, 8) < 0) {
        close_socket(server_fd_);
        server_fd_ = INVALID_SOCK;
        return false;
    }
    running_.store(true);
    accept_thread_ = std::thread([this]{ accept_loop(); });
    return true;
}

void AgentController::stop() {
    if (!running_.exchange(false) && server_fd_ == INVALID_SOCK) return;
    if (server_fd_ != INVALID_SOCK) {
        shutdown_socket(server_fd_);
        close_socket(server_fd_);
        server_fd_ = INVALID_SOCK;
    }
    if (accept_thread_.joinable()) accept_thread_.join();
    std::vector<std::shared_ptr<ClientConn>> clients;
    {
        std::lock_guard<std::mutex> lk(clients_mutex_);
        clients.swap(clients_);
    }
    for (auto& c : clients) {
        c->active.store(false);
        shutdown_socket(c->fd);   // unblocks recv in the client thread
    }
    for (auto& c : clients) {
        if (c->thread.joinable()) c->thread.join();
        close_socket(c->fd);
    }
}

void AgentController::accept_loop() {
    while (running_.load()) {
        sockaddr_in client_addr{};
        socklen_t len = sizeof(client_addr);
        SocketFd cfd = accept(server_fd_, reinterpret_cast<sockaddr*>(&client_addr), &len);
        if (cfd == INVALID_SOCK) {
            if (!running_.load()) break;
            continue;
        }
        set_timeouts(cfd, kSendTimeoutMs);
        auto conn = std::make_shared<ClientConn>(cfd);
        std::lock_guard<std::mutex> lk(clients_mutex_);
        if (!running_.load()) { close_socket(cfd); break; }
        // Reap finished connections.
        for (auto it = clients_.begin(); it != clients_.end();) {
            if (!(*it)->active.load()) {
                if ((*it)->thread.joinable()) (*it)->thread.join();
                close_socket((*it)->fd);
                it = clients_.erase(it);
            } else {
                ++it;
            }
        }
        conn->thread = std::thread([this, conn]{ client_loop(conn); });
        clients_.push_back(conn);
    }
}

void AgentController::client_loop(std::shared_ptr<ClientConn> conn) {
    if (!do_handshake(conn->fd)) { conn->active.store(false); return; }
    while (conn->active.load() && running_.load()) {
        std::string payload;
        uint8_t opcode;
        if (!recv_frame(conn->fd, payload, opcode)) break;
        if (opcode == 0x08) break;
        if (opcode == 0x09) {
            std::lock_guard<std::mutex> lk(conn->send_mutex);
            if (!send_frame(conn->fd, payload, 0x0A)) break;
            continue;
        }
        if (opcode == 0x01 || opcode == 0x02) {
            std::string reply;
            {
                std::lock_guard<std::mutex> lk(handler_mutex_);
                if (handler_) reply = handler_(payload);
            }
            if (reply.empty()) reply = "{\"status\":\"ignored\",\"message\":\"no handler\"}";
            std::lock_guard<std::mutex> lk(conn->send_mutex);
            if (!send_frame(conn->fd, reply)) break;
        }
    }
    conn->active.store(false);
}

int AgentController::broadcast(const std::string& json) {
    std::vector<std::shared_ptr<ClientConn>> clients;
    {
        std::lock_guard<std::mutex> lk(clients_mutex_);
        clients = clients_;
    }
    int sent = 0;
    for (auto& conn : clients) {
        if (!conn->active.load()) continue;
        std::unique_lock<std::mutex> lk(conn->send_mutex, std::try_to_lock);
        if (!lk.owns_lock()) continue; // a reply is being sent; skip this snapshot
        if (send_frame(conn->fd, json)) {
            ++sent;
        } else {
            conn->active.store(false);  // slow/broken client: disconnect
            shutdown_socket(conn->fd);
        }
    }
    return sent;
}

void AgentController::on_message(MessageHandler handler) {
    std::lock_guard<std::mutex> lk(handler_mutex_);
    handler_ = std::move(handler);
}

int AgentController::client_count() const {
    std::lock_guard<std::mutex> lk(clients_mutex_);
    int n = 0;
    for (const auto& c : clients_) if (c->active.load()) ++n;
    return n;
}

} // namespace aegis

#else // __EMSCRIPTEN__ — no sockets/threads in WASM

namespace aegis {
struct AgentController::ClientConn {};
AgentController::AgentController(int port) : port_(port) {}
AgentController::~AgentController() {}
bool AgentController::start()                       { return false; }
void AgentController::stop()                        {}
int  AgentController::broadcast(const std::string&) { return 0; }
void AgentController::on_message(MessageHandler)    {}
int  AgentController::client_count() const          { return 0; }
} // namespace aegis

#endif // !__EMSCRIPTEN__
