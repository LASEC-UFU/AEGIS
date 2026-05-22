#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
#include <stdexcept>

namespace aegis {

enum class NormalizerType { MinMax, RobustScaler, ZScore };

/** Per-column normalizer. Fit on training data; apply to val/test. */
struct ColumnNorm {
    double shift = 0.0;   // subtract first
    double scale = 1.0;   // then divide
    double lo    = 0.0;   // output range low  (default 1e-6)
    double hi    = 1.0;   // output range high (default 1.0)
    bool   valid = false; // true after fit()

    /** Map raw x → [lo, hi]. */
    double transform(double x) const noexcept {
        if (scale < 1e-30) return (lo + hi) * 0.5;
        double v = (x - shift) / scale;
        // Remap [0,1] to [lo,hi]
        v = lo + v * (hi - lo);
        return std::max(lo, std::min(hi, v));
    }

    /** Invert: [lo, hi] → raw. */
    double inverse(double y) const noexcept {
        if (hi <= lo) return shift;
        double v = (y - lo) / (hi - lo);
        return shift + v * scale;
    }
};

class Normalizer {
public:
    explicit Normalizer(NormalizerType type = NormalizerType::MinMax,
                        double lo = 1e-6, double hi = 1.0)
        : type_(type), lo_(lo), hi_(hi) {}

    /**
     * Fit on training data (row-major, rows × cols).
     * Stores per-column statistics; does NOT modify the data.
     */
    void fit(const double* data, int rows, int cols);

    /** Transform a data matrix in-place (row-major, rows × cols). */
    void transform(double* data, int rows, int cols) const;

    /** Inverse-transform a single column vector (length = rows). */
    void inverse_transform_col(double* col, int rows, int col_idx) const;

    /** Inverse-transform one scalar value in column col_idx. */
    double inverse_scalar(double y, int col_idx) const;

    int num_cols() const noexcept { return static_cast<int>(cols_.size()); }
    const ColumnNorm& col_norm(int i) const { return cols_.at(i); }

private:
    NormalizerType       type_;
    double               lo_, hi_;
    std::vector<ColumnNorm> cols_;

    void fit_minmax(const double* data, int rows, int cols);
    void fit_robust(const double* data, int rows, int cols);
    void fit_zscore(const double* data, int rows, int cols);
};

} // namespace aegis
