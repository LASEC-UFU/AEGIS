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

### Incident 2: second machine hang (2026-11-20 18:42)

- The machine froze at 18:42:27 local and was restarted on 2026-11-21 at
  09:43.
- System log: Kernel-Power 41 with BugcheckCode 0. There is no WHEA error,
  no storage or display-driver event, and no dump. This matches 11:12 the
  same day and 2026-11-04 21:57 / 2026-11-07 19:02, both before this work.
- Load at the time:
  - 4 runs of the original code (WH `legacy_head`), about 12 threads of 32;
  - 50 GB of free RAM;
  - BelowNormal priority.
- Reducing the load after the first hang did not prevent the second.
- Results at the time of the hang:
  - WH `legacy_head` runs 1–4 completed; JSON validated after reboot.
  - WH `legacy_head` runs 5–8 were interrupted and left empty `.log` files
    only; runs 9–10 never started.
  - SB `legacy_head` and Phase 0 E3 had not started.
  - No WH/SB test metric was inspected.
- Monitor correction: the `cpu%` column of `protocol_monitor.log` came from
  WMI `Win32_Processor.LoadPercentage`, which reads about 43 % on an idle
  machine while `\Processor(_Total)\% Processor Time` reads 1–4 %. Those
  values are overstated and must not be used. The monitor in
  `run_protocol_resume.sh` now uses the performance counter.
- The cause is still undetermined. The diagnosis and suspects (RAM profile,
  2022 BIOS, Ryzen 5000 idle/transition freezes, PSU/VRM) are in
  `docs/HANDOFF.md` §4.0a.
- Runs are not restarted until the user decides.

### Continuation on a second machine (2026-11-21)

- The original workstation (Ryzen 9 5950X) was retired from long runs after
  the hangs above. Work continues per `docs/PROMPT_CONTINUACAO_OUTRA_MAQUINA.md`.
- Second machine: AMD Ryzen 5 PRO 5650G (6 cores / 12 logical CPUs), 7.4 GB
  RAM, Windows 11 Pro 10.0.26300 (pt-BR locale), Flutter 3.44.0 / Dart 3.12.0.
  No compiler used; no binary rebuilt.
- Integrity: state package `aegis_estado_local_2026-11-21.tar.gz` SHA-256
  `4fdf47ba…7155c` matches; `sha256sum -c experiments/transfer/FILES.sha256`
  OK for all 741 files; frozen binaries `cpp/build/aegis_core.dll`,
  `cpp/build/aegis_batch.exe`, `cpp/build_phase0/aegis_phase0.exe` and
  `experiments/bin/head-9e4b1d8/*` match the recorded hashes.
- Sanity: `core_tests` 91 checks / 0 failures; `api_tests` 66 / 0;
  `phase0_tests` 11 passed / 0 failed.
- Cross-machine reproduction: CT `aegis_full`, seed 1, 3×10⁵ evaluations,
  written to `experiments/transfer/repro_ct/`. `report.model`,
  `report.evaluations` and `report.metrics.validation` are **identical** to
  `experiments/results/cascaded_tanks/aegis_full/run_1.json` (validation
  free-run RMSE 0.8320657852 V in both). Bit-for-bit reproduction across the
  two machines is confirmed for this run.
- `wallSeconds` / `elapsedSeconds` from this machine are not comparable with
  the original machine (different CPU and parallelism).
- Load rules on this machine: at most 6 compute processes and never more
  than half of the 12 logical CPUs. The original code uses about 3 threads
  per run, so `legacy_head` runs here with 2 in parallel (the prompt's value
  of 4 was set for the 32-thread machine). Parallelism does not change
  seeded results. CPU load is read from
  `Win32_PerfFormattedData_PerfOS_Processor` (`_Total`), since the
  `\Processor(_Total)\% Processor Time` counter path is localized on this
  Windows (pt-BR) and fails under that English name.
- The empty `.log` files of the interrupted WH `legacy_head` seeds 5–8 were
  moved to `experiments/results_archive/interrupted_2026-11-20_wh_legacy_head/`
  before resuming.
- WH `legacy_head` resumed on the second machine 2026-11-21 11:24–12:14
  (`run_legacy_head.sh wiener_hammerstein 1000 2 10`, BelowNormal, log
  `experiments/results/legacy_resume_wh.log`, exit 0). Seeds 1–4 come from the
  original machine; seeds 5–10 from this one. About 15 min per run, 2 in
  parallel. 10/10 `run_*.json` parse as complete JSON objects (only parsed;
  no metric read). `aegis_evaluate_models` regenerated
  `legacy_head/evaluations.jsonl` over all 10 runs; that file was not opened.
- SB `legacy_head` run on the second machine 2026-11-21 12:15–13:43
  (`run_legacy_head.sh silverbox 1000 2 10`, BelowNormal, log
  `experiments/results/legacy_resume_sb.log`, exit 0). About 17–18 min per
  run, 2 in parallel. 10/10 `run_*.json` parse as complete JSON objects.
  `legacy_head/evaluations.jsonl` generated and not opened.

