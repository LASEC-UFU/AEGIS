# How to Use AEGIS

> **Step-by-step guide to identify NARX models using AEGIS.**

---

## 1. Loading Data

1. Navigate to the **Data** tab in the left navigation rail (or bottom bar on mobile).
2. Click **Load File** and select a `.csv`, `.tsv`, or space-separated text file containing your time-series data.
3. Toggle **Header row** if your file has a column name row — AEGIS will skip it automatically.
4. Click each column header in the preview table to assign it as **Input** ($u$) or **Output** ($y$). At least one input and one output must be assigned before the engine can start.

### Data Requirements

| Requirement | Description |
|-------------|-------------|
| **Format** | CSV, TSV, space-separated, or semicolon-separated |
| **Columns** | At least 2: one input $u(k)$ and one output $y(k)$ |
| **Header** | Optional — the loader auto-detects numeric rows |
| **Size** | Recommended: 200–10,000 samples |
| **Normalization** | Performed automatically before identification |

The data is split sequentially into **70% training · 15% validation · 15% test** after loading.

---

## 2. Running the Evolution

1. Go to the **Evolution** tab.
2. Click **Start** to initialize and begin the Differential Evolution optimization.
3. The algorithm evolves populations across multiple islands to find the best NARX model structure.
4. Use **Pause** / **Resume** to interrupt without losing progress. Use **Stop** to end early.

The status bar shows the current generation, best fitness (BIC), $R^2$, and elapsed time.

### Engine Selection (automatic)

| Platform | Engine used |
|----------|-------------|
| Windows (with `aegis_core.dll`) | C++ multi-threaded — faster, more diagnostics |
| Windows (without DLL) | Pure Dart fallback |
| Web / GitHub Pages | Pure Dart |

---

## 3. Monitoring with the Agent Dashboard

The **Agent** tab provides real-time insight into the evolutionary process.

### Indicator Grid

12 key indicators are shown with semantic colors (green = healthy, yellow = caution, red = problem):

| Indicator | What it means |
|-----------|---------------|
| **Best BIC** | Best composite fitness found (lower = better) |
| **RMSE Train / Val** | Training and validation errors |
| **$R^2$** | Coefficient of determination (1 = perfect fit) |
| **Stagnation** | Generations without improvement |
| **Diversity** | Population spread — low means premature convergence |
| **Success Rate** | Fraction of trial vectors accepted this generation |

### Tuning Sliders

12 parameters can be adjusted **live** while the engine is running:

| Parameter | Default | When to change |
|-----------|---------|----------------|
| `mutationFactor` $F$ | 0.5 | Increase if diversity drops or stagnation grows |
| `crossoverRate` $CR$ | 0.9 | Decrease if $CR$ approaches 1.0 with good diversity |
| `populationSize` $NP$ | 50 | Increase for harder problems (costs more per generation) |
| `elitismCount` | 2 | Increase to protect best solutions |
| `migrationInterval` | 20 | Decrease for faster island communication |
| `migrationRate` | 0.1 | Increase if islands stagnate independently |
| `maxRegressors` | 8 | Increase if RMSE is high and model seems too simple |
| `maxExponent` | 3 | Increase to allow more nonlinear terms |
| `maxDelay` | 20 | Set to the expected system memory (in samples) |
| `complexityPenalty` | 1.0 | Increase if overfitting; decrease if underfitting |
| `stagnationLimit` | 500 | Lower to stop sooner in clearly converged runs |
| `reinitializationRatio` | 0.1 | Increase to escape local optima |

Click the reset icon next to any slider to restore its default.

### Island Monitor

The bar chart at the bottom shows the best fitness per island. Islands with very similar bars indicate convergence; large spread indicates the archipelago is still exploring.

### LLM Agent (Windows only)

When `aegis_core.dll` is present and an Anthropic API key is configured, the **Claude agent** monitors the engine every 50 generations and may suggest parameter adjustments automatically. Suggestions appear in the tuning log and are applied immediately.

**Setup (Windows):**

```powershell
# Option A — environment variable (current session)
$env:ANTHROPIC_API_KEY = "sk-ant-..."

# Option B — file next to the executable
echo "sk-ant-..." > aegis.exe_folder\anthropic_api_key.txt
```

The agent suggests at most one parameter change per call and only when the engine shows signs of stagnation, overfitting, or loss of diversity. When the engine is healthy it replies `null` and makes no changes.

---

## 4. Viewing Results

Once the evolution completes (or after stopping), go to the **Results** tab:

1. **Model Equation** — The identified NARX expression with coefficients, e.g.:
   ```
   y_hat(k) = (0.8732·y(k-1) + 0.1241·u(k-1)²) / (1 + 0.0034·y(k-1)·u(k-2))
   ```
2. **Quality Metrics** — RMSE (train / validation / test), $R^2$, AIC, BIC, FPE, MDL, SSE
3. **ERR Table** — Each regressor ranked by its Error Reduction Ratio contribution
4. **Residual Autocorrelation** — Plot with 95% confidence bands ($\pm 1.96/\sqrt{n}$). Bars inside the bands indicate white-noise residuals (adequate model).
5. **Diagnostics** (C++ only) — Stability (BIBO), collinearity (VIF), overfitting / underfitting flags

---

## 5. Tips & Best Practices

- **Start with the defaults** — the engine is tuned for a broad range of systems; only adjust if the metrics suggest a problem.
- **Check diversity early** — if `phenotypicDiversity` collapses below 0.01 in the first 50 generations, increase `mutationFactor` or `migrationRate`.
- **Watch RMSE_val vs RMSE_train** — if the gap grows (overfitting), increase `complexityPenalty` or decrease `maxRegressors`.
- **Low $R^2$ after 200+ generations** — try increasing `maxRegressors`, `maxDelay`, or `maxExponent`.
- **On web** — the pure Dart engine is slower than the C++ build. For large datasets (> 2,000 samples) or long runs, use the Windows build.
- **On Windows** — the LLM agent can substitute for manual tuning. Just keep the API key configured and monitor its suggestions in the console log.

---

## 6. About / Technical Reference

The **About** screen renders the full `IDENTIFICATION_PROCESS.md` document, which covers:

- The complete identification pipeline with mathematical details
- C++ module descriptions (normalizer, QR solver, local refiner, diagnostics)
- The composite fitness function and all penalties
- FFI bridge design and WASM execution model
- LLM agent flow and API key security notes

Both screens support **dark/light mode** toggle (top-right icon) and are fully **selectable** for copy-paste.

---

<div align="center">

**AEGIS v2.0** · How to Use Guide

*For technical details, see the About section.*

</div>
