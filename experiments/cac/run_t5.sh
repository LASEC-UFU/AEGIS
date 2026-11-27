#!/usr/bin/env bash
# CAC T5 (docs/architecture/15_PLANO_TREINO_CAC.md §11): validation of CAC v4
# against the A1 package without agent and CAC v3, validation only.
# Resumable; PAR (default 5) runs at once, BelowNormal.
#   experiments/cac/run_t5.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; B="$1"; PAR="${PAR:-5}"
O="$ROOT/experiments/results_cac/t5/$B"; mkdir -p "$O"
case "$B" in
  cascaded_tanks) TE=819; VE=1024; BUDGET=300000; SEEDS="21 22 23 24 25 26 27 28 29 30" ;;
  *) TE=16000; VE=20000; BUDGET=150000; SEEDS="31 32 33 34 35" ;;
esac
D="$ROOT/experiments/data/processed/$B/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS="--set trainEndRow=$TE --set valEndRow=$VE --set testStartRow=$VE --set maxEvaluations=$BUDGET --set maxRegressors=39 \
--set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 \
--set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set fitMethod=normal --set admissibilityVeto=true \
--set finalRefine=simulation"
jobs_list() { for s in $SEEDS; do for a in none cac cac4; do echo "$a|$s"; done; done; }
one() {
  local agent="${1%%|*}" seed="${1##*|}"
  local out="$O/$agent"; [ -s "$out/run_$seed.json" ] && return 0
  mkdir -p "$out"
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_dev/aegis_core.dll" --data "$D" --config "$CFG" $SETS \
    --agent "$agent" --seed "$seed" --output "$out" --label "t5_$agent" > "$out/log_$seed.txt" 2>&1
}
export -f one; export O ROOT D CFG SETS
jobs_list | xargs -P "$PAR" -I{} bash -c 'one "$@"' _ {}
echo "T5 $B finished $(date -Iseconds)"
