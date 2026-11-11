//==============================================================================
// pc.v : program counter register
//------------------------------------------------------------------------------
// Deliberately dumb: it is a plain register with a synchronous, active-low
// reset. All the "where do we go next" logic (PC+4, branch target, jump target)
// lives in riscv_core, where the muxes belong.
//
// Keeping the addressing logic out of here is what makes JALR possible: a JALR
// target is an absolute address computed from a register, not an offset from
// the PC, so a PC that could only add to itself would not be able to express it.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module pc #(
    parameter integer WIDTH      = `XLEN,
    parameter [WIDTH-1:0] RESET_ADDR = {WIDTH{1'b0}}
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,        // stall input: 0 holds the PC
    input  wire [WIDTH-1:0] next_pc,
    output reg  [WIDTH-1:0] pc_out
);

    always @(posedge clk) begin
        if (!rst_n)
            pc_out <= RESET_ADDR;
        else if (en)
            pc_out <= next_pc;
    end

endmodule

`default_nettype wire
