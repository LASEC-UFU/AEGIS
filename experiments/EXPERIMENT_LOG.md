# AEGIS — experiment log

Chronological record of experimental decisions, including iterations that
were discarded. Times are local (UTC−3). Raw outputs live under
`experiments/results/` (current) and `experiments/results_archive/` (discarded
iterations); both are reproducible from the scripts and are not versioned.

## 2026-11-20 — Iteration 0: original code (commit 9e4b1d8)

- Binaries preserved in `experiments/bin/head-9e4b1d8/` (SHA-256 in `SHA256SUMS.txt`).
- `aegis_batch` of the original code fails every run (audit P0-1), so the
  baseline is produced by `experiments/tools/legacy_head_runner.cpp`, which
  uses only the original C API with the app's default configuration
  (`experiments/configs/legacy_head_app_defaults.json`).
- The original normalizer clips held-out data (P0-3), so the original models
  are re-evaluated with the audited metric code: `powerMode=legacy` reproduces
  the original regressor semantics exactly; `--refit 1` re-estimates the
  coefficients from the same least-squares problem (the original JSON export
  rounds coefficients to 8 decimals).
- Cascaded Tanks, 10 seeds, maxGenerations 2000 (≈ 3×10⁵ evaluations):
  `experiments/results/cascaded_tanks/legacy_head/`.

## 2026-11-20 — Iteration 1 (discarded): greedy ERR for the input-contribution penalty

- Engine 1.1.0-audit with the fixes P0-2…P0-8 and P1-1…P1-12 and the ERR
  computed in forward-greedy (FROLS) order on centred data.
- Cascaded Tanks, 10 conditions × 10 seeds, 3×10⁵ evaluations each.
- **Observed on training/validation diagnostics:** the champions systematically
  avoided short autoregressive lags (models use y(k−17…20) instead of
  y(k−1)), with validation one-step RMSE 0.51–0.72 V, whereas the original
  code reached ≈0.05 V one-step on the same data.
- **Cause:** the input-contribution penalty (ζ ≥ 1.5 in phase 0, target 0.3).
  With an order-invariant ERR, y(k−1) explains ≈99 % of the variance of a slow
  system, so any model containing it has an input share ≈0 and is penalised
  by ≈1.45 (normalized units) — far larger than the RMSE term. The search
  therefore drops y(k−1). In the original code the same indicator depended
  on the arbitrary order of the regressors in the chromosome (audit P1),
  which hid this incentive.
- **Decision:** redefine the indicator as the share of the variance *not
  explained by the autoregressive terms* that is explained by the
  input-dependent terms (AR terms entered first), see
  `IndividualEvaluator::compute_input_contribution_ratio`.
- **Disclosure:** the Cascaded Tanks *test* metrics of iteration 1 were
  viewed before this decision (SUMMARY.md in the archive). The decision was
  based on the structural/validation evidence above, but Cascaded Tanks can
  no longer be treated as a fully untouched benchmark for the final engine;
  conclusions must rest on Wiener–Hammerstein and Silverbox, whose test
  metrics had not been inspected.
- A Wiener–Hammerstein batch of iteration 1 was interrupted and archived
  without inspecting any of its metrics:
  `experiments/results_archive/iter1_greedy_input_err/wiener_hammerstein/`.

## 2026-11-20 — Iteration 2 (final engine for this study)

Changes after iteration 1, all decided on **training/validation** evidence
only (no test metric of iteration 2 was inspected before freezing):

1. Input-contribution indicator redefined (AR terms first; share of the
   non-autoregressive variance explained by input-dependent terms). Models
   again contain y(k−1); CT validation one-step RMSE ≈ 0.07 V.
2. Common scoring row: every candidate's validation one-step and free-run
   errors are scored from row `maxDelay` of the split (previously from its own
   maximum delay, so models with different delays were compared on different
   samples).
3. New option `errorMode` (`one_step` — the original documented objective,
   default; `simulation` — base term = free-run RMSE over the whole
   validation split, BIC on simulation residuals). `freeRunHorizon = 0`
   means "whole split".
4. CT validation check (4 seeds, 3×10⁵ evaluations): free-run RMSE on
   validation 0.83–0.86 V (`one_step`) and 0.69–0.94 V (`simulation`); the
   champions are near-linear structures dominated by y(k−1). Recorded as a
   limitation of the search, not tuned further.

Engine frozen here: `cpp/build/aegis_core.dll` (version 1.1.0-audit). The
protocol below is run once; every result is reported.

### Protocol

- Benchmarks: Cascaded Tanks (complete estimation/test records), Wiener–
  Hammerstein (first 20 000 samples of the official estimation set; official
  test set), Silverbox (first 20 000 samples of the multisine estimation part;
  test_multisine and test_arrow). Estimation data split 80 % train / 20 %
  validation in temporal order; test never used for any decision.
- Metric: free-run RMSE on test in original units, 50-sample initialisation
  window excluded (nonlinear_benchmarks convention).
- Budget: 3×10⁵ objective evaluations (CT), 1.5×10⁵ (WH, SB); seeds 1–10;
  one thread per run.
- Conditions: see `experiments/configs/conditions/` and docs/EXPERIMENTS.md.

### Continuation: learned policy, seeds 11–20 (2026-11-20)

- Confirmed the original protocol remains running at WH `aegis_sim`; no
  processes interrupted, no core rebuild, no WH/SB test metrics inspected.
- Confirmed 10 complete run files in each of the four policy-evaluation
  conditions; ran `analyze.dart` on that separate CT results tree.
- Test free-run RMSE (V), median [IQR]: reference 0.6718 [0.6616, 0.6742];
  learned fuzzy 0.6718 [0.6616, 0.6742]; UCB1 0.7182 [0.7045, 0.7405];
  heuristic fuzzy 1.091 [0.7051, 1.383]. No divergence in these 40 runs.
- Learned fuzzy equals the reference on 9/10 seeds and worsens one (mean
  0.7011 vs 0.6792 V; paired Wilcoxon Holm p=1). No evidence of superiority.
  UCB1 is worse (Holm p=0.0469); heuristic fuzzy p=0.0547 for test RMSE.
  Correction family: the three supervisors compared with `aegis_full`.
- These seeds were not used to learn the rule base, but CT remains a
  development benchmark because its test was observed in iteration 1.
- Extended the offline analyzer for explicitly named alternate evaluation
  JSONL files, with separate output required, duplicate-seed rejection and
  exclusion of the alternative FROLS BIC model. Engine unchanged.

### Incident: machine hang and resumed stages (2026-11-20)

- The machine froze at about 11:12 local and was hard-reset at 15:34 (System
  log: Kernel-Power 41, no bugcheck, no WHEA error, no firmware throttling
  event). Cause not determined. The machine also had unexpected shutdowns on
  2026-11-04 and 2026-11-09, before this work.
- Completed before the hang (10/10 each, JSON validated after reboot): WH
  `aegis_full`, `aegis_sim`, `de_rand1`, `single_island`, `no_curriculum`,
  `no_freerun`, `polynomial_only`, `agent_ucb1`. WH `agent_fuzzy` had only
  created empty files (moved to `experiments/results_archive/interrupted_2026-11-20_wh_agent_fuzzy/`).
- Remaining stages resumed with `experiments/scripts/run_protocol_resume.sh`:
  same binaries, configurations, budgets and seeds; parallelism reduced to 6
  (legacy stage 4) and BelowNormal priority. Runs are single-threaded and
  seeded, so results are unaffected; `wallSeconds` of the resumed stages is
  not comparable with stages run at 16 jobs.
- No WH/SB test metric was inspected.
