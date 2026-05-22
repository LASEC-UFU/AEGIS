#include "aegis/agent_controller.hpp"
#include <cstring>
#include <cstdint>
#include <sstream>
#include <algorithm>
#include <stdexcept>

#ifdef _WIN32
  #pragma comment(lib, "ws2_32.lib")
  #include <winsock2.h>
  #include <ws2tcpip.h>
  static bool wsa_init() {
      WSADATA d; return WSAStartup(MAKEWORD(2,2), &d) == 0;
  }
  static void close_socket(SOCKET s) { closesocket(s); }
#else
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <unistd.h>
  #include <fcntl.h>
  static bool wsa_init() { return true; }
  static void close_socket(int s) { ::close(s); }
#endif

namespace aegis {

// ─────────────────────────────────────────────────────────────────────────
// SHA-1 (RFC 3174) — needed for WebSocket handshake
// ─────────────────────────────────────────────────────────────────────────

void AgentController::sha1(const unsigned char* msg, size_t len, unsigned char out[20]) {
    uint32_t h0=0x67452301u, h1=0xEFCDAB89u, h2=0x98BADCFEu,
             h3=0x10325476u, h4=0xC3D2E1F0u;

    auto rot32 = [](uint32_t x, int n) -> uint32_t {
        return (x << n) | (x >> (32 - n));
    };

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
        for (int i = 0; i < 16; ++i) {
            w[i] = ((uint32_t)buf[off+i*4]   << 24) |
                   ((uint32_t)buf[off+i*4+1] << 16) |
                   ((uint32_t)buf[off+i*4+2] <<  8) |
                   ((uint32_t)buf[off+i*4+3]);
        }
        for (int i = 16; i < 80; ++i)
            w[i] = rot32(w[i-3]^w[i-8]^w[i-14]^w[i-16], 1);

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
        out[off  ]=(v>>24)&0xFF; out[off+1]=(v>>16)&0xFF;
        out[off+2]=(v>>8)&0xFF;  out[off+3]=v&0xFF;
    };
    wr(0,h0); wr(4,h1); wr(8,h2); wr(12,h3); wr(16,h4);
}

// ─────────────────────────────────────────────────────────────────────────
// Base64 encode
// ─────────────────────────────────────────────────────────────────────────

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
// WebSocket frame helpers
// ─────────────────────────────────────────────────────────────────────────

void AgentController::send_frame(SocketFd fd, const std::string& payload, uint8_t opcode) {
    // Server sends unmasked frames (RFC 6455 §5.1)
    size_t plen = payload.size();
    std::vector<uint8_t> header;

    header.push_back(0x80u | opcode); // FIN + opcode
    if (plen < 126) {
        header.push_back(static_cast<uint8_t>(plen));
    } else if (plen < 65536) {
        header.push_back(126);
        header.push_back(static_cast<uint8_t>((plen >> 8) & 0xFF));
        header.push_back(static_cast<uint8_t>(plen & 0xFF));
    } else {
        header.push_back(127);
        for (int i = 7; i >= 0; --i)
            header.push_back(static_cast<uint8_t>((plen >> (i * 8)) & 0xFF));
    }

    // Send header + payload
    send(fd, reinterpret_cast<const char*>(header.data()), (int)header.size(), 0);
    if (!payload.empty())
        send(fd, payload.c_str(), (int)plen, 0);
}

static ssize_t recv_exactly(SocketFd fd, void* buf, size_t n) {
    size_t received = 0;
    while (received < n) {
        int r = recv(fd, reinterpret_cast<char*>(buf) + received, (int)(n - received), 0);
        if (r <= 0) return -1;
        received += r;
    }
    return (ssize_t)n;
}

bool AgentController::recv_frame(SocketFd fd, std::string& payload, uint8_t& opcode) {
    uint8_t h[2];
    if (recv_exactly(fd, h, 2) < 0) return false;

    opcode = h[0] & 0x0F;
    bool masked = (h[1] & 0x80) != 0;
    uint64_t plen = h[1] & 0x7F;

    if (plen == 126) {
        uint8_t ext[2];
        if (recv_exactly(fd, ext, 2) < 0) return false;
        plen = ((uint64_t)ext[0] << 8) | ext[1];
    } else if (plen == 127) {
        uint8_t ext[8];
        if (recv_exactly(fd, ext, 8) < 0) return false;
        plen = 0;
        for (int i = 0; i < 8; ++i) plen = (plen << 8) | ext[i];
    }

    uint8_t mask[4] = {};
    if (masked) { if (recv_exactly(fd, mask, 4) < 0) return false; }

    if (plen > 64 * 1024) return false; // guard
    std::vector<uint8_t> data(plen);
    if (plen > 0 && recv_exactly(fd, data.data(), plen) < 0) return false;
    if (masked)
        for (size_t i = 0; i < plen; ++i) data[i] ^= mask[i & 3];

    payload.assign(reinterpret_cast<char*>(data.data()), plen);
    return true;
}

// ─────────────────────────────────────────────────────────────────────────
// HTTP upgrade handshake
// ─────────────────────────────────────────────────────────────────────────

