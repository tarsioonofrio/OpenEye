#!/usr/bin/env bash
set -euo pipefail

flow_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${OPENEYE_SHM:?Set OPENEYE_SHM to a validated Xcelium .shm directory}"
: "${OPENEYE_DUT_INSTANCE:?Set OPENEYE_DUT_INSTANCE to the DUT instance path inside the SHM database}"
if ! command -v genus >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
    module use /soft64/modulefiles
    module load cadence/ddi/231
fi
export OPENEYE_SHM
export OPENEYE_DUT_INSTANCE
exec genus -batch -files "$flow_dir/run_power.tcl" "$@"
