# AEGIS agent interface

AEGIS can be supervised by an agent — a remote LLM (Claude), the local UCB1
bandit, the local fuzzy policy, a human in the UI or any external program
over WebSocket. Every agent uses the **same** channel:

1. it **observes** a structured snapshot of the identification;
2. it **proposes** at most a few bounded parameter changes;
3. the C++ core **validates** each proposal (range, maximum step, cooldown,
   budget lock, kill switch) and accepts or rejects it with a code;
4. accepted actions are applied **between generations** (never inside one);
5. the core **records** the state before the action and scores its outcome
   after `outcomeHorizon` generations.

Agents never access engine internals. Disabling the agent
(`aegis_set_agent_enabled(p, 0)` or the UI switch) leaves the run untouched,
and a run without agent is bit-for-bit reproducible from its seed.

## 1. Observation

`aegis_get_snapshot()` returns `aegis.snapshot/2` (also broadcast over
WebSocket). The Dart layer converts it to `GenerationSnapshot` and to the
compact `aegis.observation/1` sent to the LLM. Test-set metrics are never
present in either (`rmse_test` is always `null` during a run).

| Group | Fields (snapshot/2) |
|---|---|
| Progress | `generation`, `evaluations`, `elapsedMs`, `phase`, `phase_name`, `stop_reason` |
| Champion (canonical: full validation split, reference weights) | `best_fitness`, `rmse_train`, `rmse_validation`, `r2_train`, `r2_validation`, `bic`, `aic`, `free_run_rmse` (in-loop horizon), `free_run_rmse_val_full`, `free_run_r2_val_full`, `input_contribution_ratio`, `residual_input_corr`, `num_terms` (regressors), `num_factors`, `max_delay`, `max_exponent`, `is_rational`, `coefficients`, `intercept`, `exponents`, `err`, `term_labels`, `fitness_breakdown{…}` |
| Diagnostics | `stability{is_stable, min_abs_denominator, denominator_sign_changes, free_run_diverged, free_run_val_diverged, linear_spectral_radius, penalty}`, `residual_autocorr` (lags 0..20, validation one-step residuals), `residual_acf_bound` (1.96/√N), `residual_white`, `residual_input_ccf_max`, `overfitting`, `overfit_gap_ratio`, `underfitting`, `alerts` |
| Population | `population_diversity` (mean within-island fitness s.d.), `population_variance`, `fitness_mean`, `fitness_median`, `unique_structures`, `structure_entropy`, `success_rate`, `mu_f`, `mu_cr`, `stagnation` (max island), `global_stagnation` (champion), `mean_num_regressors` |
| Islands | `islands[]{id, role, best/mean/median/std/worst_fitness, stagnation, success_rate, mu_f, mu_cr, unique_structures, population_size, mean_num_regressors, best_rmse_val}` — fitness values are on each island's own objective scale |
| Control | `parameters{name: current base value}`, `effective_weights{alpha…theta, free_run_horizon}`, `agent{enabled, actionsAccepted, actionsRejected, pending, lastAction}` |

## 2. Actions

`aegis_get_action_schema()` publishes the tunable parameters:

| Parameter | Kind | Range | Max step | Notes |
|---|---|---|---|---|
| `mutationFactor` | DE | 0.05–1.0 | 0.3 | JADE: resets μF of every island (μCR untouched) |
| `crossoverRate` | DE | 0–1 | 0.3 | JADE: resets μCR (μF untouched) |
| `migrationRate` | DE | 0–0.5 | 0.2 | |
| `migrationInterval` | DE | 5–200 | 50 | integer |
| `reinitializationRatio` | DE | 0–0.5 | 0.2 | random immigrants |
| `structuralMutationRate` | DE | 0–0.5 | 0.2 | |
| `stagnationLimit` | DE | 50–5000 | 1000 | **budget-affecting**, rejected unless `allowBudgetActions` |
| `complexityPenalty` | weight | 0–1 | 0.1 | overrides the curriculum annealing |
| `noInputPenalty` | weight | 0–5 | 1.0 | base value (phase floors apply) |
| `freeRunPenalty` | weight | 0–5 | 1.0 | θ base |
| `freeRunHorizon` | weight | 10–500 | 200 | re-evaluates the populations |
| `denominatorPenalty`, `stabilityPenalty`, `exponentPenalty`, `alpha` | weight | see schema | | |
| `triggerRestart` | event | 0.05–0.5 | — | one-shot restart fraction, cooldown 50 |

