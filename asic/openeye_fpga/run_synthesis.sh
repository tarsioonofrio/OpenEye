#!/usr/bin/env bash
set -euo pipefail

flow_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$flow_dir/../.." && pwd)"
cluster_rows="${CLUSTER_ROWS:-1}"
cluster_columns="${CLUSTER_COLUMNS:-1}"
num_glb_iact="${NUM_GLB_IACT:-2}"
num_glb_psum="${NUM_GLB_PSUM:-2}"
num_glb_wght="${NUM_GLB_WGHT:-2}"
parallel_macs="${PARALLEL_MACS:-2}"
out_dir="${ASIC_FPGA_RESULTS_DIR:-$flow_dir/results/pe${num_glb_psum}x${num_glb_wght}_clusters-${cluster_rows}x${cluster_columns}_macs-${parallel_macs}}"
mkdir -p "$out_dir/generated" "$out_dir/reports" "$out_dir/netlist"
out_dir="$(cd -- "$out_dir" && pwd)"
export ASIC_FPGA_RESULTS_DIR="$out_dir"

export PYTHONPATH="$repo_root/src${PYTHONPATH:+:$PYTHONPATH}"
export TOPLEVEL=OpenEye_FPGA
export VH_PATH="$out_dir/generated"
export HDL_PATH="$repo_root/hdl"
export CLUSTER_ROWS="$cluster_rows" CLUSTER_COLUMNS="$cluster_columns"
export NUM_GLB_IACT="$num_glb_iact"
export NUM_GLB_PSUM="$num_glb_psum" NUM_GLB_WGHT="$num_glb_wght"
export IACT_RAM_CELLS=4 BUFFER_WIDTH=10 BUFFER_WIDTH_WGHT=12
export BUFFER_WIDTH_PSUM=14 BRANCHES=2 QUANT_AMOUNT=32
export DATA_PSUM_BITWIDTH=20 TRANS_WORDS=8 DMA_BITWIDTH=64
export PARALLEL_MACS="$parallel_macs" SPARSITY_EN=1
export TRANS_BITWIDTH_IACT=24 TRANS_BITWIDTH_WGHT=24
export STRIDE_ENABLED=0

(cd "$out_dir" && python -m open_eye.vh_file_creator)
python "$repo_root/src/open_eye/generator.py" \
    "$repo_root/test/cocotb_fpga" "$out_dir/generated" \
    "$out_dir/generated" "$out_dir/generated"

if ! command -v genus >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
    module use /soft64/modulefiles
    module load cadence/ddi/231
fi

rm -f "$out_dir/reports/area.rpt" \
    "$out_dir/reports/gates.rpt" \
    "$out_dir/reports/timing.rpt" \
    "$out_dir/reports/power_vectorless.rpt" \
    "$out_dir/netlist/OpenEye_FPGA_mapped.db" \
    "$out_dir/netlist/OpenEye_FPGA_mapped.v"
cd "$out_dir"
genus -batch -files "$flow_dir/run_synthesis.tcl" "$@"
test -s "$out_dir/netlist/OpenEye_FPGA_mapped.db"
test -s "$out_dir/netlist/OpenEye_FPGA_mapped.v"
test -s "$out_dir/reports/area.rpt"
