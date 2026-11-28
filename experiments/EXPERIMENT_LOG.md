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

### P1, P2'a and P6 (2026-11-25)

- P1 (exact optimizations; patch `experiments/perf/p1_p2a_p6.patch`): full
  ERR only in the canonical evaluator, cached factor series with row-wise Ψ,
  row-major Householder sweep. Unit tests pass. Bit-identity check
  (`experiments/perf/check_bitid.sh`, whole run JSON except time/path
  fields): 7/7 identical (CT aegis_full seed 1 with CT test vs frozen
  output; CT E3 mr39_zero_simulation seed 21 vs E3 run; WH mr39_zero
  simulation and one_step 3e4 evaluations vs P0 runs; SB 1e4 new vs frozen;
  CT powerMode signed and legacy 5e4 new vs frozen). Wall time 1.8–2.6×
  faster.
- P2'a (`fitMethod` = `normal`, island evaluators only; default `qr` stays
  bit-identical, checked on CT aegis_full seed 1). Pre-registration
  `experiments/perf/P2A_PREREG.md` committed before quality runs. Audit (CT
  6e4, WH 5e3 evaluations): fast path 100 % (2 fallbacks in 60 015), rank
  decisions identical, p99 relative SSE difference ≤ 4.7e-9. Speed (seed 21,
  mr39_zero_simulation): CT 134 s vs 936 s before P1; WH 3e4 evaluations
  314 s vs 2 628 s.
- P6: pre-registration `experiments/p6/P6_PREREG.md` committed before any
  run. Tool `aegis_p6` (selftest: sensitivities vs central differences
  6e-10, LM recovers a rational model to loss 1e-31).
  - **Aborted first launch (tool defect):** the simulator flagged a model as
    non-differentiable whenever a factor with exponent < 1 met x = 0, also
    for the INPUT u, which does not depend on θ and needs no derivative. All
    WH models stopped at iteration 0. Fixed so that only factors of the
    simulated output are checked (the derivative is only taken for them).
    No refinement result was used to make the fix (only the status
    `init_not_differentiable_or_diverged`). Partial output archived in
    `experiments/results_archive/p6_aborted_2026-11-25_input_zero_flag/`;
    P6 restarted from scratch.
- P6 completed (2026-11-25): 240 E3 champions, 233 used, 7 excluded (CT
  champions whose free-run diverges on TRAINING, flagged by the core
  itself). Pre-registered criterion (cell mr39_zero_simulation, V_B ratio):
  CT 1.000 not met, WH 0.873 met, SB 0.841 met → met (2/3). Report
  `experiments/p6/P6_REPORT.md`.
- P2'a quality (pre-registered §3) completed 2026-11-26 00:36: CT 22:30–22:52
  (1 at a time), WH 22:33–00:14 (3 in parallel), SB 22:33–00:36 (2 in
  parallel). Operational deviation: WH and SB were first launched one run at
  a time and stopped after 3 minutes with no output, then relaunched with
  3 and 2 in parallel; no parameter changed. Result vs E3 (median validation
  RMSE ratio): CT 1.000, WH 1.010, SB 0.965; 0 divergences; identical
  champion in 10/10, 5/10, 4/10 seeds. Equivalence criterion met. Median wall
  time 134/1704/1484 s vs E3 874/24752/25746 s (parallelism differs, see
  `experiments/perf/PERF_REPORT.md`).

### Core: P1 + P2'a applied; M9 veto and P6 final refinement (2026-11-26)

- User request (2026-11-26): apply P1 and P2'a to the main source, then add
  the champion's final simulation refinement (P6) and the admissibility veto
  checking the training simulation too. Branch `audit/aegis-1.1.0-wip` only.
- `0af456d`: P1 + P2'a applied from the validated patch. The frozen binaries
  in `cpp/build` and `cpp/build_phase0` were not rebuilt; they correspond to
  the source at `adc1ee9`. New build directory: `cpp/build_a1`.
- New options (all off by default; default output stays bit-identical to the
  frozen binary, checked on CT aegis_full seed 1 with `cpp/build_a1`):
  - `admissibilityVeto` (+ `vetoTopK`, default 5): champion promotion
    considers the best `vetoTopK` members of each island; admissible = free
    run over the whole training and validation splits does not diverge and
    |D| never falls below 1e-12; admissible always beats inadmissible. The
    veto also guards the pruner and the one-step refiner in post-processing.
  - `finalRefine` = `simulation`: P6 as the last post-processing step
    (`cpp/src/sim_refiner.cpp`, ported from the validated tool; same LM,
    veto with τ and sign changes, choice on V_A).
