"""
narx_utils.py — Shared NARX utilities for baseline comparison methods.

Provides:
  - CSV loading with auto-detect separator
  - MinMax normalization (fit on training prefix)
  - Candidate regressor enumeration (polynomial, degree 1 and 2)
  - Full candidate matrix pre-build (fast repeated evaluations)
  - OLS coefficient estimation + fitness computation
  - JSON result saving in the same format as aegis_batch
"""

from __future__ import annotations
import csv
import json
import os
import time
from dataclasses import dataclass, field, asdict
from typing import Optional

import numpy as np


# ─── Configuration ─────────────────────────────────────────────────────────

@dataclass
class NarxConfig:
    n_y: int         = 9     # output lags  (match AEGIS max_delay)
    n_u: int         = 9     # input  lags
    max_degree: int  = 2     # polynomial degree (1 = linear, 2 = quadratic + cross)
    output_col: int  = -1    # -1 = last column
    train_ratio: float = 0.70
    val_ratio:   float = 0.15
    test_ratio:  float = 0.15
    alpha_bic: float  = 0.01  # BIC weight in fitness
    gamma_cplx: float = 0.01  # complexity penalty weight


# ─── CSV / data loading ─────────────────────────────────────────────────────

def load_csv(path: str) -> np.ndarray:
    """Load a CSV/TSV file, skipping header rows (non-numeric lines).
    Returns float64 ndarray of shape (n_samples, n_cols)."""
    with open(path, "r", newline="") as f:
        sample = f.read(4096)

    sep = "\t" if "\t" in sample else (";" if ";" in sample else ",")

    rows = []
    with open(path, "r", newline="") as f:
        reader = csv.reader(f, delimiter=sep)
        for line in reader:
            if not line:
                continue
            try:
                rows.append([float(v.strip()) for v in line])
            except ValueError:
                continue  # skip header / comment lines

    if not rows:
        raise ValueError(f"No numeric data found in {path}")

    return np.array(rows, dtype=np.float64)


def normalize_minmax(data: np.ndarray, train_end: int):
    """Fit MinMax on training rows, apply to all. Returns (normalized, mins, maxs)."""
    mins = data[:train_end].min(axis=0)
    maxs = data[:train_end].max(axis=0)
    rng  = maxs - mins
    rng[rng == 0] = 1.0  # avoid division by zero for constant columns
    return (data - mins) / rng, mins, maxs


def split_indices(n: int, cfg: NarxConfig):
    """Return (t_end, v_end) row indices for train/val/test partitions."""
    t_end = int(n * cfg.train_ratio)
    v_end = int(n * (cfg.train_ratio + cfg.val_ratio))
    return t_end, v_end


# ─── Regressor enumeration ──────────────────────────────────────────────────

def enumerate_candidates(n_cols: int, cfg: NarxConfig):
    """
    Enumerate all polynomial candidate regressors up to cfg.max_degree.
    Each candidate is a list of (col_idx, lag) pairs that are multiplied together.

    Returns:
        candidates: list of lists, each inner list is a term's factors
        labels:     human-readable string for each candidate
    """
    out_col = cfg.output_col % n_cols

    # All base signals: (col, lag)
    base = []
    for col in range(n_cols):
        max_lag = cfg.n_y if col == out_col else cfg.n_u
        for lag in range(1, max_lag + 1):
            name = f"y(k-{lag})" if col == out_col else f"u{col}(k-{lag})"
            base.append(((col, lag), name))

    candidates = []
    labels     = []

    # Degree 1
    for (cl, nm) in base:
        candidates.append([cl])
        labels.append(nm)

    # Degree 2 (including squared terms)
    if cfg.max_degree >= 2:
        for i in range(len(base)):
            for j in range(i, len(base)):
                (cl_i, nm_i) = base[i]
                (cl_j, nm_j) = base[j]
                candidates.append([cl_i, cl_j])
                labels.append(f"{nm_i}·{nm_j}" if i != j else f"{nm_i}²")

    return candidates, labels


def build_full_candidate_matrix(data: np.ndarray, candidates, cfg: NarxConfig,
                                 row_start: int, row_end: int):
    """
    Pre-build the full candidate matrix (n_rows × n_candidates) for rows [row_start, row_end).
    Also returns the output vector y.
    Call once per partition; then use column selection for individual evaluations.
    """
    n_cands  = len(candidates)
    n_rows   = row_end - row_start
    out_col  = cfg.output_col % data.shape[1]

    Phi = np.ones((n_rows, n_cands), dtype=np.float64)
    for j, term in enumerate(candidates):
        for (col, lag) in term:
            src_idx = np.clip(np.arange(row_start, row_end) - lag, 0, data.shape[0] - 1)
            Phi[:, j] *= data[src_idx, col]

    y = data[row_start:row_end, out_col].copy()
    return Phi, y


# ─── Fitness evaluation ─────────────────────────────────────────────────────

