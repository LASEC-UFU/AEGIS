"""
analyze_batch.py — Statistical analysis of AEGIS batch results.

Loads run_NN.json files from an aegis_batch output directory,
computes descriptive statistics, and prints a formatted report.

Usage:
  python analyze_batch.py --results <dir> [--metric r2_test] [--export <csv>]

Examples:
  python analyze_batch.py --results ../aegis_results/
  python analyze_batch.py --results results/wh/ --export summary.csv
"""

from __future__ import annotations
import argparse
import csv
import json
import os
import sys
from pathlib import Path

import numpy as np


# ─── Load helpers ───────────────────────────────────────────────────────────

def load_runs(results_dir: str) -> list[dict]:
    """Load all run_NN.json files from a directory."""
    p = Path(results_dir)
    files = sorted(p.glob("run_*.json"))
    if not files:
        # Try summary.json if no individual files
        summary_path = p / "summary.json"
        if summary_path.exists():
            with open(summary_path) as f:
                data = json.load(f)
            return data.get("runs", [])
        print(f"[analyze] No run_*.json files found in {results_dir}")
        return []

    runs = []
    for fp in files:
        with open(fp) as f:
            runs.append(json.load(f))
    return runs


def extract_scalar(run: dict, key: str):
    """Extract a scalar metric from a run dict, handling nested best_model."""
    if key in run and run[key] is not None:
        return run[key]
    # Check best_model sub-dict
    bm = run.get("best_model", {})
    if isinstance(bm, dict) and key in bm and bm[key] is not None:
        return bm[key]
    return None


# ─── Statistics ─────────────────────────────────────────────────────────────

def stats(values: list) -> dict:
    arr = np.array([v for v in values if v is not None], dtype=np.float64)
    if arr.size == 0:
        return {"n": 0, "mean": None, "std": None, "min": None, "max": None,
                "median": None, "q25": None, "q75": None}
    q25, med, q75 = np.percentile(arr, [25, 50, 75])
    return {
        "n":      int(arr.size),
        "mean":   float(arr.mean()),
        "std":    float(arr.std(ddof=1)) if arr.size > 1 else 0.0,
        "min":    float(arr.min()),
        "max":    float(arr.max()),
        "median": float(med),
        "q25":    float(q25),
        "q75":    float(q75),
    }


def _fmt(v, decimals: int = 4) -> str:
    if v is None:
        return "N/A"
    return f"{v:.{decimals}f}"


def _fmt_stat(s: dict, decimals: int = 4) -> str:
    if s["mean"] is None:
        return "N/A"
    return f"{_fmt(s['mean'], decimals)} ± {_fmt(s['std'], decimals)}"


# ─── Convergence analysis ────────────────────────────────────────────────────

def convergence_stats(runs: list) -> dict:
    """Analyze at which generation the best run converged (10% of final value)."""
    conv_gens = []
    for run in runs:
        hist = run.get("fitness_history", [])
        if not hist:
            continue
        # hist is list of [gen, fitness] or {gen, fit}
        pts = []
        for pt in hist:
            if isinstance(pt, (list, tuple)) and len(pt) >= 2:
                pts.append((int(pt[0]), float(pt[1])))
            elif isinstance(pt, dict):
                pts.append((int(pt.get("gen", 0)), float(pt.get("fit", pt.get("fitness", 0)))))

        if not pts:
            continue

        final = pts[-1][1]
        # Find first generation within 10% of final
        threshold = final * 1.10 if final < 0 else final * 0.90
        for gen, fit in pts:
            if (final < 0 and fit <= threshold) or (final >= 0 and fit <= threshold):
                conv_gens.append(gen)
                break

    return stats(conv_gens)


# ─── Report ─────────────────────────────────────────────────────────────────

