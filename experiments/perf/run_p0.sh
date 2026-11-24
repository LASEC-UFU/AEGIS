#!/usr/bin/env bash
# P0 profiling (docs/architecture/10_AUDITORIA_DO_09.md §11.3, 12 §6).
# Instrumented build (-DAEGIS_PROFILE) of the unchanged 1.1.0 source, built in a
# separate directory; the frozen cpp/build and cpp/build_phase0 are not touched.
# Same split and overrides as E3 (PHASE0_PREREG §3); no test file; one run per
# process (--jobs 1) so each probe file maps to one run. Validation only.
#   experiments/perf/run_p0.sh <prof_build_dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$1/aegis_batch.exe"
CFG="$ROOT/experiments/configs/conditions/aegis_full.json"
ZERO=(--set complexityPenalty=0 --set exponentPenalty=0 --set denominatorPenalty=0 --set alpha=0
      --set gammaAnnealStart=0 --set gammaAnnealEnd=0)
run() { # bench budget cell
  local B="$1" BUDGET="$2" cell="$3" TE VE
  case "$B" in cascaded_tanks) TE=819; VE=1024 ;; *) TE=16000; VE=20000 ;; esac
  local mr="${cell#mr}"; mr="${mr%%_*}"; local em="${cell##*_}"; [ "$em" = step ] && em=one_step
  local args=(--set "trainEndRow=$TE" --set "valEndRow=$VE" --set "testStartRow=$VE" --set "maxEvaluations=$BUDGET"
              --set "maxRegressors=$mr" --set "errorMode=$em")
  [ "$em" = simulation ] && args+=(--set freeRunHorizon=0)
  case "$cell" in *_zero_*) args+=("${ZERO[@]}") ;; esac
  local OUT="$ROOT/experiments/results_perf/p0/$B/$cell"; mkdir -p "$OUT"
  AEGIS_PROFILE_OUT="$OUT/probe" AEGIS_PROFILE_STRUCT=1 "$ROOT/experiments/phase0/lowprio.sh" "$BIN" \
    --data "$ROOT/experiments/data/processed/$B/est.csv" --config "$CFG" "${args[@]}" \
    --runs 1 --seed-start 21 --jobs 1 --label "$cell" --output "$OUT" > "$OUT/batch.log" 2>&1
  echo "$B $cell $(tail -1 "$OUT/batch.log") $(date -Iseconds)"
}
for c in mr8_default_simulation mr39_zero_simulation mr39_zero_one_step; do run cascaded_tanks 300000 "$c" & done
for c in mr8_default_simulation mr39_zero_simulation mr39_zero_one_step; do run wiener_hammerstein 30000 "$c" & done
wait