bool AgentController::do_handshake(SocketFd fd, std::string& /*client_key*/) {
    // Read HTTP request
    std::string req;
    char buf[4096];
    while (true) {
        int r = recv(fd, buf, sizeof(buf) - 1, 0);
        if (r <= 0) return false;
        buf[r] = '\0';
        req += buf;
        if (req.find("\r\n\r\n") != std::string::npos) break;
    }

    // Extract Sec-WebSocket-Key
    auto pos = req.find("Sec-WebSocket-Key:");
    if (pos == std::string::npos) return false;
    pos += 18;
    while (pos < req.size() && req[pos] == ' ') ++pos;
    auto end = req.find("\r\n", pos);
    if (end == std::string::npos) return false;
    std::string key = req.substr(pos, end - pos);

    // Compute accept key
    std::string magic = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    std::string accept = sha1_base64(magic);

    // Send HTTP 101 response
    std::string resp =
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: " + accept + "\r\n\r\n";
    send(fd, resp.c_str(), (int)resp.size(), 0);
    return true;
}

// ─────────────────────────────────────────────────────────────────────────
// JSON suggestion parser (minimal, no external deps)
// ─────────────────────────────────────────────────────────────────────────

bool AgentController::parse_suggestion(const std::string& json, AgentSuggestion& out) {
    // Expect: {"proposed_changes":{"paramName":value,...},"reason":"..."}
    auto extract_str = [&](const std::string& key) -> std::string {
        auto p = json.find("\"" + key + "\"");
        if (p == std::string::npos) return "";
        p = json.find(':', p);
        if (p == std::string::npos) return "";
        ++p;
        while (p < json.size() && (json[p]==' '||json[p]=='\t')) ++p;
        if (json[p] == '"') {
            ++p;
            auto e = json.find('"', p);
            return e != std::string::npos ? json.substr(p, e - p) : "";
        }
        return "";
    };

    // Check for proposed_changes
    auto pc_pos = json.find("\"proposed_changes\"");
    if (pc_pos == std::string::npos) return false;
    auto brace = json.find('{', pc_pos + 18);
    if (brace == std::string::npos) return false;
    auto close = json.find('}', brace + 1);
    if (close == std::string::npos) return false;
    std::string inner = json.substr(brace + 1, close - brace - 1);

    // Find first key:value in inner
    auto kp = inner.find('"');
    if (kp == std::string::npos) return false;
    auto ke = inner.find('"', kp + 1);
    if (ke == std::string::npos) return false;
    out.param_name = inner.substr(kp + 1, ke - kp - 1);

    auto vp = inner.find(':', ke);
    if (vp == std::string::npos) return false;
    ++vp;
    while (vp < inner.size() && inner[vp] == ' ') ++vp;
    try { out.proposed_value = std::stod(inner.substr(vp)); }
    catch (...) { return false; }

    out.reason = extract_str("reason");
    return !out.param_name.empty();
}

// ─────────────────────────────────────────────────────────────────────────
// ClientConn
// ─────────────────────────────────────────────────────────────────────────

struct AgentController::ClientConn {
    SocketFd fd;
    std::atomic<bool> active{true};
    std::thread thread;
    ClientConn(SocketFd f) : fd(f) {}
};

// ─────────────────────────────────────────────────────────────────────────
// AgentController lifecycle
// ─────────────────────────────────────────────────────────────────────────

AgentController::AgentController(int port) : port_(port) {
    wsa_init();
}

AgentController::~AgentController() {
    stop();
}

bool AgentController::start() {
    if (running_.load()) return true;

    server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd_ == INVALID_SOCK) return false;

    int opt = 1;
    setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR,
               reinterpret_cast<const char*>(&opt), sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(static_cast<uint16_t>(port_));
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        close_socket(server_fd_);
        server_fd_ = INVALID_SOCK;
        return false;
    }
    if (listen(server_fd_, 16) < 0) {
        close_socket(server_fd_);
        server_fd_ = INVALID_SOCK;
        return false;
    }

    running_.store(true);
    accept_thread_ = std::thread([this]{ accept_loop(); });
    return true;
}

void AgentController::stop() {
    running_.store(false);
    if (server_fd_ != INVALID_SOCK) {
        close_socket(server_fd_);
        server_fd_ = INVALID_SOCK;
    }
    if (accept_thread_.joinable()) accept_thread_.join();

    std::lock_guard<std::mutex> lk(clients_mutex_);
    for (auto& c : clients_) {
        c->active.store(false);
        close_socket(c->fd);
        if (c->thread.joinable()) c->thread.join();
    }
    clients_.clear();
}

void AgentController::accept_loop() {
    while (running_.load()) {
        sockaddr_in client_addr{};
        socklen_t len = sizeof(client_addr);
        SocketFd cfd = accept(server_fd_,
                               reinterpret_cast<sockaddr*>(&client_addr), &len);
        if (cfd == INVALID_SOCK) {
            if (!running_.load()) break;
            continue;
        }

        auto conn = std::make_shared<ClientConn>(cfd);
        {
            std::lock_guard<std::mutex> lk(clients_mutex_);
            clients_.push_back(conn);
        }
        conn->thread = std::thread([this, conn]{ client_loop(conn); });
        conn->thread.detach();
    }
}

