#!/usr/bin/env bash
# Waits (polling once a minute) for a condition, then runs a Phase-0 step.
#   wait_then.sh sb_champions   -> E1/E2 on silverbox once its 10 aegis_full runs exist
#   wait_then.sh protocol_done  -> E3 on the three benchmarks once the 1.1.0 protocol ended
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
case "$1" in
  sb_champions)
    until [ "$(ls "$ROOT"/experiments/results/silverbox/aegis_full/run_*.json 2>/dev/null | wc -l)" -ge 10 ]; do sleep 60; done
    "$ROOT/experiments/phase0/run_e1e2.sh" silverbox
    dart run "$ROOT/tool/experiments/phase0_summary.dart" "$ROOT/experiments/results_phase0" > /dev/null
    ;;
  protocol_done)
    until grep -q "\[resume\] done" "$ROOT/experiments/results/protocol_resume.log" 2>/dev/null; do sleep 60; done
    for b in cascaded_tanks wiener_hammerstein silverbox; do "$ROOT/experiments/phase0/run_e3.sh" "$b"; done
    dart run "$ROOT/tool/experiments/phase0_e3_summary.dart" "$ROOT/experiments/results_phase0" > /dev/null
    ;;
  *) echo "unknown step"; exit 2 ;;
esac
echo "[phase0] $1 finished $(date -Iseconds)"
