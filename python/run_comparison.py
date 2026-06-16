"""
run_comparison.py — Runs all baseline methods (DE Classic, JADE, GA, PSO)
on the same dataset used by AEGIS, with the same protocol.

Usage:
  python run_comparison.py --data <csv> [options]

Output:
  <output>/<method>/run_NN.json  per run
  <output>/<method>/summary.json per method
  <output>/comparison_table.json aggregated comparison table

Example:
  python run_comparison.py --data ../data/WH_estimation_uy.csv --runs 10
  python run_comparison.py --data data.csv --methods de jade ga pso --runs 5
"""

from __future__ import annotations
import argparse
import json
import os
import sys
import time

import numpy as np

from narx_utils import (
    NarxConfig, NarxEvaluator,
    load_csv, normalize_minmax, split_indices,
    enumerate_candidates,
    save_run_result, save_summary,
)
from baseline_methods import run_de_classic, run_jade, run_ga, run_pso

try:
    from tqdm import tqdm
    _HAS_TQDM = True
except ImportError:
    _HAS_TQDM = False


# ─── Method registry ────────────────────────────────────────────────────────

METHODS = {
    "de":   ("DE-Classic", run_de_classic),
    "jade": ("JADE",       run_jade),
    "ga":   ("GA",         run_ga),
    "pso":  ("PSO",        run_pso),
}


# ─── Statistics helper ──────────────────────────────────────────────────────

def compute_stats(values: list) -> dict:
    arr = np.array([v for v in values if v is not None], dtype=np.float64)
    if arr.size == 0:
        return {"mean": None, "std": None, "min": None, "max": None, "n": 0}
    return {
        "mean": float(arr.mean()),
        "std":  float(arr.std(ddof=1)) if arr.size > 1 else 0.0,
        "min":  float(arr.min()),
        "max":  float(arr.max()),
        "n":    int(arr.size),
    }


def summarize_runs(runs: list) -> dict:
    return {
        "r2_test":   compute_stats([r.get("r2_test")   for r in runs]),
        "rmse_test": compute_stats([r.get("rmse_test") for r in runs]),
        "r2_val":    compute_stats([r.get("r2_val")    for r in runs]),
        "final_gen": compute_stats([r.get("final_gen") for r in runs]),
        "elapsed_s": compute_stats([r.get("elapsed_s") for r in runs]),
    }


# ─── Run one method ─────────────────────────────────────────────────────────

def run_method(
    method_key: str,
    data_path:  str,
    output_dir: str,
    num_runs:   int,
    seed_start: int,
    cfg:        NarxConfig,
    runner_kwargs: dict,
    verbose:    bool,
):
    method_name, runner_fn = METHODS[method_key]
    method_dir = os.path.join(output_dir, method_key)
    os.makedirs(method_dir, exist_ok=True)

    print(f"\n{'='*56}")
    print(f"  Method : {method_name}")
    print(f"  Runs   : {num_runs}  (seeds {seed_start}–{seed_start+num_runs-1})")
    print(f"  Output : {method_dir}/")
    print(f"{'='*56}")

    # Load and preprocess data ONCE
    raw  = load_csv(data_path)
    n    = raw.shape[0]
    t_end, _ = split_indices(n, cfg)
    data, _, _ = normalize_minmax(raw, t_end)

    candidates, labels = enumerate_candidates(data.shape[1], cfg)
    n_cands = len(candidates)
    evaluator = NarxEvaluator(data, candidates, cfg)

    print(f"  Data   : {raw.shape[0]} rows × {raw.shape[1]} cols  →  {n_cands} candidate regressors")

    run_records = []
    runner_config = {
        "n_y":       cfg.n_y,
        "n_u":       cfg.n_u,
        "max_degree": cfg.max_degree,
        "output_col": cfg.output_col,
        **runner_kwargs,
    }

    iterable = range(num_runs)
    if _HAS_TQDM:
        iterable = tqdm(iterable, desc=method_name, unit="run")

    for run_id in iterable:
        seed = seed_start + run_id
        if _HAS_TQDM:
            iterable.set_postfix(seed=seed)
        else:
            print(f"  ── Run {run_id+1}/{num_runs}  seed={seed}  {time.strftime('%H:%M:%S')} ──")

        t0 = time.time()
        _, best_fit, metrics, history = runner_fn(
            evaluator, n_cands,
            seed=seed, verbose=verbose,
            **runner_kwargs,
        )
        elapsed_s = time.time() - t0

        if not _HAS_TQDM:
            print(f"     Done: fitness={best_fit:.4f}  R²_test={metrics.get('r2_test', '?'):.4f}"
                  f"  ({elapsed_s:.1f}s)")

        run_path = os.path.join(method_dir, f"run_{run_id:02d}.json")
        save_run_result(
            path=run_path, run_id=run_id, seed=seed,
            method=method_name, elapsed_s=elapsed_s,
            final_gen=len(history) - 1,
            metrics=metrics,
            fitness_history=history,
            config={**runner_config, "data_file": data_path},
        )

        run_records.append({
            "run_id":    run_id,
            "seed":      seed,
            "elapsed_s": round(elapsed_s, 2),
            "final_gen": len(history) - 1,
            "final_state": "completed",
            **metrics,
        })

    summary_path = save_summary(method_dir, method_name, run_records, runner_config)
    stats = summarize_runs(run_records)
    print(f"\n  ── {method_name} summary ──")
    print(f"     R² test  : {stats['r2_test']['mean']:.4f} ± {stats['r2_test']['std']:.4f}")
    print(f"     RMSE test: {stats['rmse_test']['mean']:.4f} ± {stats['rmse_test']['std']:.4f}")
    print(f"     Saved    : {summary_path}")

    return method_name, stats, run_records


