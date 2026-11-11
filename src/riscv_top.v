//==============================================================================
// riscv_top.v : core + instruction memory + data memory
//------------------------------------------------------------------------------
// The simulation-level top. Hand it two hex files and it runs a program.
// Synthesis normally targets riscv_core instead, with real memories supplied by
// the FPGA vendor's block RAM.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module riscv_top #(
    parameter integer WIDTH      = `XLEN,
    parameter integer IMEM_DEPTH = 1024,
    parameter integer DMEM_DEPTH = 1024,
    parameter         IMEM_FILE  = "",
    parameter         DMEM_FILE  = ""
) (
    input  wire             clk,
    input  wire             rst_n,
    output wire [WIDTH-1:0] dbg_pc,
    output wire [31:0]      dbg_instr,
    output wire             dbg_reg_write,
    output wire [4:0]       dbg_rd_addr,
    output wire [WIDTH-1:0] dbg_rd_data,
    output wire             dbg_illegal,
    output wire             dbg_misaligned
);

    wire [WIDTH-1:0] imem_addr;
    wire [31:0]      imem_rdata;
    wire [WIDTH-1:0] dmem_addr;
    wire [WIDTH-1:0] dmem_wdata;
    wire [3:0]       dmem_wstrb;
    wire [WIDTH-1:0] dmem_rdata;

    riscv_core #(.WIDTH(WIDTH)) u_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_rdata     (dmem_rdata),
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_reg_write  (dbg_reg_write),
        .dbg_rd_addr    (dbg_rd_addr),
        .dbg_rd_data    (dbg_rd_data),
        .dbg_illegal    (dbg_illegal),
        .dbg_misaligned (dbg_misaligned)
    );

    instr_mem #(
        .WIDTH     (WIDTH),
        .DEPTH     (IMEM_DEPTH),
        .INIT_FILE (IMEM_FILE)
    ) u_instr_mem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    data_mem #(
        .WIDTH     (WIDTH),
        .DEPTH     (DMEM_DEPTH),
        .INIT_FILE (DMEM_FILE)
    ) u_data_mem (
        .clk   (clk),
        .addr  (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb),
        .rdata (dmem_rdata)
    );

endmodule

`default_nettype wire
