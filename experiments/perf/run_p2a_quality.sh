#!/usr/bin/env bash
# P2'a quality (experiments/perf/P2A_PREREG.md §3): E3 cell mr39_zero_simulation,
# seeds 21-30, fitMethod=normal, one process per benchmark, BelowNormal.
#   experiments/perf/run_p2a_quality.sh <dir containing aegis_batch.exe>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$1/aegis_batch.exe"; CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
ZERO=(--set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 --set alpha=0 --set gammaAnnealStart=0 --set gammaAnnealEnd=0)
OUTR="$ROOT/experiments/results_perf/p2a_quality"; mkdir -p "$OUTR"
printf '{"time":"%s","prereg_sha256":"%s","binary_sha256":"%s"}\n' "$(date -Iseconds)" \
  "$(sha256sum "$ROOT/experiments/perf/P2A_PREREG.md" | cut -c1-64)" "$(sha256sum "$BIN" | cut -c1-64)" >> "$OUTR/MANIFEST.jsonl"
bench() {
  local B="$1" TE VE BUDGET; case "$B" in cascaded_tanks) TE=819; VE=1024; BUDGET=300000 ;; *) TE=16000; VE=20000; BUDGET=150000 ;; esac
  local OUT="$OUTR/$B"; mkdir -p "$OUT"
  "$ROOT/experiments/phase0/lowprio.sh" "$BIN" --data "$ROOT/experiments/data/processed/$B/est.csv" --config "$CFG" \
    --set "trainEndRow=$TE" --set "valEndRow=$VE" --set "testStartRow=$VE" --set "maxEvaluations=$BUDGET" \
    --set maxRegressors=39 --set errorMode=simulation --set freeRunHorizon=0 "${ZERO[@]}" --set fitMethod=normal \
    --runs 10 --seed-start 21 --jobs 1 --label p2a_mr39_zero_simulation --output "$OUT" > "$OUT/batch.log" 2>&1
  echo "$B $(tail -1 "$OUT/batch.log") $(date -Iseconds)"
}
for b in cascaded_tanks wiener_hammerstein silverbox; do bench $b & done
wait
