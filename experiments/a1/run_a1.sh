#!/usr/bin/env bash
# A1 runs (experiments/a1/A1_PREREG.md): 3 benchmarks x seeds 1-10, test file
# appended exactly as run_conditions.sh. Test metrics are written but NOT read
# until all runs finish (blinding). Up to 6 runs at once, BelowNormal.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/cpp/build_a1/aegis_batch.exe"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
OUTR="$ROOT/experiments/results_a1"; mkdir -p "$OUTR"
A1=(--set maxRegressors=39 --set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 --set alpha=0
    --set gammaAnnealStart=0 --set gammaAnnealEnd=0 --set errorMode=simulation --set freeRunHorizon=0
    --set fitMethod=normal --set admissibilityVeto=true --set vetoTopK=5 --set finalRefine=simulation)
printf '{"time":"%s","commit":"%s","prereg_sha256":"%s","analysis_sha256":"%s","binary_sha256":"%s","config_sha256":"%s"}\n' \
  "$(date -Iseconds)" "$(git -C "$ROOT" rev-parse HEAD)" "$(sha256sum "$ROOT/experiments/a1/A1_PREREG.md" | cut -c1-64)" \
  "$(sha256sum "$ROOT/tool/experiments/a1_analysis.dart" | cut -c1-64)" "$(sha256sum "$BIN" | cut -c1-64)" \
  "$(sha256sum "$CFG" | cut -c1-64)" >> "$OUTR/MANIFEST.jsonl"
bench() { # name budget jobs
  local B="$1" BUDGET="$2" J="$3" D="$ROOT/experiments/data/processed/$1" TEST
  case "$B" in silverbox) TEST="$D/test_multisine.csv" ;; *) TEST="$D/test.csv" ;; esac
  local OUT="$OUTR/$B"; mkdir -p "$OUT"
  "$ROOT/experiments/phase0/lowprio.sh" "$BIN" --data "$D/est.csv" --data-test "$TEST" --config "$CFG" "${A1[@]}" \
    --set "maxEvaluations=$BUDGET" --runs 10 --seed-start 1 --jobs "$J" --label a1 --output "$OUT" > "$OUT/batch.log" 2>&1
  echo "$B $(tail -1 "$OUT/batch.log") $(date -Iseconds)"
}
bench cascaded_tanks 300000 6
bench wiener_hammerstein 150000 3 &
bench silverbox 150000 3 &
wait
