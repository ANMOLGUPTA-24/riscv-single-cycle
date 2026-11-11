//==============================================================================
// alu.v : 32-bit arithmetic / logic unit
//------------------------------------------------------------------------------
// Purely combinational. One operation per cycle, selected by alu_ctrl.
// Shift amounts use only the low 5 bits of b, exactly as RV32I specifies.
//
// Note there is no zero/carry/overflow flag. A textbook ALU usually has a Zero
// output that beq uses, but this design gives branches their own comparator
// (branch_unit.v), so a flag here would be dead logic - and dead logic still
// costs gates in the synthesis report.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module alu #(
    parameter integer WIDTH = `XLEN
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [3:0]       alu_ctrl,
    output reg  [WIDTH-1:0] result
);

    // Signed views of the operands, for SLT and SRA.
    wire signed [WIDTH-1:0] a_s = a;
    wire signed [WIDTH-1:0] b_s = b;

    // RV32I shifts use rs2[4:0] (or shamt[4:0]) only.
    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (alu_ctrl)
            `ALU_ADD  : result = a + b;
            `ALU_SUB  : result = a - b;
            `ALU_SLL  : result = a << shamt;
            `ALU_SLT  : result = (a_s < b_s) ? {{WIDTH-1{1'b0}}, 1'b1} : {WIDTH{1'b0}};
            `ALU_SLTU : result = (a   < b  ) ? {{WIDTH-1{1'b0}}, 1'b1} : {WIDTH{1'b0}};
            `ALU_XOR  : result = a ^ b;
            `ALU_SRL  : result = a >> shamt;
            `ALU_SRA  : result = a_s >>> shamt;
            `ALU_OR   : result = a | b;
            `ALU_AND  : result = a & b;
            default   : result = {WIDTH{1'b0}};
        endcase
    end

endmodule

`default_nettype wire
