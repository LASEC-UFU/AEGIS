#!/usr/bin/env bash
# CAC T8 (docs/architecture/16_REGULADORES_COMPLETOS.md §9): CAC v5 (measured map
# of the full regulator set, T7) against the A1 package. Validation only.
# CTX=1 adds validationContext to every arm; pre-registered rule: CTX=1 iff
# T6b criterion 1 (doc 15 §15.2) is met. Resumable; PAR (default 5), BelowNormal.
#   CTX=<0|1> experiments/cac/run_t8.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; B="$1"; PAR="${PAR:-5}"; CTX="${CTX:?set CTX=0 or CTX=1}"
O="$ROOT/experiments/results_cac/t8/$B"; mkdir -p "$O"
case "$B" in
  cascaded_tanks) TE=819; VE=1024; BUDGET=300000; SEEDS="101 102 103 104 105 106 107 108 109 110"; ARMS="none cac5" ;;
  *) TE=16000; VE=20000; BUDGET=60000; SEEDS="71 72 73 74 75 76 77 78 79 80"; ARMS="none cac5 STATIC_pop25" ;;
esac
D="$ROOT/experiments/data/processed/$B/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS="--set trainEndRow=$TE --set valEndRow=$VE --set testStartRow=$VE --set maxEvaluations=$BUDGET --set maxRegressors=39 \
--set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 \
--set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set fitMethod=normal --set admissibilityVeto=true \
--set finalRefine=simulation --set postProcessGuard=true"
[ "$CTX" = 1 ] && SETS="$SETS --set validationContext=true"
echo "T8 $B CTX=$CTX $(date -Iseconds)" >> "$O/ctx.txt"
jobs_list() { for s in $SEEDS; do for a in $ARMS; do echo "$a|$s"; done; done; }
one() {
  local arm="${1%%|*}" seed="${1##*|}" agent extra=""
  case "$arm" in
    STATIC_pop25) agent=none; extra="--set populationSize=25" ;;  # reference: the v5 dose from the start
    *) agent="$arm" ;;
  esac
  local out="$O/$arm"; [ -s "$out/run_$seed.json" ] && return 0
  mkdir -p "$out"
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_sig/aegis_core.dll" --data "$D" --config "$CFG" $SETS $extra \
    --agent "$agent" --seed "$seed" --output "$out" --label "t8_$arm" > "$out/log_$seed.txt" 2>&1
}
export -f one; export O ROOT D CFG SETS
jobs_list | xargs -P "$PAR" -I{} bash -c 'one "$@"' _ {}
echo "T8 $B finished $(date -Iseconds)"
