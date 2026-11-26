#!/usr/bin/env bash
# P6 (experiments/p6/P6_PREREG.md): refine the 240 E3 champions. One process
# per benchmark, cells in sequence, BelowNormal. Only est.csv is read.
#   experiments/p6/run_p6.sh <dir containing aegis_p6.exe>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$1/aegis_p6.exe"; OUT="$ROOT/experiments/results_p6"; mkdir -p "$OUT"
CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
printf '{"time":"%s","prereg_sha256":"%s","binary_sha256":"%s","config_sha256":"%s"}\n' "$(date -Iseconds)" \
  "$(sha256sum "$ROOT/experiments/p6/P6_PREREG.md" | cut -c1-64)" "$(sha256sum "$BIN" | cut -c1-64)" \
  "$(sha256sum "$CFG" | cut -c1-64)" >> "$OUT/MANIFEST.jsonl"
"$BIN" --selftest > "$OUT/selftest.log" 2>&1 || { echo "selftest failed"; exit 1; }
bench() {
  local B="$1" TE VE; case "$B" in cascaded_tanks) TE=819; VE=1024 ;; *) TE=16000; VE=20000 ;; esac
  local D="$ROOT/experiments/data/processed/$B/est.csv"
  printf '{"time":"%s","bench":"%s","data_sha256":"%s"}\n' "$(date -Iseconds)" "$B" "$(sha256sum "$D" | cut -c1-64)" >> "$OUT/MANIFEST.jsonl"
  for cell in mr39_zero_simulation mr39_zero_one_step mr8_zero_simulation mr8_zero_one_step \
              mr39_default_simulation mr39_default_one_step mr8_default_simulation mr8_default_one_step; do
    "$ROOT/experiments/phase0/lowprio.sh" "$BIN" --bench "$B" --data "$D" --config "$CFG" --train-end $TE --val-end $VE \
      --cell "$cell" --runs "$ROOT/experiments/results_phase0/$B/e3/$cell" --output "$OUT/$B.jsonl" >> "$OUT/$B.log" 2>&1
  done
  echo "$B done $(date -Iseconds)"
}
for b in cascaded_tanks wiener_hammerstein silverbox; do bench $b & done
wait
