#!/usr/bin/env bash
# Generalisation of the learned fuzzy policy on unseen seeds (11-20).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="${1:-cascaded_tanks}"; BUDGET="${2:-300000}"; PAR="${3:-6}"
DATA="$ROOT/experiments/data/processed/$BENCH"
case "$BENCH" in
  cascaded_tanks|wiener_hammerstein) TEST="$DATA/test.csv" ;;
  silverbox) TEST="$DATA/test_multisine.csv" ;;
esac
OUTROOT="$ROOT/experiments/results_policy_eval/$BENCH"
run_cond() {
  local agent="$1" label="$2"
  local out="$OUTROOT/$label"; mkdir -p "$out"
  seq 11 20 | xargs -P "$PAR" -I{} "$ROOT/experiments/bin/aegis_agent_runner.exe" --dll "$ROOT/cpp/build/aegis_core.dll" \
    --data "$DATA/est.csv" --data-test "$TEST" --config "$ROOT/experiments/configs/conditions/aegis_full.json" \
    --set maxEvaluations=$BUDGET --agent "$agent" --seed {} --label "$label" --output "$out" >> "$out/runner.log" 2>&1
  echo "$label: $(ls "$out"/run_*.json | wc -l) runs"
}
run_cond none aegis_full
run_cond fuzzy agent_fuzzy
POLICY="$ROOT/experiments/policies/fuzzy_learned_ct.json"
command -v cygpath >/dev/null && POLICY="$(cygpath -m "$POLICY")"   # native Windows path for the .exe
[ "${ONLY_LEARNED:-0}" = 1 ] && { run_cond "fuzzy:$POLICY" agent_fuzzy_learned; exit 0; }
run_cond "fuzzy:$POLICY" agent_fuzzy_learned
run_cond ucb1 agent_ucb1
