#!/usr/bin/env bash
set -euo pipefail

flow_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$flow_dir/../.." && pwd)"
out_dir="$flow_dir/results"
mkdir -p "$out_dir/generated" "$out_dir/reports" "$out_dir/netlist"

export PYTHONPATH="$repo_root/src${PYTHONPATH:+:$PYTHONPATH}"
export TOPLEVEL=OpenEye_FPGA
export VH_PATH="$out_dir/generated"
export HDL_PATH="$repo_root/hdl"
export CLUSTER_ROWS=4 CLUSTER_COLUMNS=2
export NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT=3
export IACT_RAM_CELLS=4 BUFFER_WIDTH=10 BUFFER_WIDTH_WGHT=12
export BUFFER_WIDTH_PSUM=14 BRANCHES=2 QUANT_AMOUNT=32
export DATA_PSUM_BITWIDTH=20 TRANS_WORDS=8 DMA_BITWIDTH=64
export PARALLEL_MACS=2 SPARSITY_EN=1
export TRANS_BITWIDTH_IACT=24 TRANS_BITWIDTH_WGHT=24
export STRIDE_ENABLED=0

python -m open_eye.vh_file_creator
python "$repo_root/src/open_eye/generator.py" \
    "$repo_root/test/cocotb_fpga" "$out_dir/generated" \
    "$out_dir/generated" "$out_dir/generated"

if ! command -v genus >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
    module use /soft64/modulefiles
    module load cadence/ddi/231
fi

genus -batch -files "$flow_dir/run_synthesis.tcl" "$@"
test -s "$out_dir/netlist/OpenEye_FPGA_mapped.db"
test -s "$out_dir/netlist/OpenEye_FPGA_mapped.v"
test -s "$out_dir/reports/area.rpt"
