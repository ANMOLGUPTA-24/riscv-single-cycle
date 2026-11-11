//==============================================================================
// control_unit.v : main instruction decoder
//------------------------------------------------------------------------------
// Pure combinational logic: opcode in, control signals out. This is the single
// place that decides "what kind of instruction is this and which datapath
// switches must flip". Everything else in the core just obeys.
//
// The default assignment block at the top of the always block is important:
// every signal gets a safe value before the case statement, so (a) an
// unrecognised opcode behaves as a NOP instead of corrupting state, and (b) the
// synthesiser infers pure combinational logic rather than accidental latches.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module control_unit (
    input  wire [6:0] opcode,

    output reg        reg_write,   // write the register file this cycle
    output reg [1:0]  alu_src_a,   // rs1 / PC / zero
    output reg        alu_src_b,   // rs2 / immediate
    output reg [1:0]  alu_op,      // instruction class for alu_control
    output reg [2:0]  imm_sel,     // immediate format for imm_gen
    output reg        mem_read,    // load  (informational / for waveforms)
    output reg        mem_write,   // store
    output reg [1:0]  result_src,  // ALU / memory / PC+4
    output reg        branch,      // conditional branch instruction
    output reg        jump,        // jal
    output reg        jalr,        // jalr
    output reg        illegal      // opcode not implemented
);

    always @(*) begin
        // ---- safe defaults: behave like a NOP -------------------------------
        reg_write  = 1'b0;
        alu_src_a  = `SRCA_RS1;
        alu_src_b  = `SRCB_RS2;
        alu_op     = `ALUOP_ADD;
        imm_sel    = `IMM_X;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        result_src = `RES_ALU;
        branch     = 1'b0;
        jump       = 1'b0;
        jalr       = 1'b0;
        illegal    = 1'b0;

        case (opcode)
            // ---- register-register arithmetic -------------------------------
            // add rd, rs1, rs2        rd <- rs1 op rs2
            `OP_R : begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = `SRCB_RS2;
                alu_op     = `ALUOP_RTYPE;
                result_src = `RES_ALU;
            end

            // ---- register-immediate arithmetic ------------------------------
            // addi rd, rs1, imm       rd <- rs1 op sext(imm)
            `OP_I : begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = `SRCB_IMM;
                alu_op     = `ALUOP_ITYPE;
                imm_sel    = `IMM_I;
                result_src = `RES_ALU;
            end

            // ---- loads -------------------------------------------------------
            // lw rd, imm(rs1)         rd <- MEM[rs1 + sext(imm)]
            `OP_LOAD : begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = `SRCB_IMM;   // address = rs1 + imm
                alu_op     = `ALUOP_ADD;
                imm_sel    = `IMM_I;
                mem_read   = 1'b1;
                result_src = `RES_MEM;
            end

            // ---- stores ------------------------------------------------------
            // sw rs2, imm(rs1)        MEM[rs1 + sext(imm)] <- rs2
            `OP_STORE : begin
                reg_write  = 1'b0;        // stores write memory, not registers
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = `SRCB_IMM;
                alu_op     = `ALUOP_ADD;
                imm_sel    = `IMM_S;
                mem_write  = 1'b1;
            end

            // ---- conditional branches ----------------------------------------
            // beq rs1, rs2, label     if (cond) PC <- PC + sext(imm)
            `OP_BRANCH : begin
                reg_write = 1'b0;
                imm_sel   = `IMM_B;
                branch    = 1'b1;
                // The ALU is unused for branches; branch_unit does the compare.
            end

            // ---- jal ---------------------------------------------------------
            // jal rd, label           rd <- PC + 4 ; PC <- PC + sext(imm)
            `OP_JAL : begin
                reg_write  = 1'b1;
                imm_sel    = `IMM_J;
                result_src = `RES_PC4;
                jump       = 1'b1;
            end

            // ---- jalr --------------------------------------------------------
            // jalr rd, imm(rs1)       rd <- PC + 4 ; PC <- (rs1 + imm) & ~1
            `OP_JALR : begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = `SRCB_IMM;
                alu_op     = `ALUOP_ADD;  // ALU computes the target address
                imm_sel    = `IMM_I;
                result_src = `RES_PC4;
                jalr       = 1'b1;
            end

            // ---- lui ---------------------------------------------------------
            // lui rd, imm             rd <- imm << 12   (0 + upper immediate)
            `OP_LUI : begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_ZERO;
                alu_src_b  = `SRCB_IMM;
                alu_op     = `ALUOP_ADD;
                imm_sel    = `IMM_U;
                result_src = `RES_ALU;
            end

            // ---- auipc -------------------------------------------------------
            // auipc rd, imm           rd <- PC + (imm << 12)
            `OP_AUIPC : begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_PC;
                alu_src_b  = `SRCB_IMM;
                alu_op     = `ALUOP_ADD;
                imm_sel    = `IMM_U;
                result_src = `RES_ALU;
            end

            default : begin
                illegal = 1'b1;   // everything already defaults to NOP
            end
        endcase
    end

endmodule

`default_nettype wire
