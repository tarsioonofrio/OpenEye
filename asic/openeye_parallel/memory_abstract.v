// ASIC-only black-box declarations for OpenEye's generic SRAM implementation
// modules. These preserve the module interfaces while removing storage logic.
// Do not use this file for functional simulation.

module RAM_SP_generic #(
    parameter AddrWidth = 12,
    parameter DataWidth = 8,
    parameter Pipelined = 0,
    parameter WriteMaskWidth = 1
) (
    input wire clk,
    input wire cen,
    input wire rdwen,
    input wire [AddrWidth-1:0] a,
    input wire [DataWidth-1:0] d,
    output wire [DataWidth-1:0] q,
    input wire [WriteMaskWidth-1:0] wm
);
endmodule

module RAM_DP_generic #(
    parameter AddrWidth = 12,
    parameter DataWidth = 8,
    parameter Pipelined = 0
) (
    input wire clkA,
    input wire clkB,
    input wire cenA,
    input wire cenB,
    input wire [AddrWidth-1:0] aA,
    input wire [AddrWidth-1:0] aB,
    input wire [DataWidth-1:0] d,
    output wire [DataWidth-1:0] q
);
endmodule

module RAM_DP_RW_generic #(
    parameter AddrWidth = 16,
    parameter DataWidth = 32,
    parameter Pipelined = 0
) (
    input wire clk_i,
    input wire rd_en_a_i,
    input wire rd_en_b_i,
    input wire wr_en_a_i,
    input wire wr_en_b_i,
    input wire [AddrWidth-1:0] addr_r_a_i,
    input wire [AddrWidth-1:0] addr_r_b_i,
    input wire [AddrWidth-1:0] addr_w_a_i,
    input wire [AddrWidth-1:0] addr_w_b_i,
    input wire [DataWidth-1:0] data_a_i,
    input wire [DataWidth-1:0] data_b_i,
    output wire [DataWidth-1:0] data_a_o,
    output wire [DataWidth-1:0] data_b_o
);
endmodule
