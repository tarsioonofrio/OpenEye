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

  logic [63:0] dma_input_mem [0:`GEMM_TOTAL_DMA_WORD_COUNT-1];
  logic [31:0] expected_mem [0:`GEMM_TOTAL_OUTPUT_COUNT-1];

  integer cycle_index;
  integer row_index;
  integer output_index;
  integer output_filter;
  integer signed actual_value;
  integer signed expected_value;
  integer debug_addr;

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

    // The FPGA wrapper waits for host readiness before it drains the result
    // SPad, so keep the output side ready while monitoring each valid beat.
    ready_dma_i = 1'b1;
    for (row_index = 0; row_index < `GEMM_MATRIX_ROWS; row_index = row_index + 1) begin
      // Each matrix row is one mapper transmission through the same FPGA top.
      for (cycle_index = 0; cycle_index < `GEMM_DMA_WORD_COUNT; cycle_index = cycle_index + 1) begin
        @(negedge clk_i);
        data_dma_i = dma_input_mem[row_index * `GEMM_DMA_WORD_COUNT + cycle_index];
        enable_dma_i = 1'b1;
      end
      @(negedge clk_i);
      data_dma_i = '0;
      enable_dma_i = 1'b0;

      output_index = 0;
      cycle_index = 0;
      // Sample after rising-edge nonblocking assignments have settled.
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
          expected_value = $signed(expected_mem[row_index * `GEMM_OUTPUT_COUNT + output_index]);
          if (actual_value !== expected_value)
            $fatal(1, "GEMM row %0d output beat %0d maps to C[%0d]: got %0d expected %0d",
                   row_index, output_index, output_filter, actual_value, expected_value);
          output_index = output_index + 1;
        end
      end
      if (output_index != `GEMM_OUTPUT_COUNT) begin
        $display("GEMM timeout state: FPGA FSM=%0d Parallel FSM=%0d finished=%0d needed=%0d",
                 dut.fsm_current_state, dut.OpenEye_Parallel.fsm_current_state,
                 dut.OpenEye_Parallel.finished_cycles,
                 dut.OpenEye_Parallel.needed_cycles_i_reg);
        $display("compute=%b wght_enable=%h psum_enable=%h psum_ready=%h psum_fsm=%0d psum_transmitted=%b",
                 dut.compute_reg, dut.wght_enable_i_reg,
                 dut.psum_enable_o, dut.psum_ready_o_reg,
                 dut.fsm_psum_current_state, dut.psum_transmitted);
        $display("psum_cycle=%0d psum_cycle_count=%0d psum_ready_i=%h results_ready=%b psum_enable_i=%h choose=%h router=%h",
                 dut.psum_pipeline_inst.fsm_psum_cycle,
                 dut.psum_pipeline_inst.psum_cycle_count,
                 dut.psum_pipeline_inst.psum_ready_i_reg,
                 dut.psum_pipeline_inst.results_ready,
                 dut.psum_pipeline_inst.psum_enable_i_reg,
                 dut.psum_choose_i_reg,
                 dut.psum_pipeline_inst.router_mode_psum);
        $display("selected cluster(0,1): router_ready=%h router_enable=%h PE ready_o=%b ready_i=%b select=%b state=%0d",
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_router_psum_ready_out,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_router_psum_enable_in,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.psum_ready_o,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.psum_ready_i,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.psum_select,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.current_state_computing);
        $display("selected PE counters: iact_max=%0d channel=%0d iact_addr=%0d wght_vec=%0d wght_start=%0d wght_end=%0d wght_spad_addr=%0d values_valid=%b computing=%b",
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.iact_addr_max_reg,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.channel_reg_C0,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.gen_sparse_fsm.iact_addr_current,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.wght_data_vec,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.gen_sparse_fsm.wght_data_start,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.gen_sparse_fsm.wght_data_end,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.wght_data_SPad_addr,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.values_valid,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.computing);
        $display("selected PE weight config: filters=%0d raw=%b first_words=%0d second_words=%0d addr_read=%0d addr_data=%h",
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.filters_reg_M0,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.raw_wght_w,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.first_spad_words_wght,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.second_spad_words_wght,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.wght_addr_SPad_addr,
                 dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.wght_addr_SPad_data_r);
        for (debug_addr = 0; debug_addr < 16; debug_addr = debug_addr + 1)
          $display("selected PE wght_addr_spad[%0d]=%h",
                   debug_addr,
                   dut.OpenEye_Parallel.gen_x[0].gen_y[1].OpenEye_Cluster.pe_cluster.gen_X[0].gen_Y[0].pe.gen_wght_addr_spad.weight_addr_SPad.ram.impl.mem[debug_addr]);
        $fatal(1, "GEMM row %0d output count %0d, expected %0d",
               row_index, output_index, `GEMM_OUTPUT_COUNT);
      end
      if (dut.OpenEye_Parallel.gemm_mode_reg !== 1'b1)
        $fatal(1, "DMA workload did not configure output-stationary GEMM mode");

      if (row_index + 1 < `GEMM_MATRIX_ROWS) begin
        cycle_index = 0;
        while (!(ready_dma_o && !enable_dma_o && dut.fsm_current_state == 1)
               && cycle_index < 1000) begin
          @(negedge clk_i);
          cycle_index = cycle_index + 1;
        end
        if (!(ready_dma_o && !enable_dma_o && dut.fsm_current_state == 1))
          $fatal(1, "OpenEye_FPGA not ready for GEMM row %0d", row_index + 1);
      end
    end

    $display("PASS: full-system GEMM M=%0d K=%0d N=%0d seed=20261003 output_beats=%0d mode=output-stationary",
             `GEMM_MATRIX_ROWS, `GEMM_K, `GEMM_N, `GEMM_TOTAL_OUTPUT_COUNT);
    $finish;
  end
endmodule
