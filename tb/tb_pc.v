//==============================================================================
// tb_pc.v : self-checking testbench for the program counter register
//------------------------------------------------------------------------------
// Values are sampled just after the clock edge has settled (@(negedge clk))
// rather than at the edge itself, so the test never races the DUT's own
// non-blocking update.
//==============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_pc;

    reg         clk = 0, rst_n = 0, en = 1;
    reg  [31:0] next_pc = 0;
    wire [31:0] pc_out;
    integer errors = 0, checks = 0;

    pc #(.WIDTH(32), .RESET_ADDR(32'h0000_0000)) dut (
        .clk(clk), .rst_n(rst_n), .en(en), .next_pc(next_pc), .pc_out(pc_out)
    );

    always #5 clk = ~clk;

    task check;
        input [255:0] name;
        input [31:0]  expected;
        begin
            checks = checks + 1;
            if (pc_out !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: got %08h, expected %08h", name, pc_out, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_pc.vcd");
        $dumpvars(0, tb_pc);
        $display("=== tb_pc ===");

        // ---- reset ------------------------------------------------------------
        rst_n = 0; next_pc = 32'hDEAD_BEEF;
        @(posedge clk); @(negedge clk);
        check("reset to 0", 32'h0000_0000);

        // ---- sequential stepping ----------------------------------------------
        rst_n = 1;
        next_pc = 32'h0000_0004; @(posedge clk); @(negedge clk); check("step to 4", 32'h0000_0004);
        next_pc = 32'h0000_0008; @(posedge clk); @(negedge clk); check("step to 8", 32'h0000_0008);

        // ---- an arbitrary (jump) target -----------------------------------------
        next_pc = 32'h0000_0100; @(posedge clk); @(negedge clk); check("jump to 0x100", 32'h0000_0100);

        // ---- en=0 holds the PC: the hook a future pipeline needs for stalls -----
        en = 0; next_pc = 32'h0000_0200;
        @(posedge clk); @(negedge clk); check("en=0 holds", 32'h0000_0100);
        @(posedge clk); @(negedge clk); check("en=0 still holds", 32'h0000_0100);
        en = 1;
        @(posedge clk); @(negedge clk); check("en=1 resumes", 32'h0000_0200);

        // ---- reset in the middle of a run ---------------------------------------
        rst_n = 0; next_pc = 32'h0000_0300;
        @(posedge clk); @(negedge clk); check("mid-run reset", 32'h0000_0000);
        rst_n = 1;
        @(posedge clk); @(negedge clk); check("resumes after reset", 32'h0000_0300);

        if (errors == 0) $display("PASS tb_pc (%0d checks)", checks);
        else             $display("FAIL tb_pc (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
