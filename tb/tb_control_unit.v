//==============================================================================
// tb_control_unit.v : self-checking testbench for the main decoder + alu_control
//------------------------------------------------------------------------------
// Decoders are tested by comparing the whole control vector against a
// hand-written golden table - the same table that appears in the report. If the
// table and the RTL disagree, one of them is wrong, and that is exactly what we
// want to find out before integration.
//
// It also checks the subtle case: ADDI with a negative immediate must NOT be
// decoded as SUB even though instr[30] happens to be 1.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module tb_control_unit;

    reg  [6:0] opcode;
    reg  [2:0] funct3;
    reg        funct7_b5;

    wire       reg_write, alu_src_b, mem_read, mem_write, branch, jump, jalr, illegal;
    wire [1:0] alu_src_a, alu_op, result_src;
    wire [2:0] imm_sel;
    wire [3:0] alu_ctrl;

    integer errors = 0, checks = 0;

    control_unit dut (
        .opcode(opcode), .reg_write(reg_write), .alu_src_a(alu_src_a),
        .alu_src_b(alu_src_b), .alu_op(alu_op), .imm_sel(imm_sel),
        .mem_read(mem_read), .mem_write(mem_write), .result_src(result_src),
        .branch(branch), .jump(jump), .jalr(jalr), .illegal(illegal)
    );

    alu_control dut_ac (
        .alu_op(alu_op), .funct3(funct3), .funct7_b5(funct7_b5), .alu_ctrl(alu_ctrl)
    );

    // Compare the full control vector in one shot.
    task check_ctrl;
        input [255:0] name;
        input         e_reg_write;
        input [1:0]   e_alu_src_a;
        input         e_alu_src_b;
        input [2:0]   e_imm_sel;
        input         e_mem_write;
        input [1:0]   e_result_src;
        input         e_branch;
        input         e_jump;
        input         e_jalr;
        begin
            checks = checks + 1;
            #1;
            if (reg_write  !== e_reg_write  || alu_src_a !== e_alu_src_a ||
                alu_src_b  !== e_alu_src_b  || imm_sel   !== e_imm_sel   ||
                mem_write  !== e_mem_write  || result_src!== e_result_src||
                branch     !== e_branch     || jump      !== e_jump      ||
                jalr       !== e_jalr) begin
                errors = errors + 1;
                $display("  FAIL %0s (opcode=%b)", name, opcode);
                $display("    got      rw=%b srcA=%b srcB=%b imm=%b mw=%b res=%b br=%b j=%b jr=%b",
                    reg_write, alu_src_a, alu_src_b, imm_sel, mem_write, result_src, branch, jump, jalr);
                $display("    expected rw=%b srcA=%b srcB=%b imm=%b mw=%b res=%b br=%b j=%b jr=%b",
                    e_reg_write, e_alu_src_a, e_alu_src_b, e_imm_sel, e_mem_write, e_result_src,
                    e_branch, e_jump, e_jalr);
            end
        end
    endtask

    task check_alu;
        input [255:0] name;
        input [3:0]   expected;
        begin
            checks = checks + 1;
            #1;
            if (alu_ctrl !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: aluop=%b f3=%b b30=%b -> got %b, expected %b",
                         name, alu_op, funct3, funct7_b5, alu_ctrl, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_control_unit.vcd");
        $dumpvars(0, tb_control_unit);
        $display("=== tb_control_unit ===");

        //                                         rw srcA         srcB        imm      mw res        br j  jr
        opcode = `OP_R;      check_ctrl("R-type",   1, `SRCA_RS1,  `SRCB_RS2, `IMM_X,   0, `RES_ALU, 0, 0, 0);
        opcode = `OP_I;      check_ctrl("I-type",   1, `SRCA_RS1,  `SRCB_IMM, `IMM_I,   0, `RES_ALU, 0, 0, 0);
        opcode = `OP_LOAD;   check_ctrl("load",     1, `SRCA_RS1,  `SRCB_IMM, `IMM_I,   0, `RES_MEM, 0, 0, 0);
        opcode = `OP_STORE;  check_ctrl("store",    0, `SRCA_RS1,  `SRCB_IMM, `IMM_S,   1, `RES_ALU, 0, 0, 0);
        opcode = `OP_BRANCH; check_ctrl("branch",   0, `SRCA_RS1,  `SRCB_RS2, `IMM_B,   0, `RES_ALU, 1, 0, 0);
        opcode = `OP_JAL;    check_ctrl("jal",      1, `SRCA_RS1,  `SRCB_RS2, `IMM_J,   0, `RES_PC4, 0, 1, 0);
        opcode = `OP_JALR;   check_ctrl("jalr",     1, `SRCA_RS1,  `SRCB_IMM, `IMM_I,   0, `RES_PC4, 0, 0, 1);
        opcode = `OP_LUI;    check_ctrl("lui",      1, `SRCA_ZERO, `SRCB_IMM, `IMM_U,   0, `RES_ALU, 0, 0, 0);
        opcode = `OP_AUIPC;  check_ctrl("auipc",    1, `SRCA_PC,   `SRCB_IMM, `IMM_U,   0, `RES_ALU, 0, 0, 0);

        // ---- illegal opcode must be an inert NOP ----------------------------
        opcode = 7'b1110011;  // ecall/ebreak: not implemented here
        check_ctrl("illegal is inert", 0, `SRCA_RS1, `SRCB_RS2, `IMM_X, 0, `RES_ALU, 0, 0, 0);
        checks = checks + 1;
        #1; if (illegal !== 1'b1) begin
            errors = errors + 1; $display("  FAIL illegal flag not raised");
        end

        // ---- loads and stores always ADD (address arithmetic) ---------------
        opcode = `OP_LOAD;  funct3 = `F3_LW; funct7_b5 = 1'b1;
        check_alu("lw forces ADD despite b30", `ALU_ADD);
        opcode = `OP_STORE; funct3 = `F3_SW; funct7_b5 = 1'b1;
        check_alu("sw forces ADD despite b30", `ALU_ADD);

        // ---- R-type uses instr[30] ------------------------------------------
        opcode = `OP_R; funct3 = `F3_ADD_SUB; funct7_b5 = 1'b0; check_alu("add", `ALU_ADD);
        opcode = `OP_R; funct3 = `F3_ADD_SUB; funct7_b5 = 1'b1; check_alu("sub", `ALU_SUB);
        opcode = `OP_R; funct3 = `F3_SRL_SRA; funct7_b5 = 1'b0; check_alu("srl", `ALU_SRL);
        opcode = `OP_R; funct3 = `F3_SRL_SRA; funct7_b5 = 1'b1; check_alu("sra", `ALU_SRA);
        opcode = `OP_R; funct3 = `F3_SLT;     funct7_b5 = 1'b0; check_alu("slt", `ALU_SLT);
        opcode = `OP_R; funct3 = `F3_SLTU;    funct7_b5 = 1'b0; check_alu("sltu", `ALU_SLTU);
        opcode = `OP_R; funct3 = `F3_AND;     funct7_b5 = 1'b0; check_alu("and", `ALU_AND);
        opcode = `OP_R; funct3 = `F3_OR;      funct7_b5 = 1'b0; check_alu("or", `ALU_OR);
        opcode = `OP_R; funct3 = `F3_XOR;     funct7_b5 = 1'b0; check_alu("xor", `ALU_XOR);
        opcode = `OP_R; funct3 = `F3_SLL;     funct7_b5 = 1'b0; check_alu("sll", `ALU_SLL);

        // ---- THE classic trap: I-type must ignore instr[30] except for shifts
        opcode = `OP_I; funct3 = `F3_ADD_SUB; funct7_b5 = 1'b1;
        check_alu("addi with b30=1 is still ADD (not SUB)", `ALU_ADD);
        opcode = `OP_I; funct3 = `F3_SRL_SRA; funct7_b5 = 1'b0; check_alu("srli", `ALU_SRL);
        opcode = `OP_I; funct3 = `F3_SRL_SRA; funct7_b5 = 1'b1; check_alu("srai", `ALU_SRA);
        opcode = `OP_I; funct3 = `F3_SLT;     funct7_b5 = 1'b1; check_alu("slti ignores b30", `ALU_SLT);
        opcode = `OP_I; funct3 = `F3_AND;     funct7_b5 = 1'b1; check_alu("andi ignores b30", `ALU_AND);

        // ---- lui / auipc / jalr all need a plain add -------------------------
        opcode = `OP_LUI;   funct3 = 3'b111; funct7_b5 = 1'b1; check_alu("lui ADD", `ALU_ADD);
        opcode = `OP_AUIPC; funct3 = 3'b101; funct7_b5 = 1'b1; check_alu("auipc ADD", `ALU_ADD);
        opcode = `OP_JALR;  funct3 = 3'b000; funct7_b5 = 1'b1; check_alu("jalr ADD", `ALU_ADD);

        if (errors == 0) $display("PASS tb_control_unit (%0d checks)", checks);
        else             $display("FAIL tb_control_unit (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