# ─── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Run NARX baseline methods and compare against AEGIS results."
    )
    parser.add_argument("--data",       required=True,  help="CSV/TSV input file")
    parser.add_argument("--output",     default="comparison_results",
                        help="Output root directory (default: comparison_results/)")
    parser.add_argument("--methods",    nargs="+", default=list(METHODS.keys()),
                        choices=list(METHODS.keys()),
                        help="Methods to run (default: all)")
    parser.add_argument("--runs",       type=int,   default=10,   help="Runs per method")
    parser.add_argument("--seed-start", type=int,   default=0,    help="First seed")
    parser.add_argument("--max-gen",    type=int,   default=5000, help="Max generations")
    parser.add_argument("--pop-size",   type=int,   default=100,  help="Population size")
    parser.add_argument("--n-y",        type=int,   default=9,    help="Output lags (n_y)")
    parser.add_argument("--n-u",        type=int,   default=9,    help="Input  lags (n_u)")
    parser.add_argument("--degree",     type=int,   default=2,    help="Max polynomial degree")
    parser.add_argument("--output-col", type=int,   default=-1,   help="Output column index")
    parser.add_argument("--aegis-results", default=None,
                        help="Path to AEGIS summary.json for inclusion in comparison table")
    parser.add_argument("--verbose",    action="store_true")
    args = parser.parse_args()

    if not os.path.isfile(args.data):
        print(f"[error] Data file not found: {args.data}")
        sys.exit(1)

    os.makedirs(args.output, exist_ok=True)

    cfg = NarxConfig(
        n_y=args.n_y,
        n_u=args.n_u,
        max_degree=args.degree,
        output_col=args.output_col,
    )

    runner_kwargs = {
        "pop_size": args.pop_size,
        "max_gen":  args.max_gen,
    }

    print(f"\nAEGIS Python Comparison Runner")
    print(f"  Data    : {args.data}")
    print(f"  Methods : {', '.join(args.methods)}")
    print(f"  Runs    : {args.runs} × {len(args.methods)} = {args.runs * len(args.methods)} total")
    print(f"  n_y={cfg.n_y}  n_u={cfg.n_u}  degree={cfg.max_degree}  pop={args.pop_size}  max_gen={args.max_gen}")

    comparison = {}

    # Optionally include AEGIS results from an existing summary.json
    if args.aegis_results and os.path.isfile(args.aegis_results):
        with open(args.aegis_results) as f:
            aegis_data = json.load(f)
        runs = aegis_data.get("runs", [])
        comparison["AEGIS"] = summarize_runs(runs)
        print(f"\n  Loaded AEGIS results: {len(runs)} runs from {args.aegis_results}")

    # Run each baseline method
    for method_key in args.methods:
        method_name, stats, _ = run_method(
            method_key=method_key,
            data_path=args.data,
            output_dir=args.output,
            num_runs=args.runs,
            seed_start=args.seed_start,
            cfg=cfg,
            runner_kwargs=runner_kwargs,
            verbose=args.verbose,
        )
        comparison[method_name] = stats

    # Save comparison table JSON
    table_path = os.path.join(args.output, "comparison_table.json")
    with open(table_path, "w") as f:
        json.dump({
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "data_file": args.data,
            "num_runs":  args.runs,
            "config": {
                "n_y": cfg.n_y, "n_u": cfg.n_u,
                "max_degree": cfg.max_degree,
                "pop_size": args.pop_size,
                "max_gen":  args.max_gen,
            },
            "results": comparison,
        }, f, indent=2)

    # Print final comparison table
    print(f"\n\n{'─'*70}")
    print(f"  {'Method':<12}  {'R² test (mean±std)':<22}  {'RMSE test (mean±std)':<22}  {'Ger. média'}")
    print(f"{'─'*70}")
    for method, s in comparison.items():
        r2  = s["r2_test"]
        rm  = s["rmse_test"]
        gen = s["final_gen"]
        r2_str  = f"{r2['mean']:.4f} ± {r2['std']:.4f}"   if r2["mean"]  is not None else "N/A"
        rm_str  = f"{rm['mean']:.4f} ± {rm['std']:.4f}"   if rm["mean"]  is not None else "N/A"
        gen_str = f"{gen['mean']:.0f}"                     if gen["mean"] is not None else "N/A"
        print(f"  {method:<12}  {r2_str:<22}  {rm_str:<22}  {gen_str}")
    print(f"{'─'*70}")
    print(f"\n  Comparison table saved: {table_path}")
    print(f"  Run generate_figures.py --results {args.output} to produce publication plots.")


if __name__ == "__main__":
    main()
