#!/usr/bin/env bash
set -euo pipefail

flow_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$flow_dir/../.." && pwd)"
num_glb_wght="${ASIC_FPGA_NUM_GLB_WGHT:-3}"
case "$num_glb_wght" in
    3) pe_shape="4x3" ;;
    4) pe_shape="4x4" ;;
    *) echo "ASIC_FPGA_NUM_GLB_WGHT must be 3 or 4" >&2; exit 2 ;;
esac

out_dir="${ASIC_FPGA_RESULTS_DIR:-$flow_dir/results/pe${pe_shape}_clusters-1x2_macs-1}"
out_dir="$(mkdir -p "$out_dir" && cd "$out_dir" && pwd)"
sim_dir="$out_dir/activity/rtl_sim"
mkdir -p "$sim_dir"
rm -rf "$sim_dir/dut.shm"

source /etc/profile.d/modules.sh
module use /soft64/modulefiles
module load cadence/xcelium/2303

export ASIC_FPGA_RESULTS_DIR="$out_dir"
export ASIC_FPGA_NUM_GLB_WGHT="$num_glb_wght"
export OPENEYE_SIMULATOR=xcelium
export OPENEYE_CLOCK_PERIOD_NS=2
export OPENEYE_SIM_BUILD_DIR="$sim_dir"
export ASIC_CAPTURE_SHM=1
export CLUSTER_ROWS=1 CLUSTER_COLUMNS=2
export NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT="$num_glb_wght"
export PARALLEL_MACS=1 SERIAL=1 SPARSITY_EN=1
export OPENEYE_LAYER_SEED=123

cd "$repo_root"
export PYTHONPATH="$repo_root/src${PYTHONPATH:+:$PYTHONPATH}"
.venv/bin/python -m pytest -x -q -s \
    test/cocotb_fpga/test_single_layers.py::test_power_activity_official_conv_c2_f6_fpga

test -s "$sim_dir/dut.shm/Design.dsn"
test -s "$sim_dir/cocotb_sim.log"
grep -q 'TESTS=1 PASS=1 FAIL=0' "$sim_dir/cocotb_sim.log"
echo "Validated SHM: $sim_dir/dut.shm"
echo "Parameters: PE=$pe_shape clusters=1x2 MACs/PE=1 SERIAL=1 clock=2ns workload=C2/F6/32x32/kernel3x3/seed123"
