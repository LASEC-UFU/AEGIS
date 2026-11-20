#!/usr/bin/env bash
# Phase 0, E1+E2 for one benchmark, with the pre-registered parameters
# (experiments/phase0/PHASE0_PREREG.md). Single process, BelowNormal priority.
#   experiments/phase0/run_e1e2.sh <cascaded_tanks|wiener_hammerstein|silverbox>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
B="$1"
case "$B" in
  cascaded_tanks)     TE=819;   VE=1024;  NY=2; NU=11; DEG=3 ;;
  wiener_hammerstein) TE=16000; VE=20000; NY=6; NU=12; DEG=5 ;;
  silverbox)          TE=16000; VE=20000; NY=7; NU=14; DEG=7 ;;
  *) echo "unknown benchmark $B"; exit 2 ;;
esac
OUT="$ROOT/experiments/results_phase0/$B"; mkdir -p "$OUT"
BIN="$ROOT/cpp/build_phase0/aegis_phase0.exe"
DATA="$ROOT/experiments/data/processed/$B/est.csv"
CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
CHAMP="$ROOT/experiments/results/$B/aegis_full"
MAN="$ROOT/experiments/results_phase0/MANIFEST.jsonl"
sha() { sha256sum "$1" | cut -c1-64; }
printf '{"time":"%s","benchmark":"%s","prereg_sha256":"%s","binary_sha256":"%s","config_sha256":"%s","est_csv_sha256":"%s","champion_files":%s,"args":"--train-end %s --val-end %s --dce-ny %s --dce-nu %s --dce-degree %s"}\n' \
  "$(date -Iseconds)" "$B" "$(sha "$ROOT/experiments/phase0/PHASE0_PREREG.md")" "$(sha "$BIN")" "$(sha "$CFG")" \
  "$(sha "$DATA")" "$(ls "$CHAMP"/run_*.json 2>/dev/null | wc -l)" "$TE" "$VE" "$NY" "$NU" "$DEG" >> "$MAN"
"$ROOT/experiments/phase0/lowprio.sh" "$BIN" --bench "$B" --data "$DATA" --config "$CFG" \
  --train-end "$TE" --val-end "$VE" --dce-ny "$NY" --dce-nu "$NU" --dce-degree "$DEG" \
  --champions "$CHAMP" --output "$OUT/e1e2.jsonl" > "$OUT/e1e2.log" 2>&1
echo "$B: $(wc -l < "$OUT/e1e2.jsonl") structures -> $OUT/e1e2.jsonl"
