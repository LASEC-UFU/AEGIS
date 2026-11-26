#!/usr/bin/env bash
# CAC development (doc 14): CT only, E3 split (no test file), A1 package.
# train: seeds 31-40 in sequence, the arm table carried from run to run;
# eval:  seeds 21-23 with the trained table (frozen) and without a table.
#   experiments/perf/cac_dev.sh <out_dir>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; O="$1"; mkdir -p "$O"
D="$ROOT/experiments/data/processed/cascaded_tanks/est.csv"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SETS=(--set trainEndRow=819 --set valEndRow=1024 --set testStartRow=1024 --set maxEvaluations=300000 --set maxRegressors=39
      --set errorMode=simulation --set freeRunHorizon=0 --set complexityPenalty=0 --set exponentPenalty=0
      --set denominatorPenalty=0 --set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0
      --set fitMethod=normal --set admissibilityVeto=true --set finalRefine=simulation)
run() { # agent seed outdir
  "$ROOT/experiments/phase0/lowprio.sh" dart run "$ROOT/tool/experiments/run_agent_experiment.dart" \
    --dll "$ROOT/cpp/build_a1/aegis_core.dll" --data "$D" --config "$CFG" "${SETS[@]}" \
    --agent "$1" --seed "$2" --output "$3" --label cac_dev >> "$O/log.txt" 2>&1
}
T="$O/table.json"
for s in 31 32 33 34 35 36 37 38 39 40; do
  if [ -f "$T" ]; then run "cac:$T" $s "$O/train"; else run cac $s "$O/train"; fi
  dart run "$ROOT/tool/experiments/cac_table.dart" "$O/train/run_$s.json" "$T" >> "$O/log.txt" 2>&1
done
cp "$T" "$O/table_frozen.json"
for s in 21 22 23; do run "cac:$O/table_frozen.json" $s "$O/eval_trained" & run cac $s "$O/eval_untrained"; wait; done
echo done
