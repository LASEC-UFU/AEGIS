#!/usr/bin/env bash
# CAC training T2+T3 (docs/architecture/15_PLANO_TREINO_CAC.md §8-§9): dose and
# timing of the fitness weights that mattered in T1 (beta, alpha, delta; gamma
# in minimal doses as harm control) on CT, WH and SB, validation only.
# Resumable; PAR (default 5) runs at once, BelowNormal.
#   experiments/cac/run_t2.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; B="$1"; PAR="${PAR:-5}"
O="$ROOT/experiments/results_cac/t2/$B"; mkdir -p "$O"
case "$B" in
  cascaded_tanks) TE=819; VE=1024; BUDGET=300000; SEEDS="51 52 53 54 55 56 57 58 59 60"; GS="25 100 400 1200" ;;
  *) TE=16000; VE=20000; BUDGET=30000; SEEDS="61 62 63 64 65"; GS="10 25 60 150" ;;
esac
D="$ROOT/experiments/data/processed/$B/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS="--set trainEndRow=$TE --set valEndRow=$VE --set testStartRow=$VE --set maxEvaluations=$BUDGET --set maxRegressors=39 \
--set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 \
--set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set fitMethod=normal --set admissibilityVeto=true \
--set finalRefine=simulation"
ARMS=(
  "beta+0.025:denominatorPenalty+=0.025" "beta+0.05:denominatorPenalty+=0.05" "beta+0.25:denominatorPenalty+=0.25"
  "alpha+0.05:alpha+=0.05" "alpha+0.25:alpha+=0.25"
  "delta+0.02:exponentPenalty+=0.02" "delta+0.1:exponentPenalty+=0.1"
  "gamma+0.002:complexityPenalty+=0.002" "gamma+0.005:complexityPenalty+=0.005"
  "PLACEBO_theta+:freeRunPenalty+=0.5"
)
jobs_list() {
  for s in $SEEDS; do
    echo "control|none|$s"
    for g in $GS; do for a in "${ARMS[@]}"; do echo "${a%%:*}@$g|script:${a#*:}@$g|$s"; done; done
  done
}
one() {
  local name="${1%%|*}" rest="${1#*|}"; local agent="${rest%%|*}" seed="${rest##*|}"
  local out="$O/$name"; [ -s "$out/run_$seed.json" ] && return 0
  mkdir -p "$out"
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_dev/aegis_core.dll" --data "$D" --config "$CFG" $SETS \
    --agent "$agent" --seed "$seed" --output "$out" --label "t2_$name" > "$out/log_$seed.txt" 2>&1
}
export -f one; export O ROOT D CFG SETS
jobs_list | xargs -P "$PAR" -I{} bash -c 'one "$@"' _ {}
echo "T2 $B finished $(date -Iseconds)"