### Protocol 1.1.0 completed (2026-11-21 13:43)

- Every protocol condition has 10/10 complete `run_*.json`:
  - CT: 14 conditions (including the agents, `legacy_head` and the CT-only
    ablations);
  - WH: 7 core conditions, `agent_ucb1`, `agent_fuzzy` and `legacy_head`;
  - SB: 7 core conditions and `legacy_head`;
  - FROLS baselines are in `frols/` (different file format, not counted).
- Failures and deviations over the whole protocol: two machine hangs on the
  original machine (WH `agent_fuzzy` restarted from scratch; WH
  `legacy_head` seeds 5–8 restarted), and the machine change for WH
  `legacy_head` seeds 5–10 and SB `legacy_head` 1–10 (bit-for-bit
  reproduction across machines confirmed on CT `aegis_full` seed 1).
  Parallelism differed between stages; `wallSeconds` is not comparable
  across stages.
- No WH/SB test metric has been inspected. The final analysis
  (`analyze.dart`, arrow evaluation) waits for the user's decision.

### Phase 0 E3 completed (2026-11-23 21:59)

- `experiments/phase0/run_e3.sh` (unchanged), `PAR=6`, BelowNormal, frozen
  `cpp/build/aegis_batch.exe`, for CT, WH and SB in sequence; log
  `experiments/results_phase0/e3_run.log`, exit 0 for all three. One commit
  of `MANIFEST.jsonl` per benchmark.
- 240/240 runs complete (3 benchmarks × 8 cells × seeds 21–30). No test
  segment exists in these runs (`testStartRow` = `valEndRow`); the summary
  script aborts if one is found, and it did not.
- Validation divergences: 2, both in CT `mr39_zero_one_step`.
- Longest cells: `mr39_zero_*` on WH and SB, median 19 000–27 000 s per run
  (about 12–13 h per cell with 6 in parallel). The SB
  `mr39_zero_simulation` cell ran 09:13–21:59 on 2026-11-23.
- Pre-registered screening (zero+39 / default+8 median ratio ≤ 0.90 in ≥ 2
  of 3): `one_step` met 2/3 (CT 1.22 not met, WH 0.56, SB 0.12);
  `simulation` met 3/3 (CT 0.52, WH 0.28, SB 0.13). Report:
  `experiments/phase0/PHASE0_REPORT.md` §7; summary `SUMMARY_E3.md`.
- Deviations: none in execution. All E3 cells ran on the second machine
  (the original machine never started E3). Document
  discrepancy noted in the report (parecer 07 §10.4 vs prereg §3 on gamma
  annealing in the default cells; the prereg was followed).
- Local-state package (outside git):
  `experiments/transfer/aegis_estado_local_2026-11-23.tar.gz`, 1 083 files
  (frozen binaries of `cpp/build` and `cpp/build_phase0`, `experiments/data`,
  `results`, `results_archive`, `results_policy_eval`, `bin`,
  `results_phase0`), SHA-256
  `481e277660baf95bfa2a471052b013c4d1d1ce070407116882d4f4cdbc5c722f`.
  Verified by extracting to a temporary folder and `sha256sum -c`: 1 083 OK.
  The 2026-11-21 package and its `FILES.list`/`FILES.sha256` were kept.

### P0 profiling (2026-11-24)

- Authorized by the user on 2026-11-23. Instrumented build of the unchanged
  1.1.0 source (`experiments/perf/p0_probe.patch`, active only with
  `-DAEGIS_PROFILE`), built in a separate git worktree with the MSYS2 g++ 16.1
  of this machine (`C:\SourceCode\MSYS2\ucrt64\bin`). Frozen `cpp/build` and
  `cpp/build_phase0` untouched.
- Checks: `core_tests` 91/0, `api_tests` 66/0, `phase0_tests` 11/0. CT
  `aegis_full` seed 1 with the new base build and the instrumented build:
  `report.model`, `report.evaluations` and `report.metrics.validation`
  bit-identical to the frozen binary (g++ 16.2). Probe overhead ≈ 2 %.
- Runs: `experiments/perf/run_p0.sh`, E3 split and overrides, seed 21, no
  test file, 6 processes in parallel, BelowNormal, 13:56–14:41. CT
  `mr8_default_simulation`, `mr39_zero_simulation`, `mr39_zero_one_step` at
  full budget; WH same cells at 3×10⁴ evaluations (deviation: 1/5 of the
  budget, covers only the start of the search). Outputs in
  `experiments/results_perf/` (git-ignored). Analyzer
  `tool/experiments/p0_profile.dart` reads only times, structure counts and
  `wallSeconds`.
- Main numbers (K 31–40): fit 26–35 %, full ERR (unused in fitness) 25–27 %,
  grouped ERR 21–23 %, Ψ 15–19 %, free-run simulation 0.1–1.8 %; outside
  `evaluate()` 0.5–3 %. Simulated shift-invariant cache hit rate 50–60 %
  with 7.8–72 million distinct keys. Analysis and recommendation:
  `docs/architecture/13_P0_PROFILING.md`.
