#!/usr/bin/env bash
# Agent conditions (lockstep runner). Each agent supervises the aegis_full
# configuration with the same budget and seeds as the no-agent condition.
#   experiments/scripts/run_agents.sh <benchmark> <maxEvaluations> <parallel> <seeds> <agent> [label]
# agent: ucb1 | fuzzy | fuzzy:<rulebase.json> | llm (requires ANTHROPIC_API_KEY; never run by default)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$1"; BUDGET="$2"; PAR="$3"; SEEDS="$4"; AGENT="$5"; LABEL="${6:-agent_${AGENT%%:*}}"
DATA="$ROOT/experiments/data/processed/$BENCH"
case "$BENCH" in
  cascaded_tanks|wiener_hammerstein) TEST="$DATA/test.csv" ;;
  silverbox) TEST="$DATA/test_multisine.csv" ;;
esac
OUT="$ROOT/experiments/results/$BENCH/$LABEL"
mkdir -p "$OUT"
export ROOT BENCH BUDGET AGENT LABEL DATA TEST OUT
seq 1 "$SEEDS" | xargs -P "$PAR" -I{} bash -c '
  "$ROOT/experiments/bin/aegis_agent_runner.exe" --dll "$ROOT/cpp/build/aegis_core.dll" \
    --data "$DATA/est.csv" --data-test "$TEST" \
    --config "$ROOT/experiments/configs/conditions/aegis_full.json" --set maxEvaluations=$BUDGET \
    --agent "$AGENT" --seed {} --label "$LABEL" --output "$OUT" >> "$OUT/runner.log" 2>&1'
echo "agents $BENCH/$LABEL: $(ls "$OUT"/run_*.json 2>/dev/null | wc -l) runs"
