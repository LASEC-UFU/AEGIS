#!/usr/bin/env bash
# Full experimental protocol (iteration 2). Stages run sequentially; each
# stage parallelises over seeds. See experiments/EXPERIMENT_LOG.md.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/experiments/scripts"
ALL="aegis_full aegis_sim de_rand1 single_island no_migration no_curriculum no_freerun polynomial_only no_roles_regimes signed_continuous no_postprocessing"
CORE="aegis_full aegis_sim de_rand1 single_island no_curriculum no_freerun polynomial_only"
echo "[protocol] start $(date -Iseconds)"
"$S/run_conditions.sh" cascaded_tanks 300000 16 10 $ALL
"$S/run_agents.sh" cascaded_tanks 300000 10 10 ucb1
"$S/run_agents.sh" cascaded_tanks 300000 10 10 fuzzy
"$S/run_conditions.sh" wiener_hammerstein 150000 16 10 $CORE
"$S/run_agents.sh" wiener_hammerstein 150000 10 10 ucb1
"$S/run_agents.sh" wiener_hammerstein 150000 10 10 fuzzy
"$S/run_conditions.sh" silverbox 150000 16 10 $CORE
"$S/run_legacy_head.sh" wiener_hammerstein 1000 10 10
"$S/run_legacy_head.sh" silverbox 1000 10 10
echo "[protocol] done $(date -Iseconds)"
