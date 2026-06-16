"""
generate_figures.py — Publication-quality figures for AEGIS paper.

Generates:
  Fig 1 — Convergence curve (fitness vs generation, phase markers)
  Fig 2 — Multi-run R² boxplot  (AEGIS vs all baseline methods)
  Fig 3 — Method comparison bar chart (R² mean ± std)
  Fig 4 — Predicted vs actual output (best AEGIS run, test partition)
  Fig 5 — ERR contribution bar chart (from best AEGIS run)
  Fig 6 — Convergence comparison (best run of each method, same axes)

Usage:
  python generate_figures.py --aegis <dir> [--baselines <dir>] [--out <dir>]

Examples:
  python generate_figures.py --aegis ../aegis_results/
  python generate_figures.py --aegis results/wh/ --baselines comparison_results/ --out figures/
"""

from __future__ import annotations
import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")  # non-interactive backend for file output
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from matplotlib.lines import Line2D

# Optional seaborn for nicer defaults
try:
    import seaborn as sns
    sns.set_theme(style="darkgrid", context="paper", font_scale=1.2)
    _HAS_SNS = True
except ImportError:
    _HAS_SNS = False
    plt.rcParams.update({
        "figure.dpi": 150,
        "axes.grid": True,
        "grid.alpha": 0.3,
        "font.size": 11,
    })

# ── Palette ─────────────────────────────────────────────────────────────────
COLORS = {
    "AEGIS":      "#5EC4D4",   # cyan
    "DE-Classic": "#F87171",   # red
    "JADE":       "#FBBF24",   # amber
    "GA":         "#A78BFA",   # purple
    "PSO":        "#4ADE80",   # green
}
PHASE_COLORS = ["#60A5FA", "#A78BFA", "#FBBF24", "#4ADE80"]
PHASE_NAMES  = ["Fase 0\nStructural\nExploration",
                "Fase 1\nNonlinear\nExpansion",
                "Fase 2\nParsimony\nValidation",
                "Fase 3\nLocal\nRefinement"]

DPI    = 300
FMT    = ["pdf", "png"]  # save both


# ─── I/O helpers ─────────────────────────────────────────────────────────────

