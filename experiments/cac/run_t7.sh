#!/usr/bin/env bash
# CAC T7 (docs/architecture/16_REGULADORES_COMPLETOS.md §5): impact map of the
# new regulators (capacity, search, objective, events), deterministic
# branching as in T1, validation only, build cpp/build_cap.
# Every arm of a system shares the launch ceiling maxDelay=60 with
# maxDelayStart=40, so the maxDelay regulator has room (scoring row 60).
# Resumable; PAR (default 5) runs at once, BelowNormal.
#   experiments/cac/run_t7.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; B="$1"; PAR="${PAR:-5}"
O="$ROOT/experiments/results_cac/t7/$B"; mkdir -p "$O"
case "$B" in
  cascaded_tanks) TE=819; VE=1024; BUDGET=300000; SEEDS="81 82 83 84 85 86 87 88 89 90"; GS="100 400" ;;
  *) TE=16000; VE=20000; BUDGET=60000; SEEDS="66 67 68 69 70"; GS="50" ;;
esac
D="$ROOT/experiments/data/processed/$B/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS="--set trainEndRow=$TE --set valEndRow=$VE --set testStartRow=$VE --set maxEvaluations=$BUDGET --set maxRegressors=39 \
--set maxDelay=60 --set maxDelayStart=40 \
--set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 \
--set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set fitMethod=normal --set admissibilityVeto=true \
--set finalRefine=simulation --set postProcessGuard=true"
# name:script (relative to the branch generation G; '+25' items are applied 25 generations later)
ARMS=(
  "mr+10:maxRegressors+=10@G" "mr+20:maxRegressors+=10@G;maxRegressors+=10@G25" "mr-10:maxRegressors-=10@G"
  "terms+1:maxTermsPerReg+=1@G" "delay+10:maxDelay+=10@G" "delay+20:maxDelay+=10@G;maxDelay+=10@G25"
  "pmax+1:pmax+=1@G" "pmax-1:pmax-=1@G" "den+0.2:denominatorProbability+=0.2@G" "den-0.2:denominatorProbability-=0.2@G"
  "pop+50:populationSize+=50@G" "pop-25:populationSize-=25@G" "elite+2:elitismCount+=2@G"
  "varmut+0.2:variableMutationRate+=0.2@G" "jadeP+0.1:jadeP+=0.1@G" "rand1:mutationStrategy=1@G"
  "hyper0:hypermutation=0@G" "roles0:islandRoles=0@G" "onestep:errorMode=0@G"
  "seed0.2:seedFromChampion=0.2@G" "prune:pruneChampion=1@G" "advance:advancePhase=1@G"
  "PLACEBO_theta+:freeRunPenalty+=0.5@G"
)
# Static capacity arms (from the start, no agent): the headroom question.
STATIC=("STATIC_mr59@0:--set maxRegressors=59" "STATIC_mr79@0:--set maxRegressors=79")
jobs_list() {
  for s in $SEEDS; do
    echo "control|none||$s"
    for st in "${STATIC[@]}"; do echo "${st%%:*}|none|${st#*:}|$s"; done
    for g in $GS; do for a in "${ARMS[@]}"; do
      local sc="${a#*:}"; sc="${sc//@G25/@$((g + 25))}"; sc="${sc//@G/@$g}"
      echo "${a%%:*}@$g|script:$sc||$s"
    done; done
  done
}
one() {
  IFS='|' read -r name agent extra seed <<< "$1"
  local out="$O/$name"; [ -s "$out/run_$seed.json" ] && return 0
  mkdir -p "$out"
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_cap/aegis_core.dll" --data "$D" --config "$CFG" $SETS $extra \
    --agent "$agent" --seed "$seed" --output "$out" --label "t7_$name" > "$out/log_$seed.txt" 2>&1
}
export -f one; export O ROOT D CFG SETS
jobs_list | xargs -P "$PAR" -I{} bash -c 'one "$@"' _ {}
echo "T7 $B finished $(date -Iseconds)"
