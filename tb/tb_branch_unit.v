//==============================================================================
// tb_branch_unit.v : self-checking testbench for the branch comparator
//------------------------------------------------------------------------------
// Every one of the six branches is tested in both directions, and the
// signed/unsigned boundary cases (-1 vs 1, 0x8000_0000 vs 0) are tested
// explicitly because that is where a careless comparator breaks.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module tb_branch_unit;

    reg  [31:0] a, b;
    reg  [2:0]  f3;
    wire        taken;
    integer errors = 0, checks = 0;

    branch_unit dut (.rs1_data(a), .rs2_data(b), .funct3(f3), .taken(taken));

    task check;
        input [255:0] name;
        input         expected;
        begin
            checks = checks + 1;
            #1;
            if (taken !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: a=%08h b=%08h f3=%b -> got %b, expected %b",
                         name, a, b, f3, taken, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_branch_unit.vcd");
        $dumpvars(0, tb_branch_unit);
        $display("=== tb_branch_unit ===");

        // beq / bne
        f3 = `F3_BEQ;  a = 32'd5;         b = 32'd5;         check("beq equal", 1'b1);
        f3 = `F3_BEQ;  a = 32'd5;         b = 32'd6;         check("beq not equal", 1'b0);
        f3 = `F3_BNE;  a = 32'd5;         b = 32'd6;         check("bne differ", 1'b1);
        f3 = `F3_BNE;  a = 32'd5;         b = 32'd5;         check("bne same", 1'b0);

        // blt / bge  (signed)
        f3 = `F3_BLT;  a = 32'hFFFF_FFFF; b = 32'd1;         check("blt -1<1", 1'b1);
        f3 = `F3_BLT;  a = 32'd1;         b = 32'hFFFF_FFFF; check("blt 1<-1", 1'b0);
        f3 = `F3_BLT;  a = 32'd5;         b = 32'd5;         check("blt equal", 1'b0);
        f3 = `F3_BLT;  a = 32'h8000_0000; b = 32'd0;         check("blt INT_MIN<0", 1'b1);
        f3 = `F3_BGE;  a = 32'd5;         b = 32'd5;         check("bge equal", 1'b1);
        f3 = `F3_BGE;  a = 32'd1;         b = 32'hFFFF_FFFF; check("bge 1>=-1", 1'b1);
        f3 = `F3_BGE;  a = 32'hFFFF_FFFF; b = 32'd1;         check("bge -1>=1", 1'b0);

        // bltu / bgeu  (unsigned)
        f3 = `F3_BLTU; a = 32'd1;         b = 32'hFFFF_FFFF; check("bltu 1<max", 1'b1);
        f3 = `F3_BLTU; a = 32'hFFFF_FFFF; b = 32'd1;         check("bltu max<1", 1'b0);
        f3 = `F3_BLTU; a = 32'h8000_0000; b = 32'd0;         check("bltu 2^31<0", 1'b0);
        f3 = `F3_BGEU; a = 32'hFFFF_FFFF; b = 32'd1;         check("bgeu max>=1", 1'b1);
        f3 = `F3_BGEU; a = 32'd0;         b = 32'd0;         check("bgeu equal", 1'b1);
        f3 = `F3_BGEU; a = 32'd1;         b = 32'hFFFF_FFFF; check("bgeu 1>=max", 1'b0);

        // reserved funct3 values must never branch
        f3 = 3'b010;   a = 32'd1;         b = 32'd1;         check("reserved f3=010", 1'b0);
        f3 = 3'b011;   a = 32'd1;         b = 32'd1;         check("reserved f3=011", 1'b0);

        if (errors == 0) $display("PASS tb_branch_unit (%0d checks)", checks);
        else             $display("FAIL tb_branch_unit (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
