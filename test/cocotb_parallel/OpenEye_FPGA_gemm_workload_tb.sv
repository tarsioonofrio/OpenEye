// This file is part of the OpenEye project.
// SPDX-License-Identifier: SHL-2.1

`timescale 1ns / 1ps
`include "gemm_workload.svh"

module OpenEye_FPGA_gemm_workload_tb;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic [63:0] data_dma_i = '0;
  logic enable_dma_i = 1'b0;
  logic ready_dma_i = 1'b0;
  wire ready_dma_o;
  wire [63:0] data_dma_o;
  wire enable_dma_o;
  wire last_data_o;

  logic [63:0] dma_input_mem [0:`GEMM_DMA_WORD_COUNT-1];
  logic [31:0] expected_mem [0:`GEMM_OUTPUT_COUNT-1];

  integer cycle_index;
  integer output_index;
  integer output_filter;
  integer signed actual_value;
  integer signed expected_value;

  always #10 clk_i = ~clk_i;

  OpenEye_FPGA dut (
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

  initial begin
    $readmemh("gemm_dma_input.hex", dma_input_mem);
    $readmemh("gemm_expected.hex", expected_mem);

    repeat (8) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    cycle_index = 0;
    while (!ready_dma_o && cycle_index < 1000) begin
      @(posedge clk_i);
      cycle_index = cycle_index + 1;
    end
    if (!ready_dma_o)
      $fatal(1, "OpenEye_FPGA never became ready for the GEMM DMA workload");

    // Replay the same ordered DMA sections produced by GemmMapper:
    // configuration/router words, activations, weights, bias, quantization.
    for (cycle_index = 0; cycle_index < `GEMM_DMA_WORD_COUNT; cycle_index = cycle_index + 1) begin
      @(negedge clk_i);
      data_dma_i = dma_input_mem[cycle_index];
      enable_dma_i = 1'b1;
    end
    @(negedge clk_i);
    data_dma_i = '0;
    enable_dma_i = 1'b0;

    // The FPGA wrapper waits for host readiness before it drains the result
    // SPad, so keep the output side ready while monitoring each valid beat.
    ready_dma_i = 1'b1;
    output_index = 0;
    cycle_index = 0;
    // Sample after the DUT's rising-edge nonblocking assignments have settled.
    // ready_dma_i stays high, so each valid cycle is accepted at the next edge.
    while (output_index < `GEMM_OUTPUT_COUNT && cycle_index < 400000) begin
      @(negedge clk_i);
      cycle_index = cycle_index + 1;
      if (enable_dma_o) begin
        // Match rtl_test_utils.compare_stream_Dense: cluster columns are
        // interleaved for each psum address in the DMA output stream.
        output_filter = (output_index % `GEMM_CLUSTER_COLUMNS)
                        * `GEMM_OUTPUTS_PER_CLUSTER_COLUMN
                        + output_index / `GEMM_CLUSTER_COLUMNS;
        actual_value = $signed(data_dma_o[19:0]);
        expected_value = $signed(expected_mem[output_filter]);
        if (actual_value !== expected_value)
          $fatal(1, "GEMM output beat %0d maps to C[%0d]: got %0d expected %0d",
                 output_index, output_filter, actual_value, expected_value);
        output_index = output_index + 1;
      end
    end
    if (output_index != `GEMM_OUTPUT_COUNT)
      $fatal(1, "GEMM output count %0d, expected %0d (FSM=%0d)",
             output_index, `GEMM_OUTPUT_COUNT, dut.fsm_current_state);
    if (dut.OpenEye_Parallel.gemm_mode_reg !== 1'b1)
      $fatal(1, "DMA workload did not configure output-stationary GEMM mode");

    $display("PASS: full-system GEMM K=%0d N=%0d seed=20261003 outputs=%0d mode=output-stationary",
             32, 32, output_index);
    $finish;
  end
endmodule
