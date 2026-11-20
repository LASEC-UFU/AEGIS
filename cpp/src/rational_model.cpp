#include "aegis/rational_model.hpp"
#include "aegis/safe_power.hpp"
#include <cmath>
#include <sstream>
#include <iomanip>
#include <algorithm>

namespace aegis {

// ── fit ──────────────────────────────────────────────────────────────────

bool RationalModel::fit_from_psi(Chromosome& chrom, const std::vector<double>& psi,
                                 int usable, const double* y) {
    const int nr = chrom.num_regressors();
    if (usable <= 0 || nr <= 0) return false;
    const int ncols = nr + 1;

    // Augment Ψ with a constant column (intercept); pseudo-linearise
    // denominator columns: ψ_j → −y(k)·ψ_j.
    std::vector<double> psi_aug(static_cast<size_t>(usable) * ncols);
    std::vector<char> is_den(nr, 0);
    for (int j = 0; j < nr; ++j) is_den[j] = chrom.regressors[j].is_denominator() ? 1 : 0;
    for (int i = 0; i < usable; ++i) {
        const double* src = psi.data() + static_cast<size_t>(i) * nr;
        double* dst = psi_aug.data() + static_cast<size_t>(i) * ncols;
        for (int j = 0; j < nr; ++j) dst[j] = is_den[j] ? -y[i] * src[j] : src[j];
        dst[nr] = 1.0;
    }

    std::vector<double> theta(ncols, 0.0);
    if (!qr_solve(psi_aug.data(), usable, ncols, y, theta.data())) return false;
    for (double v : theta) if (!is_valid(v)) return false;

    chrom.coefficients.assign(theta.begin(), theta.begin() + nr);
    chrom.intercept = theta[nr];
    return true;
}

bool RationalModel::fit(const double* data, int rows, int cols, int output_col) {
    std::vector<double> psi;
    int usable;
    if (!build_psi_matrix(chrom_, data, rows, cols, psi, usable)) return false;
    const int md = chrom_.max_delay();
    std::vector<double> y(usable);
    for (int i = 0; i < usable; ++i)
        y[i] = data[static_cast<size_t>(i + md) * cols + output_col];
    if (!fit_from_psi(chrom_, psi, usable, y.data())) return false;
    chrom_.evaluated = true;
    return true;
}

// ── prediction ───────────────────────────────────────────────────────────

void RationalModel::predict_from_psi(const Chromosome& chrom, const std::vector<double>& psi,
                                     int usable, std::vector<double>& yhat,
                                     DenominatorStats* den) {
    const int nr = chrom.num_regressors();
    yhat.assign(usable, 0.0);
    if (chrom.coefficients.size() != static_cast<size_t>(nr)) return;
    const bool rational = chrom.is_rational();
    std::vector<char> is_den(nr, 0);
    for (int j = 0; j < nr; ++j) is_den[j] = chrom.regressors[j].is_denominator() ? 1 : 0;
    double prev = 1.0;
    for (int i = 0; i < usable; ++i) {
        const double* row = psi.data() + static_cast<size_t>(i) * nr;
        double num = chrom.intercept, d = 1.0;
        for (int j = 0; j < nr; ++j) {
            if (is_den[j]) d += chrom.coefficients[j] * row[j];
            else           num += chrom.coefficients[j] * row[j];
        }
        if (rational) {
            if (den) den->add(d, prev);
            if (std::abs(d) < kMinDenominator) d = std::copysign(kMinDenominator, d);
            yhat[i] = num / d;
        } else {
            yhat[i] = num;
        }
    }
}

void RationalModel::num_den_at(const double* data, int k, int rows, int cols,
                               double& num, double& den) const noexcept {
    num = chrom_.intercept;
    den = 1.0;
    for (size_t j = 0; j < chrom_.regressors.size(); ++j) {
        const auto& reg = chrom_.regressors[j];
        const double phi = reg.evaluate(data, k, rows, cols, chrom_.power_mode);
        if (reg.is_denominator()) den += chrom_.coefficients[j] * phi;
        else                      num += chrom_.coefficients[j] * phi;
    }
}

double RationalModel::evaluate_at(
    const double* data, int k, int rows, int cols,
    const double*, int /*output_col*/
) const noexcept {
    if (chrom_.coefficients.size() != chrom_.regressors.size()) return 0.0;
    double num, den;
    num_den_at(data, k, rows, cols, num, den);
    if (std::abs(den) < kMinDenominator) den = std::copysign(kMinDenominator, den);
    return num / den;
}

std::vector<double> RationalModel::predict_one_step(
    const double* data, int rows, int cols, int output_col,
    DenominatorStats* den
) const {
    std::vector<double> psi;
    int usable = 0;
    std::vector<double> yhat;
    (void)output_col;
    if (!build_psi_matrix(chrom_, data, rows, cols, psi, usable)) return yhat;
    predict_from_psi(chrom_, psi, usable, yhat, den);
    return yhat;
}

FreeRunResult RationalModel::simulate(
    const double* data, int rows, int cols, int output_col,
    int horizon, double bound
) const {
    FreeRunResult res;
    const int md = chrom_.max_delay();
    const int available = rows - md;
    const int n = horizon > 0 ? std::min(available, horizon) : available;
    if (n <= 0 || chrom_.coefficients.size() != chrom_.regressors.size()) return res;
    const int needed_rows = md + n;

    // Mutable copy: the output column is overwritten by the predictions.
    std::vector<double> buf(data, data + static_cast<size_t>(needed_rows) * cols);
    res.yhat.resize(n);
    const bool rational = chrom_.is_rational();
    double prev_den = 1.0;
    for (int i = 0; i < n; ++i) {
        const int k = i + md;
        double yp;
        if (res.diverged) {
            yp = res.yhat[i - 1];
        } else {
            double num, den;
            num_den_at(buf.data(), k, needed_rows, cols, num, den);
            if (rational) res.den.add(den, prev_den);
            if (std::abs(den) < kMinDenominator) den = std::copysign(kMinDenominator, den);
            yp = num / den;
            if (!std::isfinite(yp) || std::abs(yp) > bound) {
                res.diverged = true;
                res.divergence_step = i;
                if (!std::isfinite(yp)) yp = (std::isnan(yp) || yp > 0) ? bound : -bound;
                else yp = std::copysign(bound, yp);
                if (!std::isfinite(yp)) yp = 0.0; // unbounded case: keep finite
            }
        }
        res.yhat[i] = yp;
        buf[static_cast<size_t>(k) * cols + output_col] = yp;
    }
    return res;
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
        term_ss << std::setprecision(6) << std::abs(coef);
        for (const auto& t : reg.terms) {
            term_ss << "*x" << t.variable << "(k-" << t.delay << ")";
            if (t.exponent != 1.0)
                term_ss << "^" << std::setprecision(4) << t.exponent;
        }
        std::string sign = (coef >= 0) ? " + " : " - ";
        if (reg.is_denominator()) {
            if (!first_den) den_ss << sign; else if (coef < 0) den_ss << "-";
            den_ss << term_ss.str();
            first_den = false;
        } else {
            if (!first_num) num_ss << sign; else if (coef < 0) num_ss << "-";
            num_ss << term_ss.str();
            first_num = false;
        }
    }

    if (std::abs(chrom_.intercept) > 1e-12) {
        std::ostringstream ic_ss;
        ic_ss << std::setprecision(6) << std::abs(chrom_.intercept);
        if (!num_ss.str().empty())
            num_ss << (chrom_.intercept >= 0 ? " + " : " - ");
        else if (chrom_.intercept < 0)
            num_ss << "-";
        num_ss << ic_ss.str();
    }

    std::string num = num_ss.str().empty() ? "0" : num_ss.str();
    std::string den = den_ss.str().empty() ? "" : (" + " + den_ss.str());
    return "y_hat(k) = (" + num + ") / (1" + den + ")  [basis=" +
           power_mode_name(chrom_.power_mode) + "]";
}

} // namespace aegis
