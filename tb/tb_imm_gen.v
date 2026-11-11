//==============================================================================
// tb_imm_gen.v : self-checking testbench for the immediate generator
//------------------------------------------------------------------------------
// The immediate generator is where most RISC-V beginners lose a weekend, so the
// test uses REAL encoded instructions (verified against the RISC-V spec) rather
// than hand-built bit patterns, and checks both positive and negative values.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module tb_imm_gen;

    reg  [31:0] instr;
    reg  [2:0]  sel;
    wire [31:0] imm;
    integer errors = 0, checks = 0;

    imm_gen dut (.instr(instr), .imm_sel(sel), .imm_out(imm));

    task check;
        input [255:0] name;
        input [31:0]  expected;
        begin
            checks = checks + 1;
            #1;
            if (imm !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: instr=%08h sel=%b -> got %08h, expected %08h",
                         name, instr, sel, imm, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_imm_gen.vcd");
        $dumpvars(0, tb_imm_gen);
        $display("=== tb_imm_gen ===");

        // ---- I-type ---------------------------------------------------------
        // addi x1, x0, 5      -> 00500093
        sel = `IMM_I; instr = 32'h00500093; check("I +5", 32'd5);
        // addi x1, x0, -1     -> fff00093
        sel = `IMM_I; instr = 32'hfff00093; check("I -1", 32'hFFFF_FFFF);
        // addi x1, x0, 2047   -> 7ff00093  (largest positive I-immediate)
        sel = `IMM_I; instr = 32'h7ff00093; check("I +2047", 32'd2047);
        // addi x1, x0, -2048  -> 80000093  (most negative I-immediate)
        sel = `IMM_I; instr = 32'h80000093; check("I -2048", 32'hFFFF_F800);
        // lw x5, 16(x2)       -> 01012283
        sel = `IMM_I; instr = 32'h01012283; check("I load offset +16", 32'd16);

        // ---- S-type ---------------------------------------------------------
        // sw x5, 16(x2)       -> 00512823
        sel = `IMM_S; instr = 32'h00512823; check("S +16", 32'd16);
        // sw x5, -4(x2)       -> fe512e23
        sel = `IMM_S; instr = 32'hfe512e23; check("S -4", 32'hFFFF_FFFC);
        // sb x5, 2047(x2)     -> 7e510fa3
        sel = `IMM_S; instr = 32'h7e510fa3; check("S +2047", 32'd2047);

        // ---- B-type (always even, bit 0 is implicit) ------------------------
        // beq x1, x2, +8      -> 00208463
        sel = `IMM_B; instr = 32'h00208463; check("B +8", 32'd8);
        // beq x1, x2, -4      -> fe208ee3
        sel = `IMM_B; instr = 32'hfe208ee3; check("B -4", 32'hFFFF_FFFC);
        // bne x0, x0, +4094   -> 7e101fe3  (largest positive B-immediate)
        sel = `IMM_B; instr = 32'h7e101fe3; check("B +4094", 32'd4094);
        // beq x0, x0, -4096   -> 80000063  (most negative B-immediate)
        sel = `IMM_B; instr = 32'h80000063; check("B -4096", 32'hFFFF_F000);

        // ---- U-type (low 12 bits are always zero) ---------------------------
        // lui x1, 0x12345     -> 123450b7
        sel = `IMM_U; instr = 32'h123450b7; check("U 0x12345", 32'h1234_5000);
        // lui x1, 0xFFFFF     -> fffff0b7
        sel = `IMM_U; instr = 32'hfffff0b7; check("U 0xFFFFF", 32'hFFFF_F000);
        // auipc x1, 0x1        -> 00001097
        sel = `IMM_U; instr = 32'h00001097; check("U 0x1", 32'h0000_1000);

        // ---- J-type ---------------------------------------------------------
        // jal x1, +8          -> 008000ef
        sel = `IMM_J; instr = 32'h008000ef; check("J +8", 32'd8);
        // jal x1, -8          -> ff9ff0ef
        sel = `IMM_J; instr = 32'hff9ff0ef; check("J -8", 32'hFFFF_FFF8);
        // jal x0, +1048574    -> 7ffff06f  (largest positive J-immediate)
        sel = `IMM_J; instr = 32'h7ffff06f; check("J +1048574", 32'd1048574);
        // jal x0, -1048576    -> 8000006f  (most negative J-immediate)
        sel = `IMM_J; instr = 32'h8000006f; check("J -1048576", 32'hFFF0_0000);

        // ---- no immediate ----------------------------------------------------
        sel = `IMM_X; instr = 32'hFFFF_FFFF; check("X -> 0", 32'd0);

        if (errors == 0) $display("PASS tb_imm_gen (%0d checks)", checks);
        else             $display("FAIL tb_imm_gen (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
