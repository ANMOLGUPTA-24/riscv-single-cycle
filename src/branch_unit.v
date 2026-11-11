//==============================================================================
// branch_unit.v : branch condition evaluator
//------------------------------------------------------------------------------
// A dedicated comparator, kept out of the ALU. In a single-cycle machine the
// ALU is already busy during a branch - for JALR it computes the target, and
// keeping the compare separate means the ALU needs no extra output ports and
// the critical path through the branch decision stays short.
//
// Note the unsigned variants: bltu/bgeu compare the same bit patterns as an
// unsigned magnitude, which is what you want for addresses.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module branch_unit #(
    parameter integer WIDTH = `XLEN
) (
    input  wire [WIDTH-1:0] rs1_data,
    input  wire [WIDTH-1:0] rs2_data,
    input  wire [2:0]       funct3,
    output reg              taken
);

    wire signed [WIDTH-1:0] a_s = rs1_data;
    wire signed [WIDTH-1:0] b_s = rs2_data;

    wire eq  = (rs1_data == rs2_data);
    wire lt  = (a_s < b_s);        // signed
    wire ltu = (rs1_data < rs2_data); // unsigned

    always @(*) begin
        case (funct3)
            `F3_BEQ  : taken =  eq;
            `F3_BNE  : taken = !eq;
            `F3_BLT  : taken =  lt;
            `F3_BGE  : taken = !lt;
            `F3_BLTU : taken =  ltu;
            `F3_BGEU : taken = !ltu;
            default  : taken = 1'b0;   // funct3 010/011 are reserved in RV32I
        endcase
    end

endmodule

`default_nettype wire
