# Reproducing the AEGIS evaluation

Everything below runs from the repository root. The study protocol, the
discarded iterations and the reasons for every decision are recorded in
[`experiments/EXPERIMENT_LOG.md`](../experiments/EXPERIMENT_LOG.md).

## 1. Environment used

| Item | Value |
|---|---|
| CPU / RAM | AMD Ryzen 9 5950X (16 cores, 32 threads), 64 GB |
| OS | Windows Server 2025 Standard Evaluation 10.0.26100 |
| C++ | g++ 16.2.0 (MSYS2 UCRT64), CMake 4.4.3, Ninja; `-O2 -ffp-contract=off` (+ CMake Release `-O3`), no `-march=native`, static runtime |
| Dart / Flutter | Dart 3.12.2, Flutter 3.44.2 (only `dart` is needed for the experiments) |
| Threads | one thread per run (`numThreads = 1`); runs parallelised over seeds (`--jobs`) |

Bitwise reproducibility is expected for the same binary, data and
configuration. Different compilers or CPUs may change floating-point results
slightly (we avoid `-march=native` and FMA contraction for this reason).

## 2. Build and test

```bash
cmake -S cpp -B cpp/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build cpp/build
cpp/build/core_tests && cpp/build/api_tests
flutter pub get && flutter test
dart compile exe tool/experiments/run_agent_experiment.dart -o experiments/bin/aegis_agent_runner.exe
```

## 3. Data

Download the three raw files listed in [BENCHMARKS.md](BENCHMARKS.md) into
`experiments/data/raw/<benchmark>/` (zip archives extracted in place under
`extracted/`), then:

```bash
dart run tool/benchmarks/prepare_benchmarks.dart     # verifies SHA-256, writes processed CSVs + PROVENANCE.json
```

## 4. Runs

```bash
experiments/scripts/run_protocol.sh          # all conditions, agents, original-code baseline
experiments/scripts/run_frols.sh cascaded_tanks   # FROLS baseline (also wiener_hammerstein, silverbox)
experiments/scripts/run_policy_eval.sh cascaded_tanks 300000 6   # learned fuzzy policy on unseen seeds 11-20
```

Individual pieces:

| Script | What it runs |
|---|---|
| `run_conditions.sh <bench> <budget> <jobs> <seeds> [cond…]` | `aegis_batch` for each `experiments/configs/conditions/<cond>.json` |
| `run_agents.sh <bench> <budget> <par> <seeds> <agent>` | lockstep runner with `ucb1`, `fuzzy`, `fuzzy:<rulebase.json>` or `llm` |
| `run_legacy_head.sh <bench> <maxGen> <par> <seeds>` | original code 9e4b1d8 (preserved DLL) + re-evaluation with `powerMode=legacy` |
| `run_frols.sh <bench>` | FROLS grid, selection by validation free-run RMSE |
| `run_policy_eval.sh` | generalisation of the learned rule base |

The LLM condition is **not** part of `run_protocol.sh`: it needs an API key and
costs money (≈ US$ 0.02–0.06 per consultation with `claude-opus-5-5`; one run
of 3×10⁵ evaluations ≈ 40 consultations). Run it explicitly:

```bash
export ANTHROPIC_API_KEY=...        # never commit it
experiments/scripts/run_agents.sh cascaded_tanks 300000 2 10 llm
```

## 5. Analysis

```bash
dart run tool/experiments/analyze.dart --results experiments/results/cascaded_tanks --title "Cascaded Tanks"
dart run tool/experiments/learn_fuzzy_policy.dart --out experiments/policies/fuzzy_learned_ct.json \
    --seeds 1-10 experiments/results/cascaded_tanks/agent_ucb1 experiments/results/cascaded_tanks/agent_fuzzy
```

`analyze.dart` writes `SUMMARY.md` (descriptive statistics with bootstrap
CIs, exact Wilcoxon signed-rank tests paired by seed against `aegis_full`,
exact Mann–Whitney tests for unpaired baselines, Holm correction),
`runs.csv`, `stats.json`, `boxplot_test_freerun.svg` and `convergence.svg`.

Alternate frozen-model evaluations can be analysed separately after the full
protocol finishes. Put one `evaluations_arrow.jsonl` in each condition directory
(output of `aegis_evaluate_models --refit 0` with `test_arrow.csv`), then run:

```bash
dart run tool/experiments/analyze.dart --results experiments/results/silverbox \
  --evaluations evaluations_arrow.jsonl --out experiments/results/silverbox/analysis_arrow \
  --title "Silverbox (test arrow, extrapolation)"
```

This mode reads only that filename, skips conditions without it, rejects
duplicate seeds and requires a separate output directory. For FROLS pass only
the source named by `frols/selected.json` (`selectedFile`), which was selected
by validation; the analyzer excludes its alternative BIC-selected model.
For legacy models use the legacy power-mode configuration documented in
`run_legacy_head.sh`; do not use the hybrid default for those models.

### Learned-policy evaluation: CT seeds 11–20

Analysis: `experiments/results_policy_eval/cascaded_tanks/analysis/SUMMARY.md`.
Ten runs per condition; no free-run divergence. Test simulation RMSE in V:

| Condition | Median [IQR] | Mean | Holm p vs reference |
|---|---|---|---|
| aegis_full | 0.6718 [0.6616, 0.6742] | 0.6792 | reference |
| agent_fuzzy_learned | 0.6718 [0.6616, 0.6742] | 0.7011 | 1.000 |
| agent_ucb1 | 0.7182 [0.7045, 0.7405] | 0.7807 | 0.0469 |
| agent_fuzzy | 1.091 [0.7051, 1.383] | 1.071 | 0.0547 |

The learned policy matches the reference in nine seeds and worsens one; it
does not demonstrate an improvement. UCB1 worsens test simulation RMSE
significantly after correction over the three comparisons. These are unseen
seeds on a development benchmark, not an independent unseen dataset.

## 6. Conditions

| Condition | Difference from `aegis_full` |
|---|---|
| `aegis_full` | app defaults, `errorMode = one_step`, JADE, 3 islands × 50, ring migration, curriculum, island roles and regimes, hybrid basis (step 0.5), rational terms allowed, pruner + refiner |
| `aegis_sim` | `errorMode = simulation` |
| `de_rand1` | classic DE/rand/1, F = 0.5, CR = 0.9 fixed |
| `single_island` | 1 island × 150 (same population), no migration |
| `no_migration` | `migrationRate = 0` |
| `no_curriculum` | `curriculum = false` |
| `no_freerun` | `freeRunPenalty = 0` |
| `polynomial_only` | `rational = false` |
| `no_roles_regimes` | `islandRoles = islandRegimes = false` |
| `signed_continuous` | `powerMode = signed`, `exponentStep = 0` (close to the original representation, without the ε bias) |
| `no_postprocessing` | `enablePruner = enableRefiner = false` |
| `agent_ucb1`, `agent_fuzzy` | `aegis_full` supervised by the agent |
| `legacy_head` | original code 9e4b1d8, app defaults, maxGenerations 2000 (CT) / 1000 (WH, SB) |
| `frols` | FROLS polynomial NARX, (ny, nu, degree) chosen by validation |
