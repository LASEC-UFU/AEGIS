#!/usr/bin/env bash
# Bit-identity check of a modified build against the frozen 1.1.0 binary or
# against runs already produced by it (P1, docs/architecture/13_P0_PROFILING.md).
# Validation-only configurations for WH/SB (E3 split, no test file).
#   experiments/perf/check_bitid.sh <new_build_dir> <out_dir>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NEW="$1/aegis_batch.exe"; FROZEN="$ROOT/cpp/build/aegis_batch.exe"; O="$2"; L="$ROOT/experiments/phase0/lowprio.sh"
CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
ZERO=(--set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 --set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0)
SPLIT_CT=(--set trainEndRow=819 --set valEndRow=1024 --set testStartRow=1024)
SPLIT_L=(--set trainEndRow=16000 --set valEndRow=20000 --set testStartRow=20000)
D="$ROOT/experiments/data/processed"
go() { # name bin data seed args...
  local n="$1" bin="$2" data="$3" seed="$4"; shift 4; mkdir -p "$O/$n"
  "$L" "$bin" --data "$data" --config "$CFG" "$@" --runs 1 --seed-start "$seed" --jobs 1 --label "$n" --output "$O/$n" > "$O/$n/batch.log" 2>&1
}
# 1) CT aegis_full seed 1 (reference: frozen output in experiments/transfer/repro_ct)
go ct_full "$NEW" "$D/cascaded_tanks/est.csv" 1 --data-test "$D/cascaded_tanks/test.csv" &
# 2) CT E3 mr39_zero_simulation seed 21, full budget (reference: E3 run_21.json)
go ct_e3z39s "$NEW" "$D/cascaded_tanks/est.csv" 21 "${SPLIT_CT[@]}" --set maxEvaluations=300000 --set maxRegressors=39 --set errorMode=simulation --set freeRunHorizon=0 "${ZERO[@]}" &
# 3,4) WH 3e4 evaluations (reference: P0 runs, built from the unchanged source)
go wh_z39s "$NEW" "$D/wiener_hammerstein/est.csv" 21 "${SPLIT_L[@]}" --set maxEvaluations=30000 --set maxRegressors=39 --set errorMode=simulation --set freeRunHorizon=0 "${ZERO[@]}" &
go wh_z39o "$NEW" "$D/wiener_hammerstein/est.csv" 21 "${SPLIT_L[@]}" --set maxEvaluations=30000 --set maxRegressors=39 --set errorMode=one_step "${ZERO[@]}" &
# 5) SB 1e4 evaluations, new and frozen
go sb_new "$NEW" "$D/silverbox/est.csv" 21 "${SPLIT_L[@]}" --set maxEvaluations=10000 --set maxRegressors=39 --set errorMode=simulation --set freeRunHorizon=0 "${ZERO[@]}" &
go sb_frozen "$FROZEN" "$D/silverbox/est.csv" 21 "${SPLIT_L[@]}" --set maxEvaluations=10000 --set maxRegressors=39 --set errorMode=simulation --set freeRunHorizon=0 "${ZERO[@]}" &
wait
# 6) CT signed and legacy power modes, 5e4 evaluations, new and frozen
for pm in signed legacy; do
  go ct_${pm}_new "$NEW" "$D/cascaded_tanks/est.csv" 3 "${SPLIT_CT[@]}" --set maxEvaluations=50000 --set powerMode=$pm "${ZERO[@]}" --set maxRegressors=39 &
  go ct_${pm}_frozen "$FROZEN" "$D/cascaded_tanks/est.csv" 3 "${SPLIT_CT[@]}" --set maxEvaluations=50000 --set powerMode=$pm "${ZERO[@]}" --set maxRegressors=39 &
done
wait
echo done