void AgentController::client_loop(std::shared_ptr<ClientConn> conn) {
    std::string key;
    if (!do_handshake(conn->fd, key)) {
        remove_client(conn->fd);
        return;
    }

    while (conn->active.load() && running_.load()) {
        std::string payload;
        uint8_t opcode;
        if (!recv_frame(conn->fd, payload, opcode)) break;

        if (opcode == 0x08) break; // close
        if (opcode == 0x09) {      // ping → pong
            send_frame(conn->fd, payload, 0x0A);
            continue;
        }
        if (opcode == 0x01 || opcode == 0x02) { // text or binary
            AgentSuggestion suggestion;
            if (parse_suggestion(payload, suggestion)) {
                TuningLogEntry entry;
                entry.param_name = suggestion.param_name;
                entry.new_value  = suggestion.proposed_value;
                entry.reason     = suggestion.reason;
                entry.generation = 0;

                bool accepted = false;
                if (suggestion_handler_) {
                    accepted = suggestion_handler_(suggestion, entry);
                }
                entry.accepted = accepted;

                {
                    std::lock_guard<std::mutex> lk(log_mutex_);
                    log_.push_back(entry);
                }

                // Send acknowledgement
                std::string ack = "{\"status\":\"" + std::string(accepted ? "accepted" : "rejected")
                    + "\",\"param\":\"" + suggestion.param_name + "\"}";
                send_frame(conn->fd, ack);
            }
        }
    }
    remove_client(conn->fd);
}

void AgentController::remove_client(SocketFd fd) {
    std::lock_guard<std::mutex> lk(clients_mutex_);
    clients_.erase(std::remove_if(clients_.begin(), clients_.end(),
        [fd](const std::shared_ptr<ClientConn>& c){ return c->fd == fd; }),
        clients_.end());
    close_socket(fd);
}

int AgentController::broadcast(const std::string& json) {
    std::lock_guard<std::mutex> lk(clients_mutex_);
    int sent = 0;
    std::vector<SocketFd> dead;
    for (auto& conn : clients_) {
        if (!conn->active.load()) continue;
        try {
            send_frame(conn->fd, json);
            ++sent;
        } catch (...) {
            dead.push_back(conn->fd);
        }
    }
    for (SocketFd fd : dead) {
        clients_.erase(std::remove_if(clients_.begin(), clients_.end(),
            [fd](const auto& c){ return c->fd == fd; }), clients_.end());
    }
    return sent;
}

int AgentController::broadcast_report(const std::string& json_payload) {
    return broadcast(json_payload);
}

void AgentController::on_suggestion(SuggestionHandler handler) {
    suggestion_handler_ = std::move(handler);
}

int AgentController::client_count() const {
    std::lock_guard<std::mutex> lk(clients_mutex_);
    return static_cast<int>(clients_.size());
}

// ─────────────────────────────────────────────────────────────────────────
// build_broadcast_json
// ─────────────────────────────────────────────────────────────────────────

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
) {
    auto fmt = [](double v) -> std::string {
        if (!std::isfinite(v)) return "null";
        std::ostringstream s; s << std::fixed;
        s.precision(6); s << v;
        return s.str();
    };
    auto arr = [&](const std::vector<double>& v) -> std::string {
        std::string s = "[";
        for (size_t i = 0; i < v.size(); ++i) {
            if (i) s += ",";
            s += fmt(v[i]);
        }
        return s + "]";
    };

    std::ostringstream j;
    j << "{"
      << "\"generation\":"          << generation            << ","
      << "\"best_fitness\":"        << fmt(best_fitness)     << ","
      << "\"rmse_train\":"          << fmt(rmse_train)       << ","
      << "\"rmse_validation\":"     << fmt(rmse_val)         << ","
      << "\"rmse_test\":"           << fmt(rmse_test)        << ","
      << "\"bic\":"                 << fmt(bic)              << ","
      << "\"aic\":"                 << fmt(aic)              << ","
      << "\"population_diversity\":" << fmt(population_diversity) << ","
      << "\"stagnation\":"          << stagnation            << ","
      << "\"mu_f\":"                << fmt(mu_f)             << ","
      << "\"mu_cr\":"               << fmt(mu_cr)            << ","
      << "\"num_terms\":"           << num_terms             << ","
      << "\"is_stable\":"           << (is_stable?"true":"false") << ","
      << "\"overfitting\":"         << (overfitting?"true":"false") << ","
      << "\"underfitting\":"        << (underfitting?"true":"false") << ","
      << "\"pe_ok\":"               << (pe_ok?"true":"false") << ","
      << "\"residual_autocorr\":"   << arr(residual_autocorr) << ","
      << "\"coefficients\":"        << arr(best_coefficients) << ","
      << "\"exponents\":"           << arr(best_exponents)    << ","
      << "\"alerts\":\""            << alerts                 << "\""
      << "}";
    return j.str();
}

} // namespace aegis
