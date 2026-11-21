#!/usr/bin/env bash
# Resume of the iteration-2 protocol after the machine hang of 2026-11-20
# (~11:12 local, during the start of WH agent_fuzzy). Same binaries,
# configurations, budgets and seeds as run_protocol.sh; only the stages that
# had not finished are run. Each run is single-seeded and deterministic, so
# lower parallelism does not change results, only wall time (wallSeconds of
# these stages are not comparable with stages run at 16 jobs).
#
# Load limits: at most PAR processes (default 6), legacy stage LEGACY_PAR
# (default 4; the original code uses 3 threads per run), and the whole tree
# runs at BelowNormal priority (Windows children inherit it). A monitor appends
# free RAM / CPU load / process count every 60 s to protocol_monitor.log.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/experiments/scripts"
PAR="${PAR:-6}"
LEGACY_PAR="${LEGACY_PAR:-4}"
CORE="aegis_full aegis_sim de_rand1 single_island no_curriculum no_freerun polynomial_only"
MON="$ROOT/experiments/results/protocol_monitor.log"

if [ -r /proc/$$/winpid ]; then
  WINPID="$(cat /proc/$$/winpid)"
  powershell.exe -NoProfile -Command "(Get-Process -Id $WINPID).PriorityClass = 'BelowNormal'" \
    && echo "[resume] priority BelowNormal (winpid $WINPID)"
fi

monitor() {
  while kill -0 "$1" 2>/dev/null; do
    powershell.exe -NoProfile -Command \
      "\$o = Get-CimInstance Win32_OperatingSystem; \$c = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 1).CounterSamples[0].CookedValue); \$n = @(Get-Process | Where-Object { \$_.ProcessName -match 'aegis|legacy_head' }).Count; '{0:s} freeRAM_GB={1:N1} cpu%={2} aegis_procs={3}' -f (Get-Date), (\$o.FreePhysicalMemory/1MB), \$c, \$n" \
      >> "$MON" 2>/dev/null
    sleep 60
  done
}
monitor $$ &

echo "[resume] start $(date -Iseconds) PAR=$PAR LEGACY_PAR=$LEGACY_PAR"
"$S/run_agents.sh" wiener_hammerstein 150000 "$PAR" 10 fuzzy
"$S/run_conditions.sh" silverbox 150000 "$PAR" 10 $CORE
"$S/run_legacy_head.sh" wiener_hammerstein 1000 "$LEGACY_PAR" 10
"$S/run_legacy_head.sh" silverbox 1000 "$LEGACY_PAR" 10
echo "[resume] done $(date -Iseconds)"