- Tests: `core_tests` 96/0 (new `test_sim_refiner`: refinement recovers a
  perturbed rational model, divergent model vetoed), `api_tests` 66/0,
  `phase0_tests` 11/0, `aegis_p6 --selftest` PASS.
- Smoke (validation only): CT mr39_zero_simulation + fitMethod normal + veto
  + finalRefine, seeds 23–26 (seeds 23 and 26 had training-divergent
  champions in E3): all four champions admissible (no training or validation
  divergence); refinement applied in 3 of 4 (seed 24 kept iterate 0).

### Agents updated, CAC developed, A1 frozen and started (2026-11-26)

- Agents (UCB1, fuzzy `expert-v2`, LLM prompt) read the new snapshot fields
  `search{…}` and `champion_admissible` (`ca765b6`). There is no neural
  network agent in the code base.
- CAC, adaptive convergence controller over every action-schema parameter
  with an estimated horizon to the next decision; `triggerRestart` now
  accepts up to 1.0 (elite and champion always kept = cataclysmic restart)
  (`5587fea`, doc 14).
- **CAC development run (CT, validation only, E3 split, A1 package, seeds
  21–23): unfavourable.** Validation free-run RMSE with CAC 0.723 / 0.851 /
  0.640 V against 0.592 / 0.659 / 0.494 V without agent; champions shrank to
  K = 5 (vs 14–28). About 150 actions per run, median horizon 10
  generations (champion plateaus read as "stalled"); the near-uniform
  Thompson exploration over 30+ arms raised the penalties that the A1
  package sets to zero. CAC is NOT part of A1; it needs redesign and its own
  pre-registration.
- A1 design frozen at `f51b8a7` (`experiments/a1/A1_PREREG.md`,
  `tool/experiments/a1_analysis.dart`, `experiments/a1/run_a1.sh`). The
  first launch failed before running anything (output directory missing for
  the log redirect); relaunched 07:41. Test metrics are written but not read
  until all 30 runs finish.
- CAC v3 dev, CT seeds 24–30 (validation only, A1 package, with/without
  CAC): end-of-search champion validation free-run better with CAC in 5/7
  (8/10 with seeds 21–23); final reported validation after pruning and P6
  mixed (2 better, 4 worse, 1 tie); after pruning and before P6, 5 better,
  3 worse, 2 ties over 21–30. Post-processing on CT adds large variance
  (e.g. seed 27: 0.0625 at search end, 0.221 after pruning). CT validation
  (205 samples) cannot decide; WH/SB needed (doc 15, T3/T5).
- postProcessGuard ablation (CT, validation only, seeds 21–30, build_dev;
  guard-off reproduction of seed 21 identical; search identical with and
  without guard): no agent, median final validation 0.464 → 0.424 V (6
  better, 4 equal, 0 worse); CAC v3 0.432 → 0.405 V (6 better, 2 worse, 2
  equal; seed 23 2.82 → 0.50 V). CAC v3 vs no agent, both guarded: 5 better,
  4 worse, 1 tie — inconclusive on CT. Root cause: the search fitness scores
  validation with a different start convention than the reported metric.

### A1 completed and analysed (2026-11-26)

- 30/30 runs (CT 07:41–07:45, SB until 09:55, WH until 10:00). Manifest with
  hashes committed (`5d1c5b8`) before the analysis; analysis run once
  (`4953ee1`). Pre-registered gate MET: WH test 9.32 vs 46.1 mV (ratio 0.20),
  SB multisine 0.349 vs 3.78 mV (0.09), both p Holm 0.002 (10/10 seeds).
  CT secondary: 0.712 vs 0.661 V (1.08), 3 test divergences for A1.
- SB arrow (no refit, `cpp/build_dev/aegis_evaluate_models.exe`, reproduction
  of the multisine metric of A1 run 1 exact): A1 median 0.507 mV vs 1.1.0
  7.56 mV, no divergences. Outputs in `experiments/results_a1/arrow/`.
- Pending 1.1.0 analysis opened after the A1 freeze, as pre-registered:
  `analyze.dart` on WH and SB (outputs in `experiments/results/<b>/analysis/`).
