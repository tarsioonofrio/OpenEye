"""Reuse the established convolution stimulus through OpenEye_Cluster ports."""

import cocotb
from cocotb.triggers import Timer

import PE_cluster_tb as pe_tb


class ClusterInterface:
    """Map the PE_cluster test contract onto a standalone OpenEye_Cluster."""

    _ports = {
        "pe_iact_data": "ext_mem_iact_data_i",
        "pe_iact_enable": "ext_mem_iact_enable_i",
        "pe_iact_ready": "ext_mem_iact_ready_o",
        "pe_wght_data": "ext_mem_wght_data_i",
        "pe_wght_enable": "ext_mem_wght_enable_i",
        "pe_wght_ready": "ext_mem_wght_ready_o",
        "pe_psum_data_i": "ext_mem_psum_data_i",
        "pe_psum_enable_i": "ext_mem_psum_enable_i",
        "pe_psum_ready_i": "ext_mem_psum_ready_i",
        "pe_router_psum_data_i": "ext_mem_psum_data_i",
        "pe_router_psum_enable_i": "ext_mem_psum_enable_i",
        "pe_router_psum_ready_i": "ext_mem_psum_ready_i",
    }

    def __init__(self, top):
        self._top = top
        self._cluster = top.pe_cluster
        self._log = top._log

    def __getattr__(self, name):
        mapped = self._ports.get(name)
        if mapped is not None:
            return getattr(self._top, mapped)
        try:
            return getattr(self._top, name)
        except AttributeError:
            return getattr(self._cluster, name)


@cocotb.test()
async def convolution_reproducer_through_openeye_cluster(dut):
    dut.ext_mem_iact_addr_i.value = 0
    dut.ext_mem_psum_addr_i.value = 0
    dut.data_write_enable_iact_i.value = 0
    dut.data_write_enable_i.value = 0
    dut.router_mode_iact_i.value = sum(1 << (6 * bank) for bank in range(3))
    dut.router_mode_wght_i.value = 0
    dut.router_mode_psum_i.value = 0
    dut.delay_psum_glb_i.value = 0
    dut.enable_stream_i.value = 0
    dut.data_stream_i.value = 0
    dut.gemm_mode_i.value = 0
    dut.bano_cluster_mode_i.value = 0
    dut.af_cluster_mode_i.value = 0

    # The standalone weight routers broadcast GLB weights sideways as well as
    # feeding the local PE array. A neighboring cluster is absent, so report
    # ready at that boundary to avoid artificial backpressure.
    dut.ready_dst_side_wght.value = 0b111
    dut.enable_src_side_wght.value = 0
    dut.data_src_side_wght.value = 0
    dut.ready_dst_side_iact.value = 0
    dut.enable_src_side_iact.value = 0
    dut.data_src_side_iact.value = 0
    dut.ready_dst_top_iact.value = 0
    dut.enable_src_top_iact.value = 0
    dut.data_src_top_iact.value = 0
    dut.ready_dst_bottom_iact.value = 0
    dut.enable_src_bottom_iact.value = 0
    dut.data_src_bottom_iact.value = 0
    dut.enable_src_top_psum.value = 0
    dut.data_src_top_psum.value = 0
    dut.ready_dst_bottom_psum.value = 0
    dut.enable_src_bottom_psum.value = 0
    dut.data_src_bottom_psum.value = 0
    dut.ready_dst_top_psum.value = 0b1111
    dut.ext_mem_psum_ready_i.value = 0b1111

    facade = ClusterInterface(dut)
    await pe_tb.initialize_test_pe_cluster(facade)
    await Timer(1, unit="ns")