class NarxEvaluator:
    """
    Pre-builds full candidate matrices for train/val/test once;
    individual chromosome evaluations are fast column selections + OLS.
    """

    def __init__(self, data: np.ndarray, candidates, cfg: NarxConfig):
        self.cfg        = cfg
        self.candidates = candidates
        n               = data.shape[0]
        t_end, v_end    = split_indices(n, cfg)
        max_lag         = max(cfg.n_y, cfg.n_u)

        # Effective start (skip first max_lag rows — no history available)
        tr_start = max_lag
        self.Phi_tr, self.y_tr = build_full_candidate_matrix(data, candidates, cfg, tr_start, t_end)
        self.Phi_va, self.y_va = build_full_candidate_matrix(data, candidates, cfg, t_end,   v_end)
        self.Phi_te, self.y_te = build_full_candidate_matrix(data, candidates, cfg, v_end,   n)

    def evaluate(self, mask: np.ndarray):
        """
        Evaluate fitness for a binary mask over candidates.
        Returns (fitness, metrics_dict).
        fitness = RMSE_val + alpha*BIC/n_tr + gamma*n_terms  (lower = better)
        """
        selected = np.flatnonzero(mask)
        n_terms  = int(selected.sum()) if mask.dtype == bool else len(selected)

        if n_terms == 0:
            bad = {"r2_train": 0.0, "r2_val": 0.0, "r2_test": 0.0,
                   "rmse_train": 1e6, "rmse_val": 1e6, "rmse_test": 1e6,
                   "n_terms": 0, "bic": 1e6, "aic": 1e6}
            return 1e6, bad

        # Column selection (add intercept column)
        ones = np.ones((self.Phi_tr.shape[0], 1))
        X_tr = np.hstack([ones, self.Phi_tr[:, selected]])

        try:
            theta, _, _, _ = np.linalg.lstsq(X_tr, self.y_tr, rcond=None)
        except np.linalg.LinAlgError:
            bad = {"r2_train": 0.0, "r2_val": 0.0, "r2_test": 0.0,
                   "rmse_train": 1e6, "rmse_val": 1e6, "rmse_test": 1e6,
                   "n_terms": n_terms, "bic": 1e6, "aic": 1e6}
            return 1e6, bad

        def metrics(Phi, y):
            X = np.hstack([np.ones((Phi.shape[0], 1)), Phi[:, selected]])
            yh = X @ theta
            sse = float(np.sum((y - yh) ** 2))
            ss  = float(np.sum((y - y.mean()) ** 2))
            n   = len(y)
            rmse = float(np.sqrt(max(sse / n, 0.0)))
            r2   = float(1.0 - sse / max(ss, 1e-12))
            bic  = float(n * np.log(max(sse / n, 1e-12)) + (n_terms + 1) * np.log(n))
            aic  = float(n * np.log(max(sse / n, 1e-12)) + 2 * (n_terms + 1))
            return rmse, r2, sse, bic, aic

        rmse_tr, r2_tr, sse_tr, bic_tr, aic_tr = metrics(self.Phi_tr, self.y_tr)
        rmse_va, r2_va, _,      bic_va, aic_va = metrics(self.Phi_va, self.y_va)
        rmse_te, r2_te, _,      _,      _      = metrics(self.Phi_te, self.y_te)

        n_tr    = len(self.y_tr)
        fitness = (rmse_va
                   + self.cfg.alpha_bic * bic_tr / n_tr
                   + self.cfg.gamma_cplx * n_terms)

        return float(fitness), {
            "r2_train":  r2_tr,
            "r2_val":    r2_va,
            "r2_test":   r2_te,
            "rmse_train": rmse_tr,
            "rmse_val":   rmse_va,
            "rmse_test":  rmse_te,
            "n_terms":    n_terms,
            "bic":        bic_tr,
            "aic":        aic_tr,
        }


# ─── Result I/O ─────────────────────────────────────────────────────────────

def save_run_result(path: str, run_id: int, seed: int, method: str,
                    elapsed_s: float, final_gen: int, metrics: dict,
                    fitness_history: list, config: dict):
    """Save a single run result JSON (compatible with analyze_batch.py)."""
    result = {
        "run_id":         run_id,
        "seed":           seed,
        "method":         method,
        "timestamp":      time.strftime("%Y-%m-%dT%H:%M:%S"),
        "elapsed_s":      round(elapsed_s, 2),
        "final_gen":      final_gen,
        "final_state":    "completed",
        "r2_train":       metrics.get("r2_train"),
        "r2_val":         metrics.get("r2_val"),
        "r2_test":        metrics.get("r2_test"),
        "rmse_train":     metrics.get("rmse_train"),
        "rmse_val":       metrics.get("rmse_val"),
        "rmse_test":      metrics.get("rmse_test"),
        "n_terms":        metrics.get("n_terms"),
        "bic":            metrics.get("bic"),
        "aic":            metrics.get("aic"),
        "config":         config,
        "fitness_history": fitness_history,  # list of [gen, fitness]
    }
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(result, f, indent=2)


def save_summary(output_dir: str, method: str, runs: list, config: dict):
    """Save summary.json for all runs of a method."""
    summary = {
        "method":    method,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "num_runs":  len(runs),
        "ok_runs":   sum(1 for r in runs if r.get("final_state") == "completed"),
        "config":    config,
        "runs":      runs,
    }
    path = os.path.join(output_dir, "summary.json")
    with open(path, "w") as f:
        json.dump(summary, f, indent=2)
    return path
