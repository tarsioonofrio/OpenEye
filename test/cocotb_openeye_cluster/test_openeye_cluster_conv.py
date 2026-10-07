"""Run the PE-cluster convolution reproducer through OpenEye_Cluster."""

import os
from pathlib import Path

import cocotb_test.simulator


ROOT = Path(__file__).resolve().parents[2]
HDL = ROOT / "hdl"


def test_openeye_cluster_conv_reproducer(tmp_path):
    sources = [
        "OpenEye_Cluster.v", "GLB_cluster.v", "af_cluster.v", "bano_cluster.v",
        "delay_cluster.v", "router_iact.v", "router_wght.v", "router_psum.v",
        "PE_cluster.v", "PE.v", "adder.v", "adder_tree.v", "data_pipeline.v",
        "data_pipeline_iact.v", "data_pipeline_wght.v", "dsp_unit.v",
        "multiplier.v", "mux2.v", "demux2.v", "mux_iact.v", "SPad_DP.v",
        "SPad_DP_RW.v", "SPad_SP.v", "RST_SYNC.v", "RAM_DP.v", "RAM_DP_RW.v",
        "RAM_SP.v", "RAM_DP_generic.v", "RAM_DP_RW_generic.v", "RAM_SP_generic.v",
    ]
    params = {
        # A standalone cluster is positioned at the edge of a two-column
        # array. Its weight and activation routers are active; psum routing is
        # bypassed because this is the only cluster row in this diagnostic.
        "SERIAL": 1,
        "PE_SERIAL": 1,
        "LEFT_CLUSTER": 1,
        "TOP_CLUSTER": 1,
        "PARALLEL_MACS": 2,
        "SPARSITY_EN": 1,
        "CLUSTER_ROWS": 1,
        "CLUSTER_COLUMNS": 2,
        "CLUSTERS": 2,
    }
    cocotb_test.simulator.run(
        python_search=[str(Path(__file__).parent), str(ROOT / "test/cocotb_PE_cluster")],
        verilog_sources=[str(HDL / source) for source in sources],
        toplevel="OpenEye_Cluster",
        module="openeye_cluster_conv_cocotb",
        sim_build=str(tmp_path),
        parameters=params,
        defines={
            "NO_TRACE": 1,
            "USE_INTERNAL_PARAMS_PE_cluster": 1,
            "USE_INTERNAL_PARAMS_PE": 1,
        },
        includes=[str(HDL / "include")],
        simulator=os.environ.get("OPENEYE_SIMULATOR", "icarus"),
        extra_env={
            "CLOCK_LEN": "10",
            "CLOCK_UNIT": "ns",
            "IACTSIZE_X": "2",
            "IACTSIZE_Y": "2",
            "WGHTSIZE_X": "6",
            "SPARSE_IACT": "20",
            "SPARSE_WGHT": "40",
            "SEED": "4",
            "PARALLEL_MACS": "2",
            "SPARSITY_EN": "1",
        },
        force_compile=True,
    )
