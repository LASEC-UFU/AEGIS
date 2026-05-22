#include "aegis/normalizer.hpp"
#include <algorithm>
#include <numeric>
#include <cmath>
#include <stdexcept>
#include <vector>

namespace aegis {

// ── Helpers ────────────────────────────────────────────────────────────────

static double percentile(std::vector<double>& v, double p) {
    if (v.empty()) return 0.0;
    std::sort(v.begin(), v.end());
    double idx = p * (v.size() - 1);
    size_t lo  = static_cast<size_t>(idx);
    size_t hi  = std::min(lo + 1, v.size() - 1);
    double frac = idx - lo;
    return v[lo] * (1.0 - frac) + v[hi] * frac;
}

// ── Normalizer ─────────────────────────────────────────────────────────────

void Normalizer::fit(const double* data, int rows, int cols) {
    cols_.resize(cols);
    switch (type_) {
        case NormalizerType::MinMax:    fit_minmax(data, rows, cols); break;
        case NormalizerType::RobustScaler: fit_robust(data, rows, cols); break;
        case NormalizerType::ZScore:    fit_zscore(data, rows, cols);  break;
    }
    for (auto& c : cols_) {
        c.lo    = lo_;
        c.hi    = hi_;
        c.valid = true;
    }
}

void Normalizer::fit_minmax(const double* data, int rows, int cols) {
    for (int j = 0; j < cols; ++j) {
        double mn = data[j], mx = data[j];
        for (int i = 1; i < rows; ++i) {
            double v = data[i * cols + j];
            mn = std::min(mn, v);
            mx = std::max(mx, v);
        }
        auto& c = cols_[j];
        double range = mx - mn;
        if (range < 1e-30) {
            c.shift = (mn + mx) * 0.5;
            c.scale = 1.0;
        } else {
            c.shift = mn;
            c.scale = range;
        }
    }
}

void Normalizer::fit_robust(const double* data, int rows, int cols) {
    for (int j = 0; j < cols; ++j) {
        std::vector<double> col(rows);
        for (int i = 0; i < rows; ++i) col[i] = data[i * cols + j];
        double q25 = percentile(col, 0.25);
        double q50 = percentile(col, 0.50);
        double q75 = percentile(col, 0.75);
        double iqr = q75 - q25;
        auto& c = cols_[j];
        c.shift = q50;
        c.scale = (iqr < 1e-30) ? 1.0 : iqr;
    }
}

void Normalizer::fit_zscore(const double* data, int rows, int cols) {
    for (int j = 0; j < cols; ++j) {
        double sum = 0.0, sum2 = 0.0;
        for (int i = 0; i < rows; ++i) {
            double v = data[i * cols + j];
            sum  += v;
            sum2 += v * v;
        }
        double mean = sum / rows;
        double var  = sum2 / rows - mean * mean;
        auto& c  = cols_[j];
        c.shift  = mean;
        c.scale  = (var < 1e-30) ? 1.0 : std::sqrt(var);
    }
}

void Normalizer::transform(double* data, int rows, int cols) const {
    if (static_cast<int>(cols_.size()) != cols)
        throw std::runtime_error("Normalizer: cols mismatch in transform");
    for (int i = 0; i < rows; ++i) {
        for (int j = 0; j < cols; ++j) {
            data[i * cols + j] = cols_[j].transform(data[i * cols + j]);
        }
    }
}

void Normalizer::inverse_transform_col(double* col, int rows, int col_idx) const {
    const auto& cn = cols_.at(col_idx);
    for (int i = 0; i < rows; ++i) col[i] = cn.inverse(col[i]);
}

double Normalizer::inverse_scalar(double y, int col_idx) const {
    return cols_.at(col_idx).inverse(y);
}

} // namespace aegis