def print_report(runs: list, results_dir: str):
    n = len(runs)
    if n == 0:
        print("[analyze] No runs to analyze.")
        return

    method = runs[0].get("method", "Unknown")

    # Key metrics
    metrics_to_show = [
        ("r2_train",   "R² (treino)",     4),
        ("r2_val",     "R² (val)",        4),
        ("r2_test",    "R² (teste)",      4),
        ("rmse_train", "RMSE (treino)",   4),
        ("rmse_val",   "RMSE (val)",      4),
        ("rmse_test",  "RMSE (teste)",    4),
        ("n_terms",    "N termos",        1),
        ("final_gen",  "Ger. conv.",      0),
        ("elapsed_s",  "Tempo (s)",       1),
    ]

    print(f"\n{'═'*64}")
    print(f"  AEGIS Batch Analysis — {method}")
    print(f"  Diretório : {results_dir}")
    print(f"  Execuções : {n}")
    print(f"{'═'*64}\n")

    print(f"  {'Métrica':<20}  {'Média ± Desvio':<22}  {'Min':<10}  {'Max':<10}  {'Mediana'}")
    print(f"  {'─'*18}  {'─'*20}  {'─'*8}  {'─'*8}  {'─'*8}")

    stat_cache = {}
    for key, label, dec in metrics_to_show:
        vals = [extract_scalar(r, key) for r in runs]
        s    = stats(vals)
        stat_cache[key] = s
        print(f"  {label:<20}  {_fmt_stat(s, dec):<22}  "
              f"{_fmt(s['min'], dec):<10}  {_fmt(s['max'], dec):<10}  {_fmt(s['median'], dec)}")

    # Convergence speed
    conv = convergence_stats(runs)
    print(f"\n  Convergência (geração onde fitness ≈ final):")
    if conv["mean"] is not None:
        print(f"    Média  : {conv['mean']:.0f}")
        print(f"    Desvio : {conv['std']:.0f}")
        print(f"    Min    : {conv['min']:.0f}")
        print(f"    Max    : {conv['max']:.0f}")
    else:
        print("    [sem dados de histórico]")

    # Best run
    best_idx = None
    best_r2  = -np.inf
    for i, r in enumerate(runs):
        v = extract_scalar(r, "r2_test")
        if v is not None and v > best_r2:
            best_r2  = v
            best_idx = i

    if best_idx is not None:
        br = runs[best_idx]
        print(f"\n  Melhor execução: run #{br.get('run_id', best_idx)}  "
              f"seed={br.get('seed', '?')}")
        print(f"    R²_test  = {_fmt(extract_scalar(br, 'r2_test'), 6)}")
        print(f"    R²_train = {_fmt(extract_scalar(br, 'r2_train'), 6)}")
        print(f"    N termos = {extract_scalar(br, 'n_terms')}")
        print(f"    Max delay= {extract_scalar(br, 'max_delay')}")
        print(f"    Gen conv.= {br.get('final_gen', '?')}")
        print(f"    Tempo    = {_fmt(br.get('elapsed_s'), 1)}s")

    # Success rate (R² > 0.99)
    success = sum(1 for r in runs if (extract_scalar(r, "r2_test") or 0) > 0.99)
    print(f"\n  R²_test > 0.99 : {success}/{n} execuções ({100*success/n:.0f}%)")

    print(f"\n{'═'*64}\n")
    return stat_cache


# ─── Export CSV ─────────────────────────────────────────────────────────────

def export_csv(runs: list, csv_path: str):
    scalar_keys = [
        "run_id", "seed", "method", "elapsed_s", "final_gen",
        "r2_train", "r2_val", "r2_test",
        "rmse_train", "rmse_val", "rmse_test",
        "n_terms", "max_delay", "bic", "aic",
    ]
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=scalar_keys, extrasaction="ignore")
        writer.writeheader()
        for run in runs:
            row = {k: extract_scalar(run, k) for k in scalar_keys}
            writer.writerow(row)
    print(f"  Exported CSV: {csv_path}")


# ─── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Analyze AEGIS batch results and print statistics."
    )
    parser.add_argument("--results",   required=True,
                        help="Directory with run_NN.json files (output of aegis_batch)")
    parser.add_argument("--export",    default=None,
                        help="Optional path to save per-run CSV summary")
    parser.add_argument("--metric",    default="r2_test",
                        help="Primary metric for ranking (default: r2_test)")
    args = parser.parse_args()

    if not os.path.isdir(args.results):
        print(f"[error] Not a directory: {args.results}")
        sys.exit(1)

    runs = load_runs(args.results)
    if not runs:
        sys.exit(1)

    print_report(runs, args.results)

    if args.export:
        export_csv(runs, args.export)


if __name__ == "__main__":
    main()
