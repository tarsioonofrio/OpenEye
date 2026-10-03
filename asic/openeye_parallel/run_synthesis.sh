#!/usr/bin/env bash
set -euo pipefail

flow_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v genus >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
    module use /soft64/modulefiles
    module load cadence/ddi/231
fi
genus -batch -files "$flow_dir/run_synthesis.tcl" "$@"
test -s "$flow_dir/results/netlist/OpenEye_Parallel_mapped.db"
test -s "$flow_dir/results/netlist/OpenEye_Parallel_mapped.v"
test -s "$flow_dir/results/reports/area.rpt"
