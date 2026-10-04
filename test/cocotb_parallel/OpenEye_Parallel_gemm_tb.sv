// This file is part of the OpenEye project.
// © Fachhochschule Dortmund – University of Applied Sciences and Arts (until 2025),
// Universität Duisburg-Essen (since 2025).
// SPDX-License-Identifier: SHL-2.1
// For more details, see the LICENSE file in the root directory of this project.

`timescale 1ns / 1ps

module OpenEye_Parallel_gemm_tb;
  localparam integer TEST_CLUSTER_COLUMNS = 2;
  localparam integer TEST_CLUSTER_ROWS    = 2;
  localparam integer TEST_PE_COLUMNS      = 4;
  localparam integer TEST_PE_ROWS         = 3;
  localparam integer TEST_NUM_GLB_IACT    = 3;
  localparam integer TEST_CLUSTERS        = TEST_CLUSTER_COLUMNS * TEST_CLUSTER_ROWS;
  localparam integer TEST_PES             = TEST_PE_COLUMNS * TEST_PE_ROWS;
  localparam integer TEST_SEL_BITS        = $clog2(TEST_NUM_GLB_IACT + 1);
  localparam integer TEST_SEL_COUNT       = TEST_CLUSTERS * TEST_PES;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic status_reg_enable_i = 1'b0;
  logic gemm_mode_i = 1'b0;
  logic [TEST_SEL_BITS * TEST_SEL_COUNT - 1:0] iact_choose_i = '0;

  wire [TEST_SEL_BITS * TEST_SEL_COUNT - 1:0] observed_iact_sel;

  always #5 clk_i = ~clk_i;

  OpenEye_Parallel #(
      .CLUSTER_COLUMNS(TEST_CLUSTER_COLUMNS),
      .CLUSTER_ROWS(TEST_CLUSTER_ROWS),
      .PE_COLUMNS(TEST_PE_COLUMNS),
      .PE_ROWS(TEST_PE_ROWS),
      .NUM_GLB_IACT(TEST_NUM_GLB_IACT)
  ) dut (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .compute_i('0),
      .iact_data_i('0),
      .iact_enable_i('0),
      .iact_ready_o(),
      .wght_data_i('0),
      .wght_enable_i('0),
      .wght_ready_o(),
      .psum_data_i('0),
      .psum_enable_i('0),
      .psum_ready_o(),
      .psum_data_o(),
      .psum_enable_o(),
      .psum_ready_i('0),
      .status_reg_enable_i(status_reg_enable_i),
      .data_mode_i('0),
      .gemm_mode_i(gemm_mode_i),
      .raw_wght_i('0),
      .fraction_bit_i('0),
      .needed_cycles_i('0),
      .needed_x_cls_i('0),
      .needed_y_cls_i('0),
      .needed_iact_cycles_i('0),
      .filters_i('0),
      .iact_size_x_i('0),
      .iact_channels_per_pe_i('0),
      .wght_addr_len_i('0),
      .bano_cluster_mode_i('0),
      .af_cluster_mode_i('0),
      .pooling_cluster_mode_i('0),
      .delay_psum_glb_i('0),
      .input_activations_i('0),
      .kernel_per_pe_cluster_i('0),
      .iact_x_line_repetitions_i('0),
      .kernel_size_y_i('0),
      .compute_mask_i('0),
      .iact_choose_i(iact_choose_i),
      .psum_choose_i('0),
      .router_mode_iact_i('0),
      .router_mode_wght_i('0),
      .router_mode_psum_i('0),
      .needed_psum_storage_cycles_i('0),
      .needed_iact_channel_cycles_i('0),
      .psum_transmitted_i('0)
  );

  // Flatten the PE generate hierarchy into a vector so procedural checks can
  // use variable indices on every supported simulator.
  genvar gx, gy, px, py;
  generate
    for (gx = 0; gx < TEST_CLUSTER_COLUMNS; gx = gx + 1) begin : gen_probe_x
      for (gy = 0; gy < TEST_CLUSTER_ROWS; gy = gy + 1) begin : gen_probe_y
        for (px = 0; px < TEST_PE_COLUMNS; px = px + 1) begin : gen_probe_pe_x
          for (py = 0; py < TEST_PE_ROWS; py = py + 1) begin : gen_probe_pe_y
            localparam integer SAMPLE_INDEX =
                (((gx * TEST_CLUSTER_ROWS + gy) * TEST_PE_COLUMNS + px) * TEST_PE_ROWS + py);
            assign observed_iact_sel[SAMPLE_INDEX * TEST_SEL_BITS +: TEST_SEL_BITS] =
                dut.gen_x[gx].gen_y[gy].OpenEye_Cluster.pe_cluster.gen_X[px].gen_Y[py].iact_sel_w;
          end
        end
      end
    end
  endgenerate

  task automatic wait_cycles(input integer count);
    repeat (count) @(posedge clk_i);
    #1;
  endtask

  task automatic latch_dataflow(input logic mode);
    begin
      @(negedge clk_i);
      gemm_mode_i = mode;
      status_reg_enable_i = 1'b1;
      wait_cycles(4);
      @(negedge clk_i);
      status_reg_enable_i = 1'b0;
      wait_cycles(1);
      @(negedge clk_i);
      gemm_mode_i = 1'b0;
      wait_cycles(2);
    end
  endtask

  task automatic check_rs_selection;
    integer cx, cy, row, index;
    logic [TEST_SEL_BITS-1:0] selected_bank;
    begin
      for (cx = 0; cx < TEST_CLUSTER_COLUMNS; cx = cx + 1) begin
        for (cy = 0; cy < TEST_CLUSTER_ROWS; cy = cy + 1) begin
          for (row = 0; row < TEST_PE_ROWS; row = row + 1) begin
            index = (((cx * TEST_CLUSTER_ROWS + cy) * TEST_PE_COLUMNS) * TEST_PE_ROWS + row);
            selected_bank = observed_iact_sel[index * TEST_SEL_BITS +: TEST_SEL_BITS];
            if (selected_bank !== {{(TEST_SEL_BITS-1){1'b0}}, 1'b1}) begin
              $fatal(1,
                  "RS mode cluster(%0d,%0d) PE row %0d selected bank %0d; expected 1",
                  cx, cy, row, selected_bank);
            end
          end
        end
      end
    end
  endtask

  task automatic check_os_selection;
    integer cx, cy, col, row, index;
    logic [TEST_SEL_BITS-1:0] selected_bank;
    begin
      for (cx = 0; cx < TEST_CLUSTER_COLUMNS; cx = cx + 1) begin
        for (cy = 0; cy < TEST_CLUSTER_ROWS; cy = cy + 1) begin
          for (col = 0; col < TEST_PE_COLUMNS; col = col + 1) begin
            for (row = 0; row < TEST_PE_ROWS; row = row + 1) begin
              index = (((cx * TEST_CLUSTER_ROWS + cy) * TEST_PE_COLUMNS + col) * TEST_PE_ROWS + row);
              selected_bank = observed_iact_sel[index * TEST_SEL_BITS +: TEST_SEL_BITS];
              if (selected_bank !== row[TEST_SEL_BITS-1:0]) begin
                $fatal(1,
                    "OS mode cluster(%0d,%0d) PE(%0d,%0d) selected bank %0d; expected row %0d",
                    cx, cy, col, row, selected_bank, row);
              end
            end
          end
        end
      end
    end
  endtask

  integer pe_index;
  initial begin
    // Each PE's row-stationary selector field requests GLB bank 1.
    for (pe_index = 0; pe_index < TEST_SEL_COUNT; pe_index = pe_index + 1)
      iact_choose_i[pe_index * TEST_SEL_BITS +: TEST_SEL_BITS] = 1;

    rst_ni = 1'b0;
    wait_cycles(5);
    @(negedge clk_i);
    rst_ni = 1'b1;
    wait_cycles(5);

    // Row-stationary uses the programmed selector from iact_choose_i.
    latch_dataflow(1'b0);
    if (dut.gemm_mode_reg !== 1'b0)
      $fatal(1, "gemm_mode_reg must remain 0 in row-stationary mode");
    check_rs_selection();

    // Output-stationary overrides the selector with the PE row index.
    latch_dataflow(1'b1);
    if (dut.gemm_mode_reg !== 1'b1)
      $fatal(1, "gemm_mode_reg did not latch GEMM mode");
    check_os_selection();

    // Returning to row-stationary must remove the override.
    latch_dataflow(1'b0);
    if (dut.gemm_mode_reg !== 1'b0)
      $fatal(1, "gemm_mode_reg did not return to row-stationary mode");
    check_rs_selection();

    $display("PASS: OpenEye_Parallel GEMM mode plumbing");
    $finish;
  end
endmodule
