#include "aegis/rational_model.hpp"
#include "aegis/safe_power.hpp"
#include <cmath>
#include <sstream>
#include <iomanip>
#include <algorithm>

namespace aegis {

// ── fit ──────────────────────────────────────────────────────────────────

bool RationalModel::fit(const double* data, int rows, int cols, int output_col) {
    std::vector<double> psi;
    int usable;
    if (!build_psi_matrix(chrom_, data, rows, cols, psi, usable)) return false;

    const int nr = chrom_.num_regressors();
    const int md = chrom_.max_delay();

    // Extract y(k) for the usable samples
    std::vector<double> y_col(usable);
    for (int i = 0; i < usable; ++i)
        y_col[i] = data[(i + md) * cols + output_col];

    // Pseudo-linearise denominator columns: ψ_j → −y(k)·ψ_j
    if (chrom_.is_rational()) {
        pseudo_linearize(chrom_, y_col.data(), psi.data(), usable, nr);
    }

    // Solve Ψ·θ = y  via Householder QR
    std::vector<double> theta(nr, 0.0);
    if (!qr_solve(psi.data(), usable, nr, y_col.data(), theta.data()))
        return false;

    // Validate result
    for (double v : theta) {
        if (!aegis::is_valid(v)) return false;
    }

    chrom_.coefficients = theta;
    chrom_.evaluated    = true;
    return true;
}

// ── evaluate_at ──────────────────────────────────────────────────────────

double RationalModel::eval_numerator(
    const double* data, int k, int rows, int cols,
    const double* y_buf, int output_col
) const noexcept {
    double num = 0.0;
    for (size_t j = 0; j < chrom_.regressors.size(); ++j) {
        const auto& reg = chrom_.regressors[j];
        if (reg.is_denominator()) continue;
        double phi = reg.evaluate(data, k, rows, cols, true);
        num += chrom_.coefficients[j] * phi;
    }
    return num;
}

double RationalModel::eval_denominator(
    const double* data, int k, int rows, int cols,
    const double* y_buf, int output_col
) const noexcept {
    double denom = 1.0;
    for (size_t j = 0; j < chrom_.regressors.size(); ++j) {
        const auto& reg = chrom_.regressors[j];
        if (!reg.is_denominator()) continue;
        // Denominator terms reference y(k-delay); use y_buf if output var
        double phi = reg.evaluate(data, k, rows, cols, true);
        denom += chrom_.coefficients[j] * phi;
    }
    return denom;
}

double RationalModel::evaluate_at(
    const double* data, int k, int rows, int cols,
    const double*, int output_col
) const noexcept {
    if (chrom_.coefficients.empty()) return 0.0;
    double num   = eval_numerator  (data, k, rows, cols, nullptr, output_col);
    double denom = eval_denominator(data, k, rows, cols, nullptr, output_col);
    if (std::abs(denom) < 1e-12) denom = std::copysign(1e-12, denom);
    return num / denom;
}

// ── predict_one_step ──────────────────────────────────────────────────────

std::vector<double> RationalModel::predict_one_step(
    const double* data, int rows, int cols, int output_col
) const {
    const int md = chrom_.max_delay();
    const int n  = rows - md;
    std::vector<double> yhat(n);
    for (int i = 0; i < n; ++i) {
        int k = i + md;
        yhat[i] = evaluate_at(data, k, rows, cols, nullptr, output_col);
    }
    return yhat;
}

// ── predict_free_run ─────────────────────────────────────────────────────

std::vector<double> RationalModel::predict_free_run(
    const double* data, int rows, int cols, int output_col
) const {
    const int md = chrom_.max_delay();
    const int n  = rows - md;

    // Make a mutable copy of data so we can overwrite the output column
    std::vector<double> data_buf(data, data + static_cast<size_t>(rows) * cols);
    std::vector<double> yhat(n);

    for (int i = 0; i < n; ++i) {
        int k = i + md;
        double yp = evaluate_at(data_buf.data(), k, rows, cols, nullptr, output_col);
        if (!std::isfinite(yp)) yp = 0.0;
        yhat[i] = yp;
        // Feed prediction back for future time steps
        data_buf[static_cast<size_t>(k) * cols + output_col] = yp;
    }
    return yhat;
}

// ── equation_string ───────────────────────────────────────────────────────

std::string RationalModel::equation_string() const {
    if (chrom_.coefficients.empty()) return "y_hat(k) = [not fitted]";

    std::ostringstream num_ss, den_ss;
    bool first_num = true, first_den = true;

    for (size_t j = 0; j < chrom_.regressors.size(); ++j) {
        const auto& reg = chrom_.regressors[j];
        double coef = chrom_.coefficients[j];
        std::ostringstream term_ss;
        term_ss << std::fixed << std::setprecision(4) << std::abs(coef);
        for (const auto& t : reg.terms) {
            term_ss << "·" << (t.is_denominator ? "y" : "x")
                    << t.variable << "(k-" << t.delay << ")";
            if (t.exponent != 1.0)
                term_ss << "^" << std::fixed << std::setprecision(2) << t.exponent;
        }
        std::string sign = (coef >= 0) ? " + " : " - ";
        if (reg.is_denominator()) {
            if (!first_den) den_ss << sign;
            den_ss << term_ss.str();
            first_den = false;
        } else {
            if (!first_num) num_ss << sign;
            num_ss << term_ss.str();
            first_num = false;
        }
    }

    std::string num = num_ss.str().empty() ? "0" : num_ss.str();
    std::string den = den_ss.str().empty() ? "" : (" + " + den_ss.str());
    return "y_hat(k) = (" + num + ") / (1" + den + ")";
}

} // namespace aegis
