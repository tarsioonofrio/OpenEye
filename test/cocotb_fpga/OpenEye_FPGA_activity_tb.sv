`timescale 1ns/1ps

// Same external interface as OpenEye_FPGA, with a named DUT instance so the
// Xcelium SHM hierarchy is stable for Genus read_stimulus.
module OpenEye_FPGA_activity_tb (
    input  wire        clk_i,
    input  wire        rst_ni,
    output wire        ready_dma_o,
    input  wire [63:0] data_dma_i,
    input  wire        enable_dma_i,
    input  wire        ready_dma_i,
    output wire [63:0] data_dma_o,
    output wire        enable_dma_o,
    output wire        last_data_o
);
    parameter MAX_POOLING = 1;
    parameter AVERAGE_POOLING = 0;
    OpenEye_FPGA dut (
        .MAX_POOLING(MAX_POOLING),
        .AVERAGE_POOLING(AVERAGE_POOLING),
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .ready_dma_o(ready_dma_o),
        .data_dma_i(data_dma_i),
        .enable_dma_i(enable_dma_i),
        .ready_dma_i(ready_dma_i),
        .data_dma_o(data_dma_o),
        .enable_dma_o(enable_dma_o),
        .last_data_o(last_data_o)
    );

`ifdef ASIC_CAPTURE_SHM
    initial begin
        $shm_open("dut.shm");
        $shm_probe(dut, "ASM");
    end
`endif
endmodule
