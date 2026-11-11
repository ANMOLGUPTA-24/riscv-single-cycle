//==============================================================================
// alu_control.v : second-level decoder for the ALU
//------------------------------------------------------------------------------
// The main control unit only knows the instruction *class* (ALUOp). This block
// turns that class plus funct3 / instr[30] into the 4-bit ALU opcode.
//
// Why two levels? Because funct7 means different things in different formats:
//   R-type SUB  = funct7 0100000  -> instr[30] really is a "subtract" bit
//   I-type ADDI = funct7 field is part of the 12-bit immediate, so instr[30]
//                 must be IGNORED, or `addi x1,x0,-1024` would decode as SUB.
//   The one exception is SRAI, where instr[30] genuinely selects arithmetic
//   shift. ALUOP_ITYPE therefore honours instr[30] only for funct3 = 101.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module alu_control (
    input  wire [1:0] alu_op,      // instruction class from control_unit
    input  wire [2:0] funct3,      // instr[14:12]
    input  wire       funct7_b5,   // instr[30]
    output reg  [3:0] alu_ctrl
);

    always @(*) begin
        case (alu_op)
            // Loads, stores, LUI, AUIPC, JALR: address / immediate arithmetic.
            `ALUOP_ADD : alu_ctrl = `ALU_ADD;

            // addi, slti, sltiu, xori, ori, andi, slli, srli, srai
            `ALUOP_ITYPE : begin
                case (funct3)
                    `F3_ADD_SUB : alu_ctrl = `ALU_ADD;            // no SUBI exists
                    `F3_SLL     : alu_ctrl = `ALU_SLL;
                    `F3_SLT     : alu_ctrl = `ALU_SLT;
                    `F3_SLTU    : alu_ctrl = `ALU_SLTU;
                    `F3_XOR     : alu_ctrl = `ALU_XOR;
                    `F3_SRL_SRA : alu_ctrl = funct7_b5 ? `ALU_SRA : `ALU_SRL;
                    `F3_OR      : alu_ctrl = `ALU_OR;
                    `F3_AND     : alu_ctrl = `ALU_AND;
                    default     : alu_ctrl = `ALU_ADD;
                endcase
            end

            // add, sub, sll, slt, sltu, xor, srl, sra, or, and
            `ALUOP_RTYPE : begin
                case (funct3)
                    `F3_ADD_SUB : alu_ctrl = funct7_b5 ? `ALU_SUB : `ALU_ADD;
                    `F3_SLL     : alu_ctrl = `ALU_SLL;
                    `F3_SLT     : alu_ctrl = `ALU_SLT;
                    `F3_SLTU    : alu_ctrl = `ALU_SLTU;
                    `F3_XOR     : alu_ctrl = `ALU_XOR;
                    `F3_SRL_SRA : alu_ctrl = funct7_b5 ? `ALU_SRA : `ALU_SRL;
                    `F3_OR      : alu_ctrl = `ALU_OR;
                    `F3_AND     : alu_ctrl = `ALU_AND;
                    default     : alu_ctrl = `ALU_ADD;
                endcase
            end

            default : alu_ctrl = `ALU_ADD;
        endcase
    end

endmodule

`default_nettype wire
