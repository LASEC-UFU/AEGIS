#pragma once
#include <string>
#include <vector>

namespace aegis {

struct ExcitationResult {
    bool   is_persistently_excited = false;
    double rank_ratio              = 0.0;  // effective rank / expected rank
    double min_singular_value      = 0.0;  // smallest SV of Ψ
    std::vector<double> singular_values;
    std::string warning;
};

/**
 * Persistence of Excitation (PE) analyzer.
 *
 * Checks whether the regressor matrix Ψ has sufficient rank for reliable
 * parameter estimation. PE of order p requires the p×p submatrix
 * (1/n)·Ψ^T·Ψ to be positive definite with a minimum eigenvalue above ε_pe.
 */
class ExcitationAnalyzer {
public:
    explicit ExcitationAnalyzer(double pe_threshold = 1e-4)
        : pe_threshold_(pe_threshold) {}

    /**
     * Analyze the regressor matrix for persistence of excitation.
     *   psi : row-major, n × p
     */
    ExcitationResult analyze(const double* psi, int n, int p) const;

private:
    double pe_threshold_;

    /** Compute singular values of A (m × n, row-major) using power iteration. */
    static std::vector<double> svd_singular_values(
        const double* A, int m, int n, int max_iter = 100
    );
};

} // namespace aegis
