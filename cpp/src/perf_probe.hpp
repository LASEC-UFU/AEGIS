// perf_probe.hpp — P0 profiling probe (docs/architecture/10_AUDITORIA_DO_09.md §11.3).
// Compiled in only with -DAEGIS_PROFILE; otherwise every macro is empty and the
// evaluator is byte-for-byte the frozen code path.
//
// Output: one text file per thread, $AEGIS_PROFILE_OUT.<tid>.tsv, one line per
// evaluate() call:
//   K nden nfac nnonint md ok t_psi t_fit t_pred t_err t_ratio t_val t_sim t_rest [struct]
// Times are nanoseconds (steady_clock). With AEGIS_PROFILE_STRUCT=1 a last column
// lists the regressors as N|D:v,d,p;v,d,p/... for the cache-hit study (P2'b).
#pragma once
#ifdef AEGIS_PROFILE
#include "aegis/regressor_library.hpp"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
#include <thread>
#include <functional>

namespace aegis { namespace perf {

enum Stage { PSI = 0, FIT, PRED, ERRF, RATIO, VAL, SIM, REST, NSTAGE };

struct ThreadSink {
    std::FILE* f = nullptr;
    bool want_struct = false;
    ThreadSink() {
        const char* base = std::getenv("AEGIS_PROFILE_OUT");
        if (!base || !*base) return;
        const char* s = std::getenv("AEGIS_PROFILE_STRUCT");
        want_struct = s && s[0] == '1';
        const size_t tid = std::hash<std::thread::id>{}(std::this_thread::get_id());
        std::string path = std::string(base) + "." + std::to_string(tid % 1000000007u) + ".tsv";
        f = std::fopen(path.c_str(), "w");
        if (f) std::setvbuf(f, nullptr, _IOFBF, 1 << 20);
    }
    ~ThreadSink() { if (f) std::fclose(f); }
};

inline ThreadSink& sink() { static thread_local ThreadSink s; return s; }

struct EvalProbe {
    using clk = std::chrono::steady_clock;
    const Chromosome& chrom;
    const bool& ok;
    clk::time_point last;
    long long t[NSTAGE] = {0};
    EvalProbe(const Chromosome& c, const bool& valid) : chrom(c), ok(valid), last(clk::now()) {}
    void mark(Stage s) {
        const auto now = clk::now();
        t[s] += std::chrono::duration_cast<std::chrono::nanoseconds>(now - last).count();
        last = now;
    }
    ~EvalProbe() {
        mark(REST);
        ThreadSink& o = sink();
        if (!o.f) return;
        int nden = 0, nfac = 0, nnonint = 0;
        for (const auto& r : chrom.regressors) {
            if (r.is_denominator()) ++nden;
            for (const auto& tm : r.terms) {
                ++nfac;
                if (std::abs(tm.exponent - std::round(tm.exponent)) > 1e-12) ++nnonint;
            }
        }
        std::fprintf(o.f, "%d\t%d\t%d\t%d\t%d\t%d", chrom.num_regressors(), nden, nfac, nnonint,
                     chrom.max_delay(), ok ? 1 : 0);
        for (int i = 0; i < NSTAGE; ++i) std::fprintf(o.f, "\t%lld", t[i]);
        if (o.want_struct) {
            std::fputc('\t', o.f);
            bool first = true;
            for (const auto& r : chrom.regressors) {
                if (!first) std::fputc('/', o.f);
                first = false;
                std::fputs(r.is_denominator() ? "D:" : "N:", o.f);
                bool ft = true;
                for (const auto& tm : r.terms) {
                    if (!ft) std::fputc(';', o.f);
                    ft = false;
                    std::fprintf(o.f, "%d,%d,%g", tm.variable, tm.delay, tm.exponent);
                }
            }
        }
        std::fputc('\n', o.f);
    }
};

}} // namespace aegis::perf

#define AEGIS_PROBE_BEGIN(chrom, okflag) ::aegis::perf::EvalProbe aegis_probe_((chrom), (okflag))
#define AEGIS_PROBE_MARK(stage) aegis_probe_.mark(::aegis::perf::stage)
#else
#define AEGIS_PROBE_BEGIN(chrom, okflag) ((void)0)
#define AEGIS_PROBE_MARK(stage) ((void)0)
#endif
