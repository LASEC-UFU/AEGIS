# AEGIS core configuration (`aegis_configure`)

The configuration is a JSON object passed to `aegis_configure()` after
`aegis_load_data()`. Unknown keys are ignored and reported by
`aegis_get_last_error()`. `aegis_get_config()` returns the *effective*
configuration after validation, including the effective random seed (a seed
is always drawn and recorded when none is given). Values outside the valid
range are clamped to it.

Version: core 1.1.0-audit. Defaults below are the core defaults; the Flutter
app passes its own values for the parameters exposed in the UI.

## Data and splits

| Key | Default | Range | Meaning |
|---|---|---|---|
| `normalizerType` | `"minmax"` | `minmax`, `robust`, `zscore` | Fitted on the training split only; affine, **never clipped** (held-out data outside the training range are mapped linearly). |
| `trainRatio` | 0.70 | (0, 1) | Ratio mode: first ⌊N·r⌋ rows train. |
| `validationRatio` | 0.15 | [0, 1) | Ratio mode: next ⌊N·r⌋ rows validation; the rest is test. |
| `trainEndRow`, `valEndRow`, `testStartRow` | −1 | row indices | Index mode (overrides ratios). `testStartRow > valEndRow` leaves a gap (separate test record, e.g. a benchmark's test file appended to the estimation file). |
| `testTransient` | 0 | ≥ 0 | Samples at the start of the test record excluded from scoring (benchmark initialisation window). For a separate test record scoring starts at `testStartRow + max(maxDelay, testTransient)`. |
| `outputCol` | last column | column index | Output variable; all other columns are inputs. |
| `datasetName` | `""` | string | Free text stored in the records. |

## Search space and representation

| Key | Default | Range | Meaning |
|---|---|---|---|
| `maxRegressors` | 8 | 1–40 | Maximum regressors per model. |
| `maxTermsPerReg` | 3 | 1–6 | Maximum factors per regressor. |
| `maxDelay` | 40 | 1–500 | Maximum lag. Also the common scoring row for every candidate. |
| `pmin`, `pmax` | 0.5, 5.0 | 0.1–10 | Exponent range. |
| `exponentStep` | 0.5 | 0–1 | Exponent grid (0 = continuous). |
| `powerMode` | `"hybrid"` | `hybrid`, `signed`, `legacy` | Basis: `hybrid` = exact x^p for integer p, sign(x)·\|x\|^p otherwise; `signed` = sign(x)·\|x\|^p for all p; `legacy` = sign(x)·(\|x\|+10⁻⁶)^p (original code, for reproduction only). Stored in every exported model. |
| `denominatorProbability` | 0.3 | 0–1 | Probability that a new regressor goes to the denominator (rational models). |
| `rational` | — | bool | `false` is a shortcut for `denominatorProbability = 0`. |

## Differential evolution

| Key | Default | Range | Meaning |
|---|---|---|---|
| `numIslands` | 3 | 1–16 | Islands (ring migration). |
| `populationSize` | 50 | 4–1000 | Individuals per island. |
| `elitismCount` | 2 | 0–NP−1 | Best individuals protected from random immigrants/restarts (every individual still produces a trial; greedy selection is elitist). |
| `mutationStrategy` | `"jade"` | `jade`, `rand1` | JADE DE/current-to-pbest/1 (adaptive F, CR; no archive) or classic DE/rand/1 with fixed F, CR (ablation). |
| `mutationFactor` | 0.5 | 0.01–2 | Initial μF (JADE) or fixed F (rand1). JADE samples F ~ Cauchy(μF, 0.1) truncated to (0, 1]. |
| `crossoverRate` | 0.9 | 0–1 | Initial μCR (JADE) or fixed CR. |
| `jadeC`, `jadeP` | 0.1, 0.2 | | JADE learning rate and p-best fraction (top max(2, ⌈p·NP⌉)). |
| `variableMutationRate` | 0.3 | 0–1 | Probability of re-drawing a factor's variable. |
| `structuralMutationRate` | 0.1 | 0–1 | Probability of an add/delete/replace-regressor move per trial. |
| `migrationInterval` | 20 | ≥ 0 | Generations between migrations (0 = never). |
| `migrationRate` | 0.1 | 0–1 | Fraction of NP sent (≥ 1). Migrants are re-evaluated under the destination's weights and validation window and accepted only if better than its worst individual. |
| `reinitializationRatio`, `reinitInterval` | 0.1, 25 | | Random immigrants on island stagnation. |
| `hypermutation` | true | bool | JADE only: μF × 1.5 after 20 generations with zero successes. |
| `numThreads` | 0 | 0–64 | 0 = one thread per island; 1 = sequential (results are identical). |
| `randomSeed` | drawn | > 0 | Seed; island i uses seed + 104729·i. |

## Stopping (budget)

| Key | Default | Meaning |
|---|---|---|
| `maxGenerations` | 5000 | Generation limit. |
| `stagnationLimit` | 500 | Generations without improvement of the canonical champion. |
| `maxEvaluations` | 0 | Objective-evaluation budget (0 = unlimited). Use it for fair comparisons. |

The stop reason is recorded (`max_generations`, `stagnation`,
`max_evaluations`, `stopped`).

## Objective (fitness, lower is better)

f = E + α·B + β·P_D + γ·P_C + δ·P_E + η·P_S + ζ·P_I + θ·E_fr

| Key | Default | Term |
|---|---|---|
| `errorMode` | `"one_step"` | `one_step`: E = one-step RMSE on validation, B = BIC/n on training one-step residuals, θ·E_fr added. `simulation`: E = free-run RMSE over the whole validation split, B = ln(MSE_sim) + k·ln(n)/n, no θ term. |
| `alpha` | 0.05 | α — BIC weight. |
| `denominatorPenalty` | 0.1 | β — P_D = number of denominator regressors. |
| `complexityPenalty` | 0.01 | γ — P_C = number of factors (annealed by the curriculum, see below). |
| `exponentPenalty` | 0.01 | δ — P_E = Σ\|p−1\|. |
| `stabilityPenalty` | 1.0 | η — P_S = singularity of the rational denominator along the data (1 if it changes sign, else max(0, (0.1 − min\|D\|)/0.1)) + 1 if the free-run diverges (non-finite or \|ŷ\| > 10·max\|y_train\|). |
| `noInputPenalty` | 0.5 | ζ — P_I = max(0, c* − c)/c*, c = share of the non-autoregressive variance explained by input-dependent regressors (AR terms enter first), c* = `inputContributionMin`. |
| `inputContributionMin` | 0.3 | c*. |
| `freeRunPenalty` | 0.5 | θ base (curriculum multipliers 0, 0.5, 1, 1.5). |
| `freeRunHorizon` | 50 | Samples of the in-loop free-run RMSE E_fr (0 = whole validation split). |

All candidates are scored from row `maxDelay` of each split, so models with
different lags are compared on the same samples.

## Curriculum and islands

| Key | Default | Meaning |
|---|---|---|
| `curriculum` | true | Four phases (structural exploration → nonlinear expansion → parsimony/validation → local refinement); `false` disables phases (phase −1). |
| `phaseStagnationLimit` | 150 | Champion stagnation that forces phase transitions. |
| `gammaAnnealStart`, `gammaAnnealEnd` | γ, max(γ, 0.1) | γ chosen at each phase change by run progress. |
| `initialPmax`, `initialDelayFraction` | 1.5, 0.5 | Search space in phase 0. |
| `islandRoles` | true | Balanced / parsimony / free-run fidelity / stability weight profiles. |
| `islandRegimes` | true | Each island validates on its own contiguous fold of the validation split. The canonical champion is always selected on the whole validation split. |

## Post-processing (on the final champion)

| Key | Default | Meaning |
|---|---|---|
| `enablePruner` | true | Backward elimination; a removal is kept only if the canonical (validation) fitness does not get worse. |
| `enableRefiner` | true | Rational models: nonlinear least-squares refinement of the coefficients of N/D; kept only if the canonical fitness improves. |

## Agent interface and execution

| Key | Default | Meaning |
|---|---|---|
| `agentActionsEnabled` | true | Kill switch for agent actions (also `aegis_set_agent_enabled`). |
| `allowBudgetActions` | false | If false, actions that change the stopping criterion are rejected. |
| `actionCooldown` | 10 | Generations between changes of the same parameter. |
| `outcomeHorizon` | 25 | Generations used to score each action's outcome. |
| `webSocketPort` | 0 | > 0 starts the WebSocket server on 127.0.0.1. |
| `broadcastInterval` | 1 | Generations between WebSocket snapshots. |
| `syncMode` | false | Lockstep: generations only advance in `aegis_step()` (deterministic agent experiments). Always true in WASM. |
| `historyStride` | 1 | Store every n-th generation in the history. |
