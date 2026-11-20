#!/usr/bin/env bash
# Runs AEGIS ablation conditions (no agent) with aegis_batch.
#
#   experiments/scripts/run_conditions.sh <benchmark> <maxEvaluations> <jobs> <seeds> [condition ...]
#
# benchmark: cascaded_tanks | wiener_hammerstein | silverbox
# Conditions are the files experiments/configs/conditions/<name>.json
# (default: all). Seeds 1..<seeds>. Results: experiments/results/<benchmark>/<condition>/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$1"; BUDGET="$2"; JOBS="$3"; SEEDS="$4"; shift 4
CONDS=("$@")
if [ ${#CONDS[@]} -eq 0 ]; then
  CONDS=()
  for f in "$ROOT"/experiments/configs/conditions/*.json; do CONDS+=("$(basename "$f" .json)"); done
fi
DATA="$ROOT/experiments/data/processed/$BENCH"
case "$BENCH" in
  cascaded_tanks|wiener_hammerstein) TEST="$DATA/test.csv" ;;
  silverbox) TEST="$DATA/test_multisine.csv" ;;
  *) echo "unknown benchmark $BENCH"; exit 2 ;;
esac
BIN="$ROOT/cpp/build/aegis_batch.exe"
[ -x "$BIN" ] || BIN="$ROOT/cpp/build/aegis_batch"
for c in "${CONDS[@]}"; do
  OUT="$ROOT/experiments/results/$BENCH/$c"
  mkdir -p "$OUT"
  echo "=== $BENCH / $c ($(date -Iseconds)) ==="
  "$BIN" --data "$DATA/est.csv" --data-test "$TEST" \
    --config "$ROOT/experiments/configs/conditions/$c.json" \
    --set "maxEvaluations=$BUDGET" --runs "$SEEDS" --seed-start 1 --jobs "$JOBS" \
    --label "$c" --output "$OUT" > "$OUT/batch.log" 2>&1 || echo "  (non-zero exit, see $OUT/batch.log)"
  tail -1 "$OUT/batch.log"
done
