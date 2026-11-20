#!/usr/bin/env bash
# Phase 0, E3: configuration-only screening with the frozen 1.1.0 binary
# (experiments/phase0/PHASE0_PREREG.md §3). Run ONLY after the 1.1.0 protocol
# has finished. No test file is passed; the split is explicit, so the test
# segment is empty. At most PAR (default 6) runs at once, BelowNormal priority.
#   experiments/phase0/run_e3.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
B="$1"
PAR="${PAR:-6}"
case "$B" in
  cascaded_tanks)     TE=819;   VE=1024;  BUDGET=300000 ;;
  wiener_hammerstein) TE=16000; VE=20000; BUDGET=150000 ;;
  silverbox)          TE=16000; VE=20000; BUDGET=150000 ;;
  *) echo "unknown benchmark $B"; exit 2 ;;
esac
if pgrep -f "run_protocol" >/dev/null 2>&1 || ps -W | grep -qi "aegis_agent_runner\|legacy_head_runner"; then
  echo "the 1.1.0 protocol still seems to be running; E3 must wait"; exit 3
fi
BIN="$ROOT/cpp/build/aegis_batch.exe"
DATA="$ROOT/experiments/data/processed/$B/est.csv"
CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
SPLIT=(--set "trainEndRow=$TE" --set "valEndRow=$VE" --set "testStartRow=$VE" --set "maxEvaluations=$BUDGET")
ZERO=(--set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 --set alpha=0
      --set gammaAnnealStart=0 --set gammaAnnealEnd=0)
MAN="$ROOT/experiments/results_phase0/MANIFEST.jsonl"
for mr in 8 39; do
  for pen in default zero; do
    for em in one_step simulation; do
      cell="mr${mr}_${pen}_${em}"
      OUT="$ROOT/experiments/results_phase0/$B/e3/$cell"
      mkdir -p "$OUT"
      args=("${SPLIT[@]}" --set "maxRegressors=$mr" --set "errorMode=$em")
      [ "$em" = simulation ] && args+=(--set freeRunHorizon=0)
      [ "$pen" = zero ] && args+=("${ZERO[@]}")
      printf '{"time":"%s","experiment":"E3","benchmark":"%s","cell":"%s","binary_sha256":"%s","config_sha256":"%s","overrides":"%s"}\n' \
        "$(date -Iseconds)" "$B" "$cell" "$(sha256sum "$BIN" | cut -c1-64)" "$(sha256sum "$CFG" | cut -c1-64)" "${args[*]}" >> "$MAN"
      echo "=== E3 $B / $cell ($(date -Iseconds)) ==="
      "$ROOT/experiments/phase0/lowprio.sh" "$BIN" --data "$DATA" --config "$CFG" "${args[@]}" \
        --runs 10 --seed-start 21 --jobs "$PAR" --label "$cell" --output "$OUT" > "$OUT/batch.log" 2>&1 \
        || echo "  (non-zero exit, see $OUT/batch.log)"
      tail -1 "$OUT/batch.log"
    done
  done
done
