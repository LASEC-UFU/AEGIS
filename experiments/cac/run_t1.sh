#!/usr/bin/env bash
# CAC training T1 (docs/architecture/15_PLANO_TREINO_CAC.md §3): impact map.
# CT only, E3 split (no test file), A1 package, seeds 41-50, branching at
# g in {50,150,400,1000}: one scripted action per branch, plus one control per
# seed. allowBudgetActions=true in every run (control included) so that
# stagnationLimit can be studied. Resumable: existing run files are skipped.
# Up to $PAR (default 6) runs at once, BelowNormal.
#   experiments/cac/run_t1.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; O="$ROOT/experiments/results_cac/t1"; mkdir -p "$O"
PAR="${PAR:-6}"
D="$ROOT/experiments/data/processed/cascaded_tanks/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS="--set trainEndRow=819 --set valEndRow=1024 --set testStartRow=1024 --set maxEvaluations=300000 --set maxRegressors=39 \
--set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 \
--set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set fitMethod=normal --set admissibilityVeto=true \
--set finalRefine=simulation --set allowBudgetActions=true"
# arm name -> relative or absolute action (A1 package; steps from the core schema)
ARMS=(
  "F+:mutationFactor+=0.15" "F-:mutationFactor-=0.15"
  "CR+:crossoverRate+=0.15" "CR-:crossoverRate-=0.15"
  "migRate+:migrationRate+=0.1" "migRate-:migrationRate-=0.1"
  "migInt+:migrationInterval+=25" "migInt-:migrationInterval-=25"
  "reinit+:reinitializationRatio+=0.1" "reinit-:reinitializationRatio-=0.1"
  "struct+:structuralMutationRate+=0.1" "struct-:structuralMutationRate-=0.1"
  "stagLim+:stagnationLimit+=500" "stagLim-:stagnationLimit-=500"
  "gamma+small:complexityPenalty+=0.01" "gamma+large:complexityPenalty+=0.05"
  "zeta+small:noInputPenalty+=0.1" "zeta-small:noInputPenalty-=0.1"
  "zeta+large:noInputPenalty+=0.5" "zeta-large:noInputPenalty-=0.5"
  "beta+small:denominatorPenalty+=0.05" "beta+large:denominatorPenalty+=0.25"
  "eta+small:stabilityPenalty+=0.1" "eta-small:stabilityPenalty-=0.1"
  "eta+large:stabilityPenalty+=0.5" "eta-large:stabilityPenalty-=0.5"
  "delta+small:exponentPenalty+=0.02" "delta+large:exponentPenalty+=0.1"
  "alpha+small:alpha+=0.05" "alpha+large:alpha+=0.25"
  "restart30:triggerRestart=0.3" "cataclysm:triggerRestart=1.0"
  "PLACEBO_theta+:freeRunPenalty+=0.5" "PLACEBO_theta-:freeRunPenalty-=0.5"
  "PLACEBO_horizon:freeRunHorizon+=100" "PLACEBO_restart5:triggerRestart=0.05"
)
jobs_list() {
  for s in 41 42 43 44 45 46 47 48 49 50; do
    echo "control|none|$s"
    for g in 50 150 400 1000; do
      for a in "${ARMS[@]}"; do echo "${a%%:*}@$g|script:${a#*:}@$g|$s"; done
    done
  done
}
one() {
  local name="${1%%|*}" rest="${1#*|}"; local agent="${rest%%|*}" seed="${rest##*|}"
  local out="$O/$name"; [ -f "$out/run_$seed.json" ] && return 0
  mkdir -p "$out"
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_dev/aegis_core.dll" --data "$D" --config "$CFG" $SETS \
    --agent "$agent" --seed "$seed" --output "$out" --label "t1_$name" > "$out/log_$seed.txt" 2>&1
}
export -f one; export O ROOT D CFG SETS
jobs_list | xargs -P "$PAR" -I{} bash -c 'one "$@"' _ {}
echo "T1 finished $(date -Iseconds)"
