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
    bool   bounded = true; // min-max maps to [lo,hi]; robust/z-score do not

    /**
     * Affine map fitted on the training segment. For min-max, the training
     * range is mapped onto [lo, hi]; samples outside the training range
     * (validation/test extrapolation) are mapped linearly and are NOT clipped,
     * so that held-out data are never altered (audit item P0-3).
     */
    double transform(double x) const noexcept {
        if (scale < 1e-30) return (lo + hi) * 0.5;
        double v = (x - shift) / scale;
        if (!bounded) return v;
        return lo + v * (hi - lo);
    }

    /** Invert: [lo, hi] → raw. */
    double inverse(double y) const noexcept {
        if (!bounded) return shift + y * scale;
        if (hi <= lo) return shift;
        double v = (y - lo) / (hi - lo);
        return shift + v * scale;
    }
};

class Normalizer {
public:
    explicit Normalizer(NormalizerType type = NormalizerType::MinMax,
                        double lo = -1.0, double hi = 1.0)
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
