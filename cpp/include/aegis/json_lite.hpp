#pragma once
// Minimal, dependency-free JSON value + parser + string escaping.
// Used for configuration, agent actions and model import. Supports the full
// JSON grammar (objects, arrays, strings with escapes, numbers, booleans,
// null). Not optimised for very large documents.

#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <memory>
#include <sstream>
#include <iomanip>
#include <string>
#include <vector>

namespace aegis {
namespace json {

/** Escape a string for inclusion between JSON double quotes. */
inline std::string escape(const std::string& s) {
    std::string r;
    r.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  r += "\\\""; break;
            case '\\': r += "\\\\"; break;
            case '\n': r += "\\n";  break;
            case '\r': r += "\\r";  break;
            case '\t': r += "\\t";  break;
            case '\b': r += "\\b";  break;
            case '\f': r += "\\f";  break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    r += buf;
                } else {
                    r += static_cast<char>(c);
                }
        }
    }
    return r;
}

/** Quoted + escaped JSON string literal. */
inline std::string str(const std::string& s) { return "\"" + escape(s) + "\""; }

/** Finite double → JSON number with 10 significant digits; NaN/Inf → null. */
inline std::string num(double v, int precision = 10) {
    if (!std::isfinite(v)) return "null";
    std::ostringstream ss;
    ss << std::setprecision(precision) << v;
    return ss.str();
}

inline std::string boolean(bool b) { return b ? "true" : "false"; }

inline std::string num_array(const std::vector<double>& v, int precision = 10) {
    std::string s = "[";
    for (size_t i = 0; i < v.size(); ++i) {
        if (i) s += ",";
        s += num(v[i], precision);
    }
    return s + "]";
}

inline std::string str_array(const std::vector<std::string>& v) {
    std::string s = "[";
    for (size_t i = 0; i < v.size(); ++i) {
        if (i) s += ",";
        s += str(v[i]);
    }
    return s + "]";
}

// ── Value ──────────────────────────────────────────────────────────────────

class Value {
public:
    enum class Type { Null, Bool, Number, String, Array, Object };

    Value() = default;
    static Value make_bool(bool b)               { Value v; v.type_ = Type::Bool; v.b_ = b; return v; }
    static Value make_number(double d)           { Value v; v.type_ = Type::Number; v.d_ = d; return v; }
    static Value make_string(std::string s)      { Value v; v.type_ = Type::String; v.s_ = std::move(s); return v; }
    static Value make_array()                    { Value v; v.type_ = Type::Array; return v; }
    static Value make_object()                   { Value v; v.type_ = Type::Object; return v; }

    Type type() const noexcept { return type_; }
    bool is_null()   const noexcept { return type_ == Type::Null; }
    bool is_bool()   const noexcept { return type_ == Type::Bool; }
    bool is_number() const noexcept { return type_ == Type::Number; }
    bool is_string() const noexcept { return type_ == Type::String; }
    bool is_array()  const noexcept { return type_ == Type::Array; }
    bool is_object() const noexcept { return type_ == Type::Object; }

    bool               as_bool(bool def = false)       const { return is_bool() ? b_ : (is_number() ? d_ != 0.0 : def); }
    double             as_number(double def = 0.0)     const { return is_number() ? d_ : (is_bool() ? (b_ ? 1.0 : 0.0) : def); }
    const std::string& as_string()                     const { static const std::string e; return is_string() ? s_ : e; }
    const std::vector<Value>& items()                  const { return arr_; }
    std::vector<Value>&       items()                        { return arr_; }
    const std::vector<std::pair<std::string, Value>>& members() const { return obj_; }

    /** Object lookup (first match); returns nullptr when absent. */
    const Value* get(const std::string& key) const {
        if (!is_object()) return nullptr;
        for (const auto& kv : obj_) if (kv.first == key) return &kv.second;
        return nullptr;
    }
    bool has(const std::string& key) const { return get(key) != nullptr; }

    double number_or(const std::string& key, double def) const {
        const Value* v = get(key);
        return (v && (v->is_number() || v->is_bool())) ? v->as_number(def) : def;
    }
    int int_or(const std::string& key, int def) const {
        const Value* v = get(key);
        if (!v || !(v->is_number() || v->is_bool())) return def;
        double d = v->as_number(def);
        if (!std::isfinite(d)) return def;
        return static_cast<int>(std::llround(d));
    }
    bool bool_or(const std::string& key, bool def) const {
        const Value* v = get(key);
        return (v && (v->is_bool() || v->is_number())) ? v->as_bool(def) : def;
    }
    std::string string_or(const std::string& key, const std::string& def) const {
        const Value* v = get(key);
        return (v && v->is_string()) ? v->as_string() : def;
    }

