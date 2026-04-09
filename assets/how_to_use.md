# How to Use AEGIS

> **Step-by-step guide to identify NARX models using AEGIS.**

---

## 1. Loading Data

1. Navigate to the **Data** tab in the left navigation.
2. Click **Load File** and select a `.csv` file containing your input/output time-series data.
3. The expected format is columns separated by commas, with the first column as the input $u(k)$ and the second as the output $y(k)$.

<!-- ![Loading data](media/step_load_data.png) -->

### Data Requirements

| Requirement | Description |
|-------------|-------------|
| **Format** | CSV (comma-separated values) |
| **Columns** | At least 2 columns: input $u(k)$ and output $y(k)$ |
| **Header** | Optional — the loader auto-detects numeric rows |
| **Size** | Recommended: 500–10,000 samples |

---

## 2. Configuring the Model

After loading data, configure the NARX model parameters:

| Parameter | Description | Typical Range |
|-----------|-------------|---------------|
| **$n_y$** (Output lags) | Number of past output terms | 1–5 |
| **$n_u$** (Input lags) | Number of past input terms | 1–5 |
| **$\ell$** (Nonlinearity degree) | Polynomial degree of the model | 1–3 |

<!-- ![Model configuration](media/step_config_model.png) -->

---

## 3. Running the Evolution

1. Go to the **Evolution** tab.
2. Click **Start** to begin the Differential Evolution optimization.
3. The algorithm will evolve populations across multiple islands to find the best model structure.

<!-- ![Evolution running](media/step_evolution.png) -->

### Key Evolution Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Population size** | Individuals per island | 50 |
| **Number of islands** | Parallel populations | 4 |
| **Max generations** | Stopping criterion | 500 |
| **$F$** (Mutation factor) | DE scaling factor (JADE adaptive) | 0.5 (initial) |
| **$CR$** (Crossover rate) | Crossover probability (JADE adaptive) | 0.9 (initial) |

---

## 4. Monitoring with the Agent Dashboard

The **Agent** tab provides a real-time dashboard with 34 indicators:

- **Fitness charts** — Track best/mean/worst fitness per island
- **Diversity metrics** — Monitor population diversity to avoid premature convergence
- **Migration events** — Visualize individual exchange between islands
- **Tunable parameters** — Adjust 12 parameters live during execution

<!-- ![Agent dashboard](media/step_agent_dashboard.png) -->

---

## 5. Viewing Results

Once the evolution completes, go to the **Results** tab:

1. **Best Model** — The identified NARX polynomial with coefficients
2. **Validation Plot** — Predicted vs. measured output on validation data
3. **Error Metrics** — MSE, RMSE, and NRMSE on both training and validation sets
4. **Model Terms** — Selected regressors ranked by ERR contribution

<!-- ![Results](media/step_results.png) -->

---

## 6. Tips & Best Practices

- **Normalize your data** before loading for better convergence
- **Start with low nonlinearity** ($\ell = 1$ or $2$) and increase if needed
- **Watch diversity metrics** — if diversity drops too fast, increase mutation factor or island count
- **Use the agent dashboard** to tune parameters in real time rather than restarting
- **Compare models** with different lag orders to find the most parsimonious structure

---

## 7. Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl + O` | Open / Load file |
| `Space` | Start / Pause evolution |
| `Ctrl + R` | Reset evolution |
| `Ctrl + S` | Save results |

---

<div align="center">

**AEGIS v2.0** · How to Use Guide

*For more details, see the About section.*

</div>
