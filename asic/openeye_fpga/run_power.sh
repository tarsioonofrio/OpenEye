#!/usr/bin/env bash
set -euo pipefail

flow_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
num_glb_wght="${ASIC_FPGA_NUM_GLB_WGHT:-3}"
case "$num_glb_wght" in
    3) pe_shape="4x3" ;;
    4) pe_shape="4x4" ;;
    *) echo "ASIC_FPGA_NUM_GLB_WGHT must be 3 or 4" >&2; exit 2 ;;
esac

out_dir="${ASIC_FPGA_RESULTS_DIR:-$flow_dir/results/pe${pe_shape}_clusters-1x2_macs-1}"
sim_dir="$out_dir/activity/rtl_sim"
: "${OPENEYE_SHM:=$sim_dir/dut.shm}"
: "${OPENEYE_DUT_INSTANCE:=OpenEye_FPGA_activity_tb.dut}"
export ASIC_FPGA_RESULTS_DIR="$out_dir"
export OPENEYE_SHM OPENEYE_DUT_INSTANCE

test -s "$OPENEYE_SHM/dut.dsn" || {
    echo "Validated Xcelium SHM not found: $OPENEYE_SHM" >&2
    echo "Run asic/openeye_fpga/run_activity.sh first." >&2
    exit 2
}
test -s "$out_dir/netlist/OpenEye_FPGA_mapped.db" || {
    echo "Mapped Genus database not found: $out_dir/netlist/OpenEye_FPGA_mapped.db" >&2
    exit 2
}

if ! command -v genus >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
    module use /soft64/modulefiles
    module load cadence/ddi/231
fi

exec genus -batch -files "$flow_dir/run_power.tcl" "$@"
