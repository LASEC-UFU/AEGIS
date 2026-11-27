#!/usr/bin/env bash
# CAC T6b (docs/architecture/15_PLANO_TREINO_CAC.md §15): validationContext, the
# search validation in the reported convention (T6 finding), with and without
# CAC v4.1. Validation only. Resumable; PAR (default 1: runs next to T7) at once, BelowNormal.
#   experiments/cac/run_t6b.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; B="$1"; PAR="${PAR:-1}"
O="$ROOT/experiments/results_cac/t6b/$B"; mkdir -p "$O"
case "$B" in
  cascaded_tanks) TE=819; VE=1024; BUDGET=300000; SEEDS="91 92 93 94 95 96 97 98 99 100" ;;
  *) TE=16000; VE=20000; BUDGET=150000; SEEDS="41 42 43 44 45" ;;
esac
ARMS="none_guard none_guard_ctx cac41_guard_ctx"
D="$ROOT/experiments/data/processed/$B/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS="--set trainEndRow=$TE --set valEndRow=$VE --set testStartRow=$VE --set maxEvaluations=$BUDGET --set maxRegressors=39 \
--set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 \
--set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set fitMethod=normal --set admissibilityVeto=true \
--set finalRefine=simulation --set postProcessGuard=true"
jobs_list() { for s in $SEEDS; do for a in $ARMS; do echo "$a|$s"; done; done; }
one() {
  local arm="${1%%|*}" seed="${1##*|}"; local agent="${arm%%_guard*}" extra=""
  [[ "$arm" == *_ctx ]] && extra="--set validationContext=true"
  local out="$O/$arm"; [ -s "$out/run_$seed.json" ] && return 0
  mkdir -p "$out"
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_sig/aegis_core.dll" --data "$D" --config "$CFG" $SETS $extra \
    --agent "$agent" --seed "$seed" --output "$out" --label "t6b_$arm" > "$out/log_$seed.txt" 2>&1
}
export -f one; export O ROOT D CFG SETS ARMS
jobs_list | xargs -P "$PAR" -I{} bash -c 'one "$@"' _ {}
echo "T6b $B finished $(date -Iseconds)"