Request (`aegis_apply_action`, WebSocket text frame, or the Dart
`AegisFfiService.applyAction`):

```json
{"param": "mutationFactor", "value": 0.65, "reason": "success rate 1 % for 120 generations", "source": "llm"}
```

`{"actions":[{"param":…,"value":…}, …]}` and the legacy
`{"proposed_changes":{"param":value}, "reason":"…"}` are also accepted.

Reply: `{"results":[ActionRecord…]}` with `accepted`, `code`, `message`,
`oldValue`, `newValue`, `effectiveValue`, `generation`, `generationApplied`,
`pre`, `post`, `outcome`.

Rejection codes: `agent_disabled`, `not_running`, `invalid_json`,
`unknown_parameter`, `invalid_value`, `budget_locked`, `out_of_range`,
`step_too_large`, `cooldown`, `no_change`. Rejected requests are logged too.

## 3. Trajectory records

Two complementary logs are produced:

* **Core action log** (`aegis_get_tuning_log`, `finalReport.actions`): every
  action from every source, accepted or rejected, with the state digest
  before (`pre`), after `outcomeHorizon` generations (`post`), the relative
  change of the champion's validation RMSE after the action (`postChange`)
  and in the same number of generations before it (`preTrend`, drift
  baseline) and the outcome: `improved` / `worsened` / `neutral` (|score| <
  0.2 %) / `inconclusive` (a phase change, a reflex restart or another action
  inside the window, or the run ended). Curriculum transitions are logged with
  `source = "reflex"`.
* **Agent decision log** (`AgentDecision`, `aegis.decision/1`, written to
  `decisions_<seed>.jsonl` by the experiment runner): one record per
  consultation, including `no_action`, `insufficient_evidence`, `skipped`,
  `error`, `refusal` and `rejected_locally`, with the rationale, the agent's
  diagnosis, the observation (LLM), latency, token usage and estimated cost.

These records are the training data for local policies
(`tool/experiments/learn_fuzzy_policy.dart`).

## 4. Agents shipped

| Mode | Class | Notes |
|---|---|---|
| off | — | |
| local (UCB1) | `LocalAdaptiveAgent` | heuristic candidates every 25 generations; UCB1 over (parameter, direction) arms; reward = improvement of validation RMSE over 50 generations relative to the drift baseline, clipped to [−1, 1]; observations crossing a phase change are discarded; severe signals bypass persistence, never the cooldown |
| fuzzy | `FuzzyPolicyAgent` | zero-order Takagi–Sugeno rule base (JSON); explicit refusal when the firing strength is below the evidence threshold |
| remote (Claude) | `LlmAgent` (`llm_agent_core.dart`) | raw HTTPS to the Messages API (Dart has no official SDK); default model `claude-opus-5-5`, effort `medium`, structured output (JSON schema), server-side refusal fallback, 120 s timeout, call and cost budgets; at most one action per consultation |
| external | WebSocket client | `webSocketPort > 0`; same action interface |

## 5. LLM credentials and cost

The key is read from `ANTHROPIC_API_KEY` or from `anthropic_api_key.txt`
next to the executable (git-ignored); it is never logged or written by AEGIS.
Each consultation sends ≈ 2–4 k input tokens and receives a short structured
reply (plus thinking tokens); at the list price of `claude-opus-5-5`
(US$ 4 / 20 per million input/output tokens) the estimate is US$ 0.02–0.06
per consultation. `consultEvery`, `maxCalls` and `maxCostUsd` bound the
spend; the experiment runner refuses to start the LLM condition without a key
and makes no request.