- CAC T1 started 2026-11-26 after A1 (6 processes).
- CAC T1 completed (2026-11-26, 1 450 runs, CT, validation only). Ten
  branches (seed 43, g=400) failed with Dart VM JIT crashes (likely memory
  pressure, 6 VMs in 7.4 GB) and one wrote an empty run file (kept as
  .broken); all re-run. Findings: γ↑ harmful at every time point
  (dose-dependent); β↑ the most consistent benefit on CT; δ↑/α↑ help the
  search-end metric (δ hurts the reported metric); DE operators, restarts,
  η and stagnationLimit within the placebo noise band; ζ inert (curriculum
  floors). Results: `experiments/cac/T1_RESULTS.md`, doc 15 §8.
- CAC T2+T3 completed (2026-11-27, 820 runs: CT 410, WH 205, SB 205; 5
  processes, no crashes; validation only). Penalty-weight effects are
  system-dependent: on WH and SB, raising δ or γ (even +0.02 / +0.002)
  worsens the champion in 5/5 seeds at every time point (log ratio +0.4 to
  +1.7), and β worsens less; on CT the same arms are within noise or helpful
  (final metric: α and late β help, δ and γ hurt). Results:
  `experiments/cac/T2_*.md`, doc 15 §10.
- CAC T4 (2026-11-27): overfitting gate gapOS = log(val/train one-step) >= 0.15
  separates CT from WH/SB (leave-one-system-out: no raises authorized on the
  held-out WH or SB); CAC v4 built from the measured map
  (`experiments/cac/T4_FEATURES.md`, doc 15 §11).
- CAC T5 (2026-11-27, 60 runs, validation only): pre-registered criterion NOT
  met. CT end-of-search v4 −0.151 (8/10 better) but worse than v3; WH +0.205
  (4/5 worse); SB +0.007 (3/5 worse). The gate never opened on WH/SB; the harm
  came from a few DE-operator moves. CT final reported validation worse in
  8/10 (post-processing variance, no postProcessGuard). Results:
  `experiments/cac/T5_RESULTS.md`, doc 15 §12.
- CAC T6 (2026-11-27, 50 runs, validation only, new seeds): pre-registered
  criterion NOT met. CT cac41_guard vs none_guard: end-of-search −0.184 (8/10
  better) but final reported validation +0.604 (7/10 worse); WH and SB: the
  gate never opened, 0 actions, identical to control (non-harm met).
  postProcessGuard alone on CT: final better 4/10, never worse. Exploratory
  diagnosis: v4.1 (β↑, α↑) yields smaller champions (K 5–22 vs 24–34) that win
  under the search validation convention but lose under the reported one.
  Results: `experiments/cac/T6_RESULTS.md`, doc 15 §14.
- CAC T7 (2026-11-27/28, 750 runs: CT 490, WH 130, SB 130; validation only):
  impact map of the new regulators. WH/SB (narrow placebo band): a larger
  regressor ceiling from the start helps (ceiling 79: WH −0.138, final 4/1
  better; SB −0.423, final 4/1); population −25 helps (WH 5/0, SB 4/1 final)
  and +50 hurts (WH 0/5, SB 1/4); rand/1 hurts (WH 0/5); pmax −1 hurts SB
  (0/5). Raising maxRegressors online barely grows the model (initialization
  draws up to the ceiling; growth online is one regressor per accepted
  mutation). elitismCount and hypermutation inert. CT: wide placebo band,
  nothing robust on the final metric. Results: `experiments/cac/T7_*.md`,
  doc 16 §8.
- CAC T6b (2026-11-28, 60 runs, validation only, new seeds): validationContext
  (search validation in the reported convention). Criterion 1 (adopt in
  package) NOT met: CT final +0.039 (4/6), SB 2/3 worse. Criterion 2 (CAC
  v4.1 + context) NOT met: CT final −0.004 (5/5); WH/SB 0 actions. The
  T6 harm (+0.604) disappears with the corrected signal, but no detectable
  gain. T8 runs with CTX=0 (pre-registered rule). Results:
  `experiments/cac/T6B_RESULTS.md`, doc 15 §16.
- CAC T8 (2026-11-28, 80 runs, validation only, new seeds, CTX=0): CAC v5
  vs A1, pre-registered criterion MET. Final reported validation: WH −0.072
  (8/10 better), SB −0.141 (9/10), CT −0.033 (6/10; non-harm). Secondary
  STATIC_pop25 vs none: WH −0.214 (9/10), SB −0.125 (6/10): the fixed dose
  has a similar effect. Results: `experiments/cac/T8_RESULTS.md`, doc 16 §10.
