#!/usr/bin/env bash
# postProcessGuard ablation (CT, validation only, A1 package): seeds 21-30,
# no agent and CAC v3, guard on. Plus one guard-off reproduction check.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; O="$ROOT/experiments/results_perf/guard"; mkdir -p "$O"
D="$ROOT/experiments/data/processed/cascaded_tanks/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS=(--set trainEndRow=819 --set valEndRow=1024 --set testStartRow=1024 --set maxEvaluations=300000 --set maxRegressors=39
      --set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0
      --set denominatorPenalty=0 --set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0
      --set fitMethod=normal --set admissibilityVeto=true --set finalRefine=simulation)
run() { "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
  --dll "$ROOT/cpp/build_dev/aegis_core.dll" --data "$D" --config "$CFG" "${SETS[@]}" "${@:3}" \
  --agent "$1" --seed "$2" --label guard >> "$O/log.txt" 2>&1; }
run none 21 --output "$O/off_none"
for s in 21 22 23 24 25 26 27 28 29 30; do
  run none $s --set postProcessGuard=true --output "$O/none" &
  run cac $s --set postProcessGuard=true --output "$O/cac" &
  wait
done
echo done
