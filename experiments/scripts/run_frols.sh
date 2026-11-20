#!/usr/bin/env bash
# FROLS (ERR-OLS) polynomial NARX baseline on a grid of (ny, nu, degree);
# the configuration is chosen by validation free-run RMSE only, never by test.
#   experiments/scripts/run_frols.sh <benchmark>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$1"
DATA="$ROOT/experiments/data/processed/$BENCH"
case "$BENCH" in
  cascaded_tanks|wiener_hammerstein) TEST="$DATA/test.csv" ;;
  silverbox) TEST="$DATA/test_multisine.csv" ;;
esac
OUT="$ROOT/experiments/results/$BENCH/frols"
mkdir -p "$OUT"
for g in "2 2 3" "5 5 2" "5 5 3" "10 10 2" "10 10 3"; do
  set -- $g
  "$ROOT/cpp/build/aegis_frols.exe" --data "$DATA/est.csv" --data-test "$TEST" \
    --config "$ROOT/experiments/configs/aegis_default.json" \
    --ny "$1" --nu "$2" --degree "$3" --max-terms 25 --output "$OUT/frols_ny$1_nu$2_d$3.json" >> "$OUT/frols.log" 2>&1
done
# Select by validation free-run RMSE (orig units) using a tiny Dart helper.
dart run "$ROOT/tool/experiments/select_frols.dart" "$OUT"
