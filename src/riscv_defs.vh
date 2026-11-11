//==============================================================================
// riscv_defs.vh : shared constants for the single-cycle RV32I core
//------------------------------------------------------------------------------
// Everything that more than one module needs to agree on lives here, so that a
// control signal encoding can never drift between the producer and consumer.
//==============================================================================
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// ---------------------------------------------------------------- data width -
`define XLEN 32

// ------------------------------------------------------------------- opcodes -
// Bits [6:0] of the instruction. Every RV32I opcode ends in 2'b11.
`define OP_R      7'b0110011   // add, sub, sll, slt, sltu, xor, srl, sra, or, and
`define OP_I      7'b0010011   // addi, slti, sltiu, xori, ori, andi, slli, srli, srai
`define OP_LOAD   7'b0000011   // lb, lh, lw, lbu, lhu
`define OP_STORE  7'b0100011   // sb, sh, sw
`define OP_BRANCH 7'b1100011   // beq, bne, blt, bge, bltu, bgeu
`define OP_JAL    7'b1101111   // jal
`define OP_JALR   7'b1100111   // jalr
`define OP_LUI    7'b0110111   // lui
`define OP_AUIPC  7'b0010111   // auipc

// -------------------------------------------------------- funct3 field codes -
// OP / OP-IMM
`define F3_ADD_SUB 3'b000
`define F3_SLL     3'b001
`define F3_SLT     3'b010
`define F3_SLTU    3'b011
`define F3_XOR     3'b100
`define F3_SRL_SRA 3'b101
`define F3_OR      3'b110
`define F3_AND     3'b111
// LOAD
`define F3_LB  3'b000
`define F3_LH  3'b001
`define F3_LW  3'b010
`define F3_LBU 3'b100
`define F3_LHU 3'b101
// STORE
`define F3_SB 3'b000
`define F3_SH 3'b001
`define F3_SW 3'b010
// BRANCH
`define F3_BEQ  3'b000
`define F3_BNE  3'b001
`define F3_BLT  3'b100
`define F3_BGE  3'b101
`define F3_BLTU 3'b110
`define F3_BGEU 3'b111

// ------------------------------------------------------- ALU operation codes -
// Internal encoding, chosen by us. 4 bits = up to 16 operations.
`define ALU_ADD  4'b0000
`define ALU_SUB  4'b0001
`define ALU_SLL  4'b0010
`define ALU_SLT  4'b0011
`define ALU_SLTU 4'b0100
`define ALU_XOR  4'b0101
`define ALU_SRL  4'b0110
`define ALU_SRA  4'b0111
`define ALU_OR   4'b1000
`define ALU_AND  4'b1001

// ----------------------------------------- ALUOp: how to decode funct3/funct7 -
// Tells alu_control how much of the instruction to look at.
`define ALUOP_ADD   2'b00  // force an add (loads, stores, lui, auipc, jalr)
`define ALUOP_ITYPE 2'b01  // funct3 selects; bit30 only matters for SRLI/SRAI
`define ALUOP_RTYPE 2'b10  // funct3 selects; bit30 selects ADD/SUB and SRL/SRA

// ------------------------------------------------------- ALU operand A select -
`define SRCA_RS1  2'b00
`define SRCA_PC   2'b01
`define SRCA_ZERO 2'b10   // used by LUI: 0 + imm = imm

// ------------------------------------------------------- ALU operand B select -
`define SRCB_RS2 1'b0
`define SRCB_IMM 1'b1

// ---------------------------------------------- write-back (result) selection -
`define RES_ALU  2'b00
`define RES_MEM  2'b01
`define RES_PC4  2'b10   // return address for jal / jalr

// -------------------------------------------------------- next-PC source mux -
`define PCSRC_PC4    2'b00   // sequential
`define PCSRC_TARGET 2'b01   // PC + imm   (taken branch, jal)
`define PCSRC_ALU    2'b10   // (rs1 + imm) & ~1   (jalr)

// -------------------------------------------- immediate format for imm_gen --
`define IMM_I 3'b000
`define IMM_S 3'b001
`define IMM_B 3'b010
`define IMM_U 3'b011
`define IMM_J 3'b100
`define IMM_X 3'b111   // don't care / no immediate

`endif