    void push(Value v) { arr_.push_back(std::move(v)); }
    void set(const std::string& key, Value v) {
        for (auto& kv : obj_) if (kv.first == key) { kv.second = std::move(v); return; }
        obj_.emplace_back(key, std::move(v));
    }

    /** Serialise (compact). */
    std::string dump() const {
        switch (type_) {
            case Type::Null:   return "null";
            case Type::Bool:   return boolean(b_);
            case Type::Number: return num(d_, 17);
            case Type::String: return str(s_);
            case Type::Array: {
                std::string s = "[";
                for (size_t i = 0; i < arr_.size(); ++i) { if (i) s += ","; s += arr_[i].dump(); }
                return s + "]";
            }
            case Type::Object: {
                std::string s = "{";
                for (size_t i = 0; i < obj_.size(); ++i) {
                    if (i) s += ",";
                    s += str(obj_[i].first) + ":" + obj_[i].second.dump();
                }
                return s + "}";
            }
        }
        return "null";
    }

private:
    Type type_ = Type::Null;
    bool b_ = false;
    double d_ = 0.0;
    std::string s_;
    std::vector<Value> arr_;
    std::vector<std::pair<std::string, Value>> obj_;
};

// ── Parser ─────────────────────────────────────────────────────────────────

class Parser {
public:
    explicit Parser(const std::string& text) : t_(text) {}

    /** Parse a complete document. Returns false and sets error() on failure. */
    bool parse(Value& out) {
        pos_ = 0; err_.clear();
        skip_ws();
        if (!parse_value(out, 0)) return false;
        skip_ws();
        if (pos_ != t_.size()) return fail("trailing characters");
        return true;
    }
    const std::string& error() const noexcept { return err_; }

private:
    const std::string& t_;
    size_t pos_ = 0;
    std::string err_;
    static constexpr int kMaxDepth = 64;