def _save(fig, out_dir: str, stem: str):
    os.makedirs(out_dir, exist_ok=True)
    for ext in FMT:
        path = os.path.join(out_dir, f"{stem}.{ext}")
        fig.savefig(path, dpi=DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {os.path.join(out_dir, stem)}.{{pdf,png}}")


def _load_runs(directory: str) -> list[dict]:
    p = Path(directory)
    files = sorted(p.glob("run_*.json"))
    if files:
        return [json.loads(f.read_text()) for f in files]
    summary = p / "summary.json"
    if summary.exists():
        data = json.loads(summary.read_text())
        return data.get("runs", [])
    return []


def _load_method_dirs(baselines_dir: str) -> dict[str, list[dict]]:
    """Load all method subdirectories from a comparison results folder."""
    result = {}
    p = Path(baselines_dir)
    for d in sorted(p.iterdir()):
        if d.is_dir() and not d.name.startswith("."):
            runs = _load_runs(str(d))
            if runs:
                method = runs[0].get("method", d.name)
                result[method] = runs
    return result


def _extract(runs: list, key: str) -> list:
    vals = []
    for r in runs:
        v = r.get(key)
        if v is None:
            bm = r.get("best_model", {})
            if isinstance(bm, dict):
                v = bm.get(key)
        if v is not None:
            vals.append(float(v))
    return vals


def _hist_points(run: dict) -> tuple[list, list]:
    """Return (gens, fitnesses) from a run's fitness_history."""
    hist = run.get("fitness_history", [])
    gens, fits = [], []
    for pt in hist:
        if isinstance(pt, (list, tuple)) and len(pt) >= 2:
            gens.append(int(pt[0]));  fits.append(float(pt[1]))
        elif isinstance(pt, dict):
            gens.append(int(pt.get("gen", 0)))
            fits.append(float(pt.get("fit", pt.get("fitness", 0))))
    return gens, fits


def _best_run(runs: list) -> dict:
    """Return run with highest r2_test."""
    best = None
    best_r2 = -np.inf
    for r in runs:
        v = r.get("r2_test")
        if v is not None and float(v) > best_r2:
            best_r2 = float(v)
            best = r
    return best or (runs[0] if runs else {})


# ─── Fig 1 — Convergence curve ───────────────────────────────────────────────

def fig_convergence(aegis_runs: list, out_dir: str,
                    phase_boundaries: list | None = None):
    """
    Fitness vs generation for all AEGIS runs.
    Highlighted: best run (cyan). Others: grey translucent.
    Vertical dashed lines mark phase transitions (if provided).
    """
    fig, ax = plt.subplots(figsize=(9, 4.5))

    best = _best_run(aegis_runs)

    for run in aegis_runs:
        gens, fits = _hist_points(run)
        if not gens:
            continue
        is_best = run is best
        ax.plot(gens, fits,
                color=COLORS["AEGIS"] if is_best else "#555555",
                alpha=1.0 if is_best else 0.25,
                linewidth=1.8 if is_best else 0.7,
                zorder=5 if is_best else 1)

    # Phase boundary markers (optional)
    if phase_boundaries:
        for i, (ph_gen, ph_name) in enumerate(zip(phase_boundaries, PHASE_NAMES)):
            ax.axvline(ph_gen, color=PHASE_COLORS[i], linestyle="--",
                       linewidth=1.0, alpha=0.7, zorder=3)
            ax.text(ph_gen + 10, ax.get_ylim()[1] * 0.97 if ax.get_ylim()[1] != 1 else -0.01,
                    ph_name, fontsize=7, color=PHASE_COLORS[i],
                    va="top", rotation=90, alpha=0.85)

    ax.set_xlabel("Geração")
    ax.set_ylabel("Fitness composta (↓ melhor)")
    ax.set_title("AEGIS — Curva de Convergência (todas as execuções)")

    legend_els = [
        Line2D([0], [0], color=COLORS["AEGIS"],  linewidth=2, label="Melhor execução"),
        Line2D([0], [0], color="#555555",         linewidth=0.7, alpha=0.5, label="Demais execuções"),
    ]
    if phase_boundaries:
        for i, nm in enumerate(PHASE_NAMES):
            legend_els.append(Line2D([0], [0], color=PHASE_COLORS[i],
                                     linestyle="--", linewidth=1, label=nm.replace("\n", " ")))
    ax.legend(handles=legend_els, fontsize=8, loc="upper right")
    fig.tight_layout()
    _save(fig, out_dir, "fig1_convergence")


# ─── Fig 2 — R² boxplot ──────────────────────────────────────────────────────

def fig_r2_boxplot(all_methods: dict[str, list], out_dir: str):
    """Boxplot of R² test across runs, one box per method."""
    labels, data = [], []
    for method, runs in all_methods.items():
        vals = _extract(runs, "r2_test")
        if vals:
            labels.append(method)
            data.append(vals)

    if not labels:
        print("  [fig2] No R² data found.")
        return

    fig, ax = plt.subplots(figsize=(max(6, 2 * len(labels)), 5))
    bp = ax.boxplot(data, patch_artist=True, notch=False,
                    medianprops=dict(color="white", linewidth=2))

    for patch, label in zip(bp["boxes"], labels):
        patch.set_facecolor(COLORS.get(label, "#888888"))
        patch.set_alpha(0.8)

    ax.set_xticks(range(1, len(labels) + 1))
    ax.set_xticklabels(labels)
    ax.set_ylabel("R² (conjunto de teste)")
    ax.set_title("Comparação de Métodos — R² Teste")
    ax.yaxis.set_minor_locator(ticker.AutoMinorLocator())

    # Add mean markers
    for i, vals in enumerate(data, start=1):
        ax.scatter(i, np.mean(vals), marker="D", color="white",
                   s=30, zorder=5, linewidths=0.5, edgecolors="black")

    fig.tight_layout()
    _save(fig, out_dir, "fig2_r2_boxplot")


# ─── Fig 3 — Bar chart (mean ± std) ─────────────────────────────────────────

def fig_comparison_bar(all_methods: dict[str, list], out_dir: str):
    """Horizontal bar chart: R² mean ± std for each method."""
    labels, means, stds = [], [], []
    for method, runs in all_methods.items():
        vals = _extract(runs, "r2_test")
        if vals:
            labels.append(method)
            means.append(float(np.mean(vals)))
            stds.append(float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0)

    if not labels:
        return

    n   = len(labels)
    fig, ax = plt.subplots(figsize=(8, max(3, 0.7 * n)))
    y   = np.arange(n)
    bars = ax.barh(y, means, xerr=stds, height=0.5,
                   color=[COLORS.get(l, "#888888") for l in labels],
                   alpha=0.85, error_kw=dict(elinewidth=1.5, capsize=4))

    ax.set_yticks(y)
    ax.set_yticklabels(labels)
    ax.set_xlabel("R² (teste) — média ± desvio padrão")
    ax.set_title("Comparação de Métodos — R² Teste")
    ax.set_xlim(max(0, min(means) - max(stds) * 3), 1.02)
    ax.invert_yaxis()

    for i, (m, s) in enumerate(zip(means, stds)):
        ax.text(m + s + 0.002, i, f"{m:.4f}", va="center", fontsize=9)

    fig.tight_layout()
    _save(fig, out_dir, "fig3_comparison_bar")


# ─── Fig 4 — Predicted vs actual ────────────────────────────────────────────

def fig_predicted_vs_actual(aegis_runs: list, out_dir: str,
                             data_path: str | None = None):
    """
    Plots predicted vs actual output for the best AEGIS run.
    Uses data from the run JSON if stored; otherwise loads from data_path.

    If no prediction data is available in the JSON, shows R² annotation only.
    """
    best = _best_run(aegis_runs)
    bm   = best.get("best_model", {})

    y_actual    = bm.get("y_test_actual")
    y_predicted = bm.get("y_test_predicted")

    fig, axes = plt.subplots(2, 1, figsize=(11, 6), sharex=True)
    ax_ts, ax_err = axes

    r2    = best.get("r2_test") or bm.get("r2_test")
    rmse  = best.get("rmse_test") or bm.get("rmse_test")
    seed  = best.get("seed", "?")
    gen   = best.get("final_gen", "?")

    if y_actual and y_predicted:
        y_act = np.array(y_actual)
        y_prd = np.array(y_predicted)
        ax_ts.plot(y_act, label="Real $y(k)$",      color="#AAAAAA", linewidth=0.8, alpha=0.9)
        ax_ts.plot(y_prd, label="Previsto $\\hat{y}(k)$", color=COLORS["AEGIS"], linewidth=1.2, alpha=0.9)
        residual = y_act - y_prd
        ax_err.plot(residual, color="#F87171", linewidth=0.7, alpha=0.8)
        ax_err.axhline(0, color="white", linewidth=0.5, linestyle="--")
        ax_err.set_ylabel("Resíduo $e(k)$")
    else:
        # No time-series data in JSON; show placeholder with annotation
        ax_ts.text(0.5, 0.5,
                   "Dados de predição não incluídos no JSON.\n"
                   "Exporte 'y_test_actual' e 'y_test_predicted'\n"
                   "pelo botão Export JSON na tela Results do AEGIS.",
                   transform=ax_ts.transAxes, ha="center", va="center",
                   fontsize=11, color="#AAAAAA",
                   bbox=dict(boxstyle="round", fc="#1C1C24", ec="#444"))
        ax_err.text(0.5, 0.5, "(sem dados)", transform=ax_err.transAxes,
                    ha="center", va="center", fontsize=11, color="#AAAAAA")

    title = f"AEGIS — Saída Prevista vs Real (melhor execução, seed={seed}, gen={gen})"
    if r2 is not None:
        title += f"\nR² = {float(r2):.6f}"
        if rmse is not None:
            title += f"   RMSE = {float(rmse):.6f}"
    ax_ts.set_title(title)
    ax_ts.set_ylabel("Amplitude normalizada")
    ax_ts.legend(loc="upper right", fontsize=9)
    ax_err.set_xlabel("Amostra (conjunto de teste)")

    fig.tight_layout()
    _save(fig, out_dir, "fig4_predicted_vs_actual")


# ─── Fig 5 — ERR contribution ────────────────────────────────────────────────

def fig_err_contribution(aegis_runs: list, out_dir: str):
    """
    Bar chart of ERR contributions from the best AEGIS run.
    Reads from best_model.err_contributions (list of {label, err}).
    """
    best = _best_run(aegis_runs)
    bm   = best.get("best_model", {})
    err_data = bm.get("err_contributions") or bm.get("err")

    fig, ax = plt.subplots(figsize=(9, 5))

    if err_data and isinstance(err_data, list):
        # Sort descending
        try:
            pairs = sorted(err_data, key=lambda x: x.get("err", x[1] if isinstance(x, list) else 0), reverse=True)
            labels = [p.get("label", p[0] if isinstance(p, list) else f"R{i}") for i, p in enumerate(pairs)]
            values = [float(p.get("err", p[1] if isinstance(p, list) else 0)) * 100 for p in pairs]
            n = len(labels)
            colors = plt.cm.plasma(np.linspace(0.2, 0.9, n))
            ax.barh(range(n), values, color=colors, alpha=0.85)
            ax.set_yticks(range(n))
            ax.set_yticklabels(labels, fontsize=9)
            ax.invert_yaxis()
            ax.set_xlabel("ERR (%)")
            ax.set_title("Contribuição dos Regressores — Error Reduction Ratio")
            cum = np.cumsum(values)
            for i, (v, c) in enumerate(zip(values, cum)):
                ax.text(v + 0.2, i, f"{v:.2f}%  [Σ={c:.1f}%]", va="center", fontsize=8)
        except Exception as e:
            ax.text(0.5, 0.5, f"Erro ao parsear ERR: {e}",
                    transform=ax.transAxes, ha="center", va="center")
    else:
        ax.text(0.5, 0.5,
                "Dados ERR não encontrados no JSON.\n"
                "Exporte pelo botão Export JSON do AEGIS\n"
                "(campo 'err_contributions' em best_model).",
                transform=ax.transAxes, ha="center", va="center",
                fontsize=11, color="#AAAAAA",
                bbox=dict(boxstyle="round", fc="#1C1C24", ec="#444"))
        ax.set_title("ERR — Contribuição dos Regressores")

    fig.tight_layout()
    _save(fig, out_dir, "fig5_err_contribution")


# ─── Fig 6 — Convergence comparison ─────────────────────────────────────────

def fig_convergence_comparison(all_methods: dict[str, list], out_dir: str):
    """Best convergence curve of each method on the same axes."""
    fig, ax = plt.subplots(figsize=(10, 5))

    for method, runs in all_methods.items():
        best = _best_run(runs)
        gens, fits = _hist_points(best)
        if not gens:
            continue
        color = COLORS.get(method, "#888888")
        ax.plot(gens, fits, label=method, color=color,
                linewidth=1.8, alpha=0.9)

    ax.set_xlabel("Geração / Iteração")
    ax.set_ylabel("Fitness composta (↓ melhor)")
    ax.set_title("Comparação de Convergência — Melhor Execução por Método")
    ax.legend(loc="upper right")
    fig.tight_layout()
    _save(fig, out_dir, "fig6_convergence_comparison")


# ─── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Generate publication figures from AEGIS batch and baseline results."
    )
    parser.add_argument("--aegis",      required=True,
                        help="Directory with AEGIS run_*.json files")
    parser.add_argument("--baselines",  default=None,
                        help="Directory with baseline method subdirectories (from run_comparison.py)")
    parser.add_argument("--out",        default="figures",
                        help="Output directory for figures (default: figures/)")
    parser.add_argument("--phases",     nargs="*", type=int,
                        help="Generation numbers for phase boundaries (e.g. --phases 400 900 1800)")
    parser.add_argument("--data",       default=None,
                        help="Optional CSV data file (for Fig 4 if not in JSON)")
    args = parser.parse_args()

    # Load AEGIS runs
    aegis_runs = _load_runs(args.aegis)
    if not aegis_runs:
        print(f"[error] No AEGIS runs found in: {args.aegis}")
        sys.exit(1)
    print(f"Loaded {len(aegis_runs)} AEGIS runs from {args.aegis}")

    # Collect all methods for comparison figures
    all_methods: dict[str, list] = {"AEGIS": aegis_runs}

    if args.baselines and os.path.isdir(args.baselines):
        baseline_methods = _load_method_dirs(args.baselines)
        all_methods.update(baseline_methods)
        print(f"Loaded baseline methods: {list(baseline_methods.keys())}")

    # Also check for comparison_table.json in baselines dir
    comp_table = None
    if args.baselines:
        ct_path = os.path.join(args.baselines, "comparison_table.json")
        if os.path.isfile(ct_path):
            with open(ct_path) as f:
                comp_table = json.load(f)

    print(f"\nGenerating figures → {args.out}/\n")

    # Fig 1 — AEGIS convergence
    phase_bounds = list(zip(args.phases, PHASE_NAMES)) if args.phases else None
    fig_convergence(aegis_runs, args.out, phase_bounds)

    # Fig 2 — R² boxplot (all methods)
    fig_r2_boxplot(all_methods, args.out)

    # Fig 3 — Comparison bar chart
    fig_comparison_bar(all_methods, args.out)

    # Fig 4 — Predicted vs actual (AEGIS best run)
    fig_predicted_vs_actual(aegis_runs, args.out, data_path=args.data)

    # Fig 5 — ERR contribution (AEGIS best run)
    fig_err_contribution(aegis_runs, args.out)

    # Fig 6 — Convergence comparison (all methods)
    if len(all_methods) > 1:
        fig_convergence_comparison(all_methods, args.out)
    else:
        print("  [fig6] Skipped (only one method loaded; run with --baselines to compare).")

    print(f"\nAll figures saved to: {os.path.abspath(args.out)}/")
    print("  fig1_convergence.*          — Curva de convergência AEGIS")
    print("  fig2_r2_boxplot.*           — Boxplot R² todos os métodos")
    print("  fig3_comparison_bar.*       — Barras R² média ± desvio")
    print("  fig4_predicted_vs_actual.*  — Saída prevista vs real")
    print("  fig5_err_contribution.*     — Contribuição ERR dos regressores")
    print("  fig6_convergence_comparison.*— Convergência comparativa")


if __name__ == "__main__":
    main()
