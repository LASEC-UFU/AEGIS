# Phase 0: E3 screening (configuration only, binary 1.1.0)

Validation free-run RMSE (original units), seeds 21–30. No test segment exists in these runs.

## cascaded_tanks

| cell | runs | median | IQR | diverged (val) | median K | median evals | median wall s |
|---|---|---|---|---|---|---|---|
| mr39_default_one_step | 10 | 0.8617 | [0.8247, 0.9084] | 0 | 4 | 300119 | 40 |
| mr39_default_simulation | 10 | 0.8564 | [0.6169, 0.9176] | 0 | 5 | 300073 | 54 |
| mr39_zero_one_step | 10 | 1.1464 | [0.7609, 1.4538] | 2 | 25 | 300120 | 863 |
| mr39_zero_simulation | 10 | 0.4943 | [0.4127, 0.6371] | 0 | 22 | 300045 | 874 |
| mr8_default_one_step | 10 | 0.9382 | [0.8710, 1.0063] | 0 | 4 | 300109 | 30 |
| mr8_default_simulation | 10 | 0.9465 | [0.9041, 1.0270] | 0 | 5 | 300094 | 45 |
| mr8_zero_one_step | 10 | 0.7761 | [0.6040, 0.9418] | 0 | 7 | 300121 | 106 |
| mr8_zero_simulation | 10 | 0.5047 | [0.3995, 0.6733] | 0 | 8 | 300084 | 106 |

- one_step: zero+39 / default+8 = 1.222 → not met

- simulation: zero+39 / default+8 = 0.522 → criterion met

## wiener_hammerstein

| cell | runs | median | IQR | diverged (val) | median K | median evals | median wall s |
|---|---|---|---|---|---|---|---|
| mr39_default_one_step | 10 | 0.0508 | [0.0486, 0.0508] | 0 | 6 | 150101 | 879 |
| mr39_default_simulation | 10 | 0.0396 | [0.0389, 0.0410] | 0 | 7 | 150080 | 915 |
| mr39_zero_one_step | 10 | 0.0282 | [0.0267, 0.0377] | 0 | 33 | 150054 | 27432 |
| mr39_zero_simulation | 10 | 0.0107 | [0.0097, 0.0114] | 0 | 33 | 150096 | 24752 |
| mr8_default_one_step | 10 | 0.0508 | [0.0508, 0.0508] | 0 | 6 | 150030 | 539 |
| mr8_default_simulation | 10 | 0.0389 | [0.0348, 0.0407] | 0 | 7 | 150086 | 743 |
| mr8_zero_one_step | 10 | 0.0578 | [0.0553, 0.0631] | 0 | 9 | 150083 | 1401 |
| mr8_zero_simulation | 10 | 0.0325 | [0.0313, 0.0334] | 0 | 9 | 150084 | 1345 |

- one_step: zero+39 / default+8 = 0.556 → criterion met

- simulation: zero+39 / default+8 = 0.276 → criterion met

## silverbox

| cell | runs | median | IQR | diverged (val) | median K | median evals | median wall s |
|---|---|---|---|---|---|---|---|
| mr39_default_one_step | 10 | 0.0033 | [0.0033, 0.0033] | 0 | 7 | 150038 | 756 |
| mr39_default_simulation | 10 | 0.0019 | [0.0018, 0.0026] | 0 | 7 | 150105 | 893 |
| mr39_zero_one_step | 10 | 0.0004 | [0.0004, 0.0005] | 0 | 32 | 150110 | 19205 |
| mr39_zero_simulation | 10 | 0.0003 | [0.0003, 0.0004] | 0 | 31 | 150026 | 25746 |
| mr8_default_one_step | 10 | 0.0033 | [0.0033, 0.0033] | 0 | 7 | 150052 | 497 |
| mr8_default_simulation | 10 | 0.0026 | [0.0026, 0.0027] | 0 | 7 | 150115 | 615 |
| mr8_zero_one_step | 10 | 0.0009 | [0.0009, 0.0011] | 0 | 9 | 150089 | 1244 |
| mr8_zero_simulation | 10 | 0.0008 | [0.0008, 0.0009] | 0 | 9 | 150066 | 1306 |

- one_step: zero+39 / default+8 = 0.122 → criterion met

- simulation: zero+39 / default+8 = 0.133 → criterion met

## Screening result

- one_step: criterion met in 2 of 3 benchmarks run → decompose parsimony pressure.
- simulation: criterion met in 3 of 3 benchmarks run → decompose parsimony pressure.

The two errorModes are reported separately; the pre-registration does not combine them.
