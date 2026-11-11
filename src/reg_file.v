//==============================================================================
// reg_file.v : 32 x 32-bit register file, 2 read ports + 1 write port
//------------------------------------------------------------------------------
// Reads are combinational (the single-cycle datapath needs the operands in the
// same cycle). Writes happen on the rising clock edge.
//
// x0 is architecturally hard-wired to zero: reads of x0 return 0 and writes to
// x0 are discarded. This is what makes `mv`, `nop`, `j` and friends work.
//
// Write-before-read in the same cycle is NOT needed here: in a single-cycle
// machine the operands are read at the start of the cycle and the result is
// written at the end of the same cycle, so there is no forwarding problem.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module reg_file #(
    parameter integer WIDTH = `XLEN
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             we,        // write enable
    input  wire [4:0]       rs1_addr,
    input  wire [4:0]       rs2_addr,
    input  wire [4:0]       rd_addr,
    input  wire [WIDTH-1:0] rd_data,
    output wire [WIDTH-1:0] rs1_data,
    output wire [WIDTH-1:0] rs2_data
);

    reg [WIDTH-1:0] regs [0:31];
    integer i;

    // Combinational read, with x0 forced to zero.
    assign rs1_data = (rs1_addr == 5'd0) ? {WIDTH{1'b0}} : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? {WIDTH{1'b0}} : regs[rs2_addr];

    // Synchronous write. Reset clears the whole file so simulation starts from
    // a known state instead of X's.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= {WIDTH{1'b0}};
        end else if (we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

endmodule

`default_nettype wire
