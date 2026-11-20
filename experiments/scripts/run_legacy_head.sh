#!/usr/bin/env bash
# Baseline of the ORIGINAL code (commit 9e4b1d8) with the app's default
# configuration, then re-evaluation of its models with the audited metric code
# (powerMode=legacy reproduces the original regressor semantics exactly;
# --refit 1 re-estimates the coefficients by the same least-squares problem to
# avoid the 8-decimal rounding of the original JSON export).
#
#   experiments/scripts/run_legacy_head.sh <benchmark> <maxGenerations> <parallel> <seeds>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$1"; MAXGEN="$2"; PAR="$3"; SEEDS="$4"
DATA="$ROOT/experiments/data/processed/$BENCH"
case "$BENCH" in
  cascaded_tanks|wiener_hammerstein) TEST="$DATA/test.csv" ;;
  silverbox) TEST="$DATA/test_multisine.csv" ;;
esac
OUT="$ROOT/experiments/results/$BENCH/legacy_head"
mkdir -p "$OUT"
BIN="$ROOT/experiments/bin/head-9e4b1d8/legacy_head_runner.exe"
BASE="$(tr -d '\n' < "$ROOT/experiments/configs/legacy_head_app_defaults.json")"
run_one() {
  local s="$1"
  local cfg="${BASE%\}},\"maxGenerations\":$MAXGEN,\"randomSeed\":$s}"
  PATH="$ROOT/experiments/bin/head-9e4b1d8:$PATH" "$BIN" "$DATA/est.csv" "$cfg" "$OUT/run_$s.json" > "$OUT/run_$s.log" 2>&1
}
export -f run_one
export ROOT BIN BASE MAXGEN OUT DATA
seq 1 "$SEEDS" | xargs -P "$PAR" -I{} bash -c 'run_one {}'
"$ROOT/cpp/build/aegis_evaluate_models.exe" --data "$DATA/est.csv" --data-test "$TEST" \
  --config '{"powerMode":"legacy","trainRatio":0.8,"maxDelay":40,"testTransient":50,"outputCol":1}' \
  --refit 1 --output "$OUT/evaluations.jsonl" "$OUT"/run_*.json
echo "legacy head $BENCH done"
