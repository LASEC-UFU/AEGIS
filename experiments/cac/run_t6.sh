#!/usr/bin/env bash
# CAC T6 (docs/architecture/15_PLANO_TREINO_CAC.md §13): CAC v4.1 + postProcessGuard
# against the A1 package + postProcessGuard (and, on CT, the A1 package alone). Validation only.
# Resumable; PAR (default 5) runs at once, BelowNormal.
#   experiments/cac/run_t6.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; B="$1"; PAR="${PAR:-5}"
O="$ROOT/experiments/results_cac/t6/$B"; mkdir -p "$O"
case "$B" in
  cascaded_tanks) TE=819; VE=1024; BUDGET=300000; SEEDS="71 72 73 74 75 76 77 78 79 80"; ARMS="none none_guard cac41_guard" ;;
  *) TE=16000; VE=20000; BUDGET=150000; SEEDS="36 37 38 39 40"; ARMS="none_guard cac41_guard" ;;
esac
D="$ROOT/experiments/data/processed/$B/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS="--set trainEndRow=$TE --set valEndRow=$VE --set testStartRow=$VE --set maxEvaluations=$BUDGET --set maxRegressors=39 \
--set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 \
--set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set fitMethod=normal --set admissibilityVeto=true \
--set finalRefine=simulation"
jobs_list() { for s in $SEEDS; do for a in $ARMS; do echo "$a|$s"; done; done; }
one() {
  local arm="${1%%|*}" seed="${1##*|}"; local agent="${arm%_guard}" extra=""
  [ "$arm" != "$agent" ] && extra="--set postProcessGuard=true"
  local out="$O/$arm"; [ -s "$out/run_$seed.json" ] && return 0
  mkdir -p "$out"
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_dev/aegis_core.dll" --data "$D" --config "$CFG" $SETS $extra \
    --agent "$agent" --seed "$seed" --output "$out" --label "t6_$arm" > "$out/log_$seed.txt" 2>&1
}
export -f one; export O ROOT D CFG SETS ARMS
jobs_list | xargs -P "$PAR" -I{} bash -c 'one "$@"' _ {}
echo "T6 $B finished $(date -Iseconds)"