    bool fail(const std::string& m) {
        if (err_.empty()) err_ = m + " at offset " + std::to_string(pos_);
        return false;
    }
    void skip_ws() {
        while (pos_ < t_.size() && (t_[pos_] == ' ' || t_[pos_] == '\t' ||
               t_[pos_] == '\n' || t_[pos_] == '\r')) ++pos_;
    }
    bool literal(const char* lit) {
        size_t n = std::char_traits<char>::length(lit);
        if (t_.compare(pos_, n, lit) != 0) return false;
        pos_ += n;
        return true;
    }
    bool parse_value(Value& out, int depth) {
        if (depth > kMaxDepth) return fail("nesting too deep");
        if (pos_ >= t_.size()) return fail("unexpected end");
        char c = t_[pos_];
        if (c == '{') return parse_object(out, depth);
        if (c == '[') return parse_array(out, depth);
        if (c == '"') { std::string s; if (!parse_string(s)) return false; out = Value::make_string(std::move(s)); return true; }
        if (c == 't') { if (!literal("true"))  return fail("bad literal"); out = Value::make_bool(true);  return true; }
        if (c == 'f') { if (!literal("false")) return fail("bad literal"); out = Value::make_bool(false); return true; }
        if (c == 'n') { if (!literal("null"))  return fail("bad literal"); out = Value(); return true; }
        return parse_number(out);
    }
    bool parse_number(Value& out) {
        size_t start = pos_;
        if (pos_ < t_.size() && (t_[pos_] == '-' || t_[pos_] == '+')) ++pos_;
        bool digits = false;
        while (pos_ < t_.size() && std::isdigit(static_cast<unsigned char>(t_[pos_]))) { ++pos_; digits = true; }
        if (pos_ < t_.size() && t_[pos_] == '.') {
            ++pos_;
            while (pos_ < t_.size() && std::isdigit(static_cast<unsigned char>(t_[pos_]))) { ++pos_; digits = true; }
        }
        if (!digits) return fail("invalid number");
        if (pos_ < t_.size() && (t_[pos_] == 'e' || t_[pos_] == 'E')) {
            ++pos_;
            if (pos_ < t_.size() && (t_[pos_] == '-' || t_[pos_] == '+')) ++pos_;
            bool ed = false;
            while (pos_ < t_.size() && std::isdigit(static_cast<unsigned char>(t_[pos_]))) { ++pos_; ed = true; }
            if (!ed) return fail("invalid exponent");
        }
        std::string s = t_.substr(start, pos_ - start);
        char* end = nullptr;
        double d = std::strtod(s.c_str(), &end);
        if (!end || *end != '\0') return fail("invalid number");
        out = Value::make_number(d);
        return true;
    }
    static void append_utf8(std::string& s, uint32_t cp) {
        if (cp < 0x80) s += static_cast<char>(cp);
        else if (cp < 0x800) { s += static_cast<char>(0xC0 | (cp >> 6)); s += static_cast<char>(0x80 | (cp & 0x3F)); }
        else if (cp < 0x10000) { s += static_cast<char>(0xE0 | (cp >> 12)); s += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); s += static_cast<char>(0x80 | (cp & 0x3F)); }
        else { s += static_cast<char>(0xF0 | (cp >> 18)); s += static_cast<char>(0x80 | ((cp >> 12) & 0x3F)); s += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); s += static_cast<char>(0x80 | (cp & 0x3F)); }
    }
    bool parse_hex4(uint32_t& cp) {
        if (pos_ + 4 > t_.size()) return fail("bad \\u escape");
        cp = 0;
        for (int i = 0; i < 4; ++i) {
            char h = t_[pos_++];
            cp <<= 4;
            if (h >= '0' && h <= '9') cp |= static_cast<uint32_t>(h - '0');
            else if (h >= 'a' && h <= 'f') cp |= static_cast<uint32_t>(h - 'a' + 10);
            else if (h >= 'A' && h <= 'F') cp |= static_cast<uint32_t>(h - 'A' + 10);
            else return fail("bad \\u escape");
        }
        return true;
    }
    bool parse_string(std::string& s) {
        ++pos_; // opening quote
        while (pos_ < t_.size()) {
            char c = t_[pos_++];
            if (c == '"') return true;
            if (c == '\\') {
                if (pos_ >= t_.size()) return fail("bad escape");
                char e = t_[pos_++];
                switch (e) {
                    case '"': s += '"'; break;
                    case '\\': s += '\\'; break;
                    case '/': s += '/'; break;
                    case 'b': s += '\b'; break;
                    case 'f': s += '\f'; break;
                    case 'n': s += '\n'; break;
                    case 'r': s += '\r'; break;
                    case 't': s += '\t'; break;
                    case 'u': {
                        uint32_t cp;
                        if (!parse_hex4(cp)) return false;
                        if (cp >= 0xD800 && cp <= 0xDBFF && pos_ + 6 <= t_.size() &&
                            t_[pos_] == '\\' && t_[pos_ + 1] == 'u') {
                            pos_ += 2;
                            uint32_t lo;
                            if (!parse_hex4(lo)) return false;
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        }
                        append_utf8(s, cp);
                        break;
                    }
                    default: return fail("bad escape");
                }
            } else {
                s += c;
            }
        }
        return fail("unterminated string");
    }
    bool parse_array(Value& out, int depth) {
        ++pos_;
        out = Value::make_array();
        skip_ws();
        if (pos_ < t_.size() && t_[pos_] == ']') { ++pos_; return true; }
        while (true) {
            skip_ws();
            Value v;
            if (!parse_value(v, depth + 1)) return false;
            out.push(std::move(v));
            skip_ws();
            if (pos_ >= t_.size()) return fail("unterminated array");
            if (t_[pos_] == ',') { ++pos_; continue; }
            if (t_[pos_] == ']') { ++pos_; return true; }
            return fail("expected , or ]");
        }
    }
    bool parse_object(Value& out, int depth) {
        ++pos_;
        out = Value::make_object();
        skip_ws();
        if (pos_ < t_.size() && t_[pos_] == '}') { ++pos_; return true; }
        while (true) {
            skip_ws();
            if (pos_ >= t_.size() || t_[pos_] != '"') return fail("expected key");
            std::string key;
            if (!parse_string(key)) return false;
            skip_ws();
            if (pos_ >= t_.size() || t_[pos_] != ':') return fail("expected :");
            ++pos_;
            skip_ws();
            Value v;
            if (!parse_value(v, depth + 1)) return false;
            out.set(key, std::move(v));
            skip_ws();
            if (pos_ >= t_.size()) return fail("unterminated object");
            if (t_[pos_] == ',') { ++pos_; continue; }
            if (t_[pos_] == '}') { ++pos_; return true; }
            return fail("expected , or }");
        }
    }
};

/** Convenience: parse text; returns false on error (message in *error). */
inline bool parse(const std::string& text, Value& out, std::string* error = nullptr) {
    Parser p(text);
    bool ok = p.parse(out);
    if (!ok && error) *error = p.error();
    return ok;
}

} // namespace json
} // namespace aegis
