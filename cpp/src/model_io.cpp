#include "aegis/model_io.hpp"
#include "aegis/rational_model.hpp"
#include "aegis/metrics.hpp"
#include <cmath>
#include <cstdio>
#include <sstream>

#ifndef AEGIS_VERSION_STRING
#define AEGIS_VERSION_STRING "1.1.0-audit"
#endif
#ifndef AEGIS_BUILD_FLAGS
#define AEGIS_BUILD_FLAGS "unknown"
#endif

namespace aegis {

std::string chromosome_structure_json(const Chromosome& c) {
    std::ostringstream j;
    j << "{\"powerMode\":" << json::str(power_mode_name(c.power_mode))
      << ",\"intercept\":" << json::num(c.intercept, 17)
      << ",\"coefficients\":" << json::num_array(c.coefficients, 17)
      << ",\"regressors\":[";
    for (size_t i = 0; i < c.regressors.size(); ++i) {
        if (i) j << ",";
        j << "{\"terms\":[";
        const auto& reg = c.regressors[i];
        for (size_t t = 0; t < reg.terms.size(); ++t) {
            if (t) j << ",";
            const auto& term = reg.terms[t];
            j << "{\"variable\":" << term.variable
              << ",\"delay\":" << term.delay
              << ",\"exponent\":" << json::num(term.exponent, 17)
              << ",\"isDenominator\":" << json::boolean(term.is_denominator) << "}";
        }
        j << "]}";
    }
    j << "]}";
    return j.str();
}

bool chromosome_from_json(const json::Value& v, Chromosome& out,
                          PowerMode default_mode, std::string* error) {
    auto fail = [&](const std::string& m) { if (error) *error = m; return false; };
    if (!v.is_object()) return fail("model must be a JSON object");
    const json::Value* model = &v;
    if (const json::Value* inner = v.get("model"); inner && inner->is_object() && inner->has("regressors"))
        model = inner;
    const json::Value* regs = model->get("regressors");
    if (!regs || !regs->is_array() || regs->items().empty()) return fail("missing regressors");

    Chromosome c;
    c.power_mode = power_mode_from_name(model->string_or("powerMode", ""), default_mode);
    for (const auto& r : regs->items()) {
        const json::Value* terms = r.get("terms");
        if (!terms || !terms->is_array() || terms->items().empty()) return fail("regressor without terms");
        Regressor reg;
        for (const auto& tv : terms->items()) {
            Term t;
            t.variable = tv.int_or("variable", -1);
            t.delay = tv.int_or("delay", 0);
            t.exponent = tv.number_or("exponent", 1.0);
            t.is_denominator = tv.bool_or("isDenominator", false);
            if (t.variable < 0 || t.delay < 1 || !std::isfinite(t.exponent) || t.exponent <= 0.0)
                return fail("invalid term (variable ≥ 0, delay ≥ 1, exponent > 0 required)");
            reg.terms.push_back(t);
        }
        c.regressors.push_back(std::move(reg));
    }
    if (const json::Value* co = model->get("coefficients"); co && co->is_array() && !co->items().empty()) {
        if (co->items().size() != c.regressors.size()) return fail("coefficients/regressors size mismatch");
        for (const auto& x : co->items()) {
            if (!x.is_number() || !std::isfinite(x.as_number())) return fail("non-finite coefficient");
            c.coefficients.push_back(x.as_number());
        }
        c.intercept = model->number_or("intercept", 0.0);
        c.evaluated = true;
    }
    out = std::move(c);
    return true;
}

// ── segment evaluation ───────────────────────────────────────────────────

static double fit_percent(const std::vector<double>& y, const std::vector<double>& yh) {
    const size_t n = y.size();
    if (n < 2) return std::numeric_limits<double>::quiet_NaN();
    double mean = 0.0;
    for (double v : y) mean += v;
    mean /= static_cast<double>(n);
    double e2 = 0.0, d2 = 0.0;
    for (size_t i = 0; i < n; ++i) {
        e2 += (y[i] - yh[i]) * (y[i] - yh[i]);
        d2 += (y[i] - mean) * (y[i] - mean);
    }
    if (d2 < 1e-300) return std::numeric_limits<double>::quiet_NaN();
    return 100.0 * (1.0 - std::sqrt(e2 / d2));
}

SegmentMetrics evaluate_segment(const Chromosome& c, const double* norm_data,
                                int rows, int cols, int output_col,
                                int seg_start, int seg_end, int score_start,
                                double bound, const Normalizer* norm,
                                const std::string& name) {
    SegmentMetrics m;
    m.name = name;
    seg_start = std::max(0, seg_start);
    seg_end = std::min(rows, seg_end);
    const int md = c.max_delay();
    score_start = std::max(score_start, seg_start + md);
    m.seg_start = seg_start; m.seg_end = seg_end; m.score_start = score_start;
    if (seg_end - score_start < 2 || c.coefficients.size() != c.regressors.size()) return m;

    const double* seg = norm_data + static_cast<size_t>(seg_start) * cols;
    const int seg_rows = seg_end - seg_start;
    RationalModel model(c);

    // yhat index i ↔ absolute row seg_start + md + i
    DenominatorStats den;
    std::vector<double> os = model.predict_one_step(seg, seg_rows, cols, output_col, &den);
    FreeRunResult fr = model.simulate(seg, seg_rows, cols, output_col, -1, bound);

    std::vector<double> y, yos, yfr;
    const int first = score_start - (seg_start + md);
    for (int i = first; i < static_cast<int>(os.size()); ++i) {
        const int row = seg_start + md + i;
        y.push_back(norm_data[static_cast<size_t>(row) * cols + output_col]);
        yos.push_back(os[i]);
        yfr.push_back(i < static_cast<int>(fr.yhat.size()) ? fr.yhat[i] : 0.0);
    }
    m.n = static_cast<int>(y.size());
    if (m.n < 2) return m;
    m.rmse_one_step = Metrics::rmse(y.data(), yos.data(), m.n);
    m.r2_one_step   = Metrics::r2(y.data(), yos.data(), m.n);
    m.fit_one_step  = fit_percent(y, yos);
    m.rmse_free_run = Metrics::rmse(y.data(), yfr.data(), m.n);
    m.r2_free_run   = Metrics::r2(y.data(), yfr.data(), m.n);
    m.fit_free_run  = fit_percent(y, yfr);
    m.free_run_diverged = fr.diverged;
    m.divergence_row = fr.diverged ? seg_start + md + fr.divergence_step : -1;
    if (c.is_rational()) {
        m.min_abs_denominator = std::min(den.min_abs, fr.den.min_abs);
        m.denominator_sign_changes = den.sign_changes + fr.den.sign_changes;
    }
    if (norm && output_col < norm->num_cols()) {
        double s_os = 0.0, s_fr = 0.0, a_fr = 0.0, mx = 0.0;
        for (int i = 0; i < m.n; ++i) {
            const double yo = norm->inverse_scalar(y[i], output_col);
            const double e1 = yo - norm->inverse_scalar(yos[i], output_col);
            const double e2 = yo - norm->inverse_scalar(yfr[i], output_col);
            s_os += e1 * e1; s_fr += e2 * e2; a_fr += std::abs(e2);
            mx = std::max(mx, std::abs(e2));
        }
        m.rmse_one_step_orig = std::sqrt(s_os / m.n);
        m.rmse_free_run_orig = std::sqrt(s_fr / m.n);
        m.mae_free_run_orig  = a_fr / m.n;
        m.max_abs_err_free_run_orig = mx;
    }
    return m;
}

std::string SegmentMetrics::to_json() const {
    std::ostringstream j;
    j << "{\"name\":" << json::str(name)
      << ",\"segStart\":" << seg_start << ",\"segEnd\":" << seg_end
      << ",\"scoreStart\":" << score_start << ",\"n\":" << n
      << ",\"rmseOneStep\":" << json::num(rmse_one_step)
      << ",\"r2OneStep\":" << json::num(r2_one_step)
      << ",\"fitOneStep\":" << json::num(fit_one_step)
      << ",\"rmseFreeRun\":" << json::num(rmse_free_run)
      << ",\"r2FreeRun\":" << json::num(r2_free_run)
      << ",\"fitFreeRun\":" << json::num(fit_free_run)
      << ",\"rmseOneStepOrig\":" << json::num(rmse_one_step_orig)
      << ",\"rmseFreeRunOrig\":" << json::num(rmse_free_run_orig)
      << ",\"maeFreeRunOrig\":" << json::num(mae_free_run_orig)
      << ",\"maxAbsErrFreeRunOrig\":" << json::num(max_abs_err_free_run_orig)
      << ",\"freeRunDiverged\":" << json::boolean(free_run_diverged)
      << ",\"divergenceRow\":" << divergence_row
      << ",\"minAbsDenominator\":" << json::num(min_abs_denominator)
      << ",\"denominatorSignChanges\":" << denominator_sign_changes
      << "}";
    return j.str();
}

std::string hash_doubles(const double* data, size_t n) {
    uint64_t h = 1469598103934665603ULL;
    const unsigned char* p = reinterpret_cast<const unsigned char*>(data);
    for (size_t i = 0; i < n * sizeof(double); ++i) {
        h ^= p[i];
        h *= 1099511628211ULL;
    }
    char buf[17];
    std::snprintf(buf, sizeof(buf), "%016llx", static_cast<unsigned long long>(h));
    return buf;
}

std::string build_info_json() {
    std::ostringstream j;
    j << "{\"version\":" << json::str(AEGIS_VERSION_STRING);
#if defined(__clang__)
    j << ",\"compiler\":" << json::str(std::string("clang ") + __clang_version__);
#elif defined(__GNUC__)
    j << ",\"compiler\":" << json::str("gcc " + std::to_string(__GNUC__) + "." +
                                       std::to_string(__GNUC_MINOR__) + "." +
                                       std::to_string(__GNUC_PATCHLEVEL__));
#elif defined(_MSC_VER)
    j << ",\"compiler\":" << json::str("msvc " + std::to_string(_MSC_VER));
#else
    j << ",\"compiler\":\"unknown\"";
#endif
#if defined(__EMSCRIPTEN__)
    j << ",\"target\":\"wasm\"";
#elif defined(_WIN32)
    j << ",\"target\":\"windows\"";
#else
    j << ",\"target\":\"posix\"";
#endif
    j << ",\"flags\":" << json::str(AEGIS_BUILD_FLAGS)
      << ",\"cppStandard\":" << __cplusplus << "}";
    return j.str();
}

} // namespace aegis
