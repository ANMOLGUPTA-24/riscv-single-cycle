//==============================================================================
// tb_alu.v : self-checking testbench for the ALU
//------------------------------------------------------------------------------
// Pattern used by every testbench in this project:
//   - drive inputs, wait a moment for combinational logic to settle (#1)
//   - compare against an independently computed expected value
//   - count errors, print PASS / FAIL at the end
// A testbench that only dumps waveforms is not a test. This one fails loudly.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module tb_alu;

    reg  [31:0] a, b;
    reg  [3:0]  ctrl;
    wire [31:0] result;
    integer     errors = 0;
    integer     checks = 0;

    alu dut (.a(a), .b(b), .alu_ctrl(ctrl), .result(result));

    task check;
        input [255:0] name;
        input [31:0]  expected;
        begin
            checks = checks + 1;
            #1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: a=%08h b=%08h ctrl=%b -> got %08h, expected %08h",
                         name, a, b, ctrl, result, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_alu.vcd");
        $dumpvars(0, tb_alu);
        $display("=== tb_alu ===");

        // ---- ADD / SUB, including wrap-around ------------------------------
        ctrl = `ALU_ADD;  a = 32'd7;          b = 32'd5;           check("add 7+5", 32'd12);
        ctrl = `ALU_ADD;  a = 32'hFFFF_FFFF;  b = 32'd1;           check("add overflow wraps", 32'd0);
        ctrl = `ALU_ADD;  a = 32'd10;         b = 32'hFFFF_FFFB;   check("add 10+(-5)", 32'd5);
        ctrl = `ALU_SUB;  a = 32'd7;          b = 32'd5;           check("sub 7-5", 32'd2);
        ctrl = `ALU_SUB;  a = 32'd5;          b = 32'd7;           check("sub 5-7", 32'hFFFF_FFFE);
        ctrl = `ALU_SUB;  a = 32'd0;          b = 32'd0;           check("sub 0-0", 32'd0);

        // ---- logic ----------------------------------------------------------
        ctrl = `ALU_AND;  a = 32'hF0F0_FF00;  b = 32'h0FF0_0F0F;   check("and", 32'h00F0_0F00);
        ctrl = `ALU_OR;   a = 32'hF0F0_0000;  b = 32'h0F0F_1234;   check("or",  32'hFFFF_1234);
        ctrl = `ALU_XOR;  a = 32'hAAAA_AAAA;  b = 32'hFFFF_FFFF;   check("xor", 32'h5555_5555);

        // ---- shifts: only b[4:0] is used -----------------------------------
        ctrl = `ALU_SLL;  a = 32'h0000_0001;  b = 32'd31;          check("sll 1<<31", 32'h8000_0000);
        ctrl = `ALU_SLL;  a = 32'h0000_00FF;  b = 32'd4;           check("sll ff<<4", 32'h0000_0FF0);
        ctrl = `ALU_SLL;  a = 32'h0000_0001;  b = 32'd32;          check("sll shamt masked to 0", 32'h0000_0001);
        ctrl = `ALU_SLL;  a = 32'h0000_0001;  b = 32'd33;          check("sll shamt 33 -> 1", 32'h0000_0002);
        ctrl = `ALU_SRL;  a = 32'h8000_0000;  b = 32'd31;          check("srl logical", 32'h0000_0001);
        ctrl = `ALU_SRL;  a = 32'hFFFF_FFF0;  b = 32'd4;           check("srl zero-fills", 32'h0FFF_FFFF);
        ctrl = `ALU_SRA;  a = 32'h8000_0000;  b = 32'd31;          check("sra sign-fills", 32'hFFFF_FFFF);
        ctrl = `ALU_SRA;  a = 32'hFFFF_FFF0;  b = 32'd4;           check("sra -16>>4", 32'hFFFF_FFFF);
        ctrl = `ALU_SRA;  a = 32'h7FFF_FFFF;  b = 32'd4;           check("sra positive", 32'h07FF_FFFF);

        // ---- set-less-than: signed vs unsigned is the classic bug ----------
        ctrl = `ALU_SLT;  a = 32'hFFFF_FFFF;  b = 32'd1;           check("slt -1<1 signed", 32'd1);
        ctrl = `ALU_SLT;  a = 32'd1;          b = 32'hFFFF_FFFF;   check("slt 1<-1 false", 32'd0);
        ctrl = `ALU_SLT;  a = 32'd5;          b = 32'd5;           check("slt equal false", 32'd0);
        ctrl = `ALU_SLTU; a = 32'hFFFF_FFFF;  b = 32'd1;           check("sltu 4294967295<1 false", 32'd0);
        ctrl = `ALU_SLTU; a = 32'd1;          b = 32'hFFFF_FFFF;   check("sltu 1<4294967295 true", 32'd1);

        // ---- unknown ALU opcode must be inert, not X -------------------------
        ctrl = 4'b1111;   a = 32'hDEAD_BEEF; b = 32'hCAFE_F00D; check("undefined ctrl -> 0", 32'd0);

        if (errors == 0) $display("PASS tb_alu (%0d checks)", checks);
        else             $display("FAIL tb_alu (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
