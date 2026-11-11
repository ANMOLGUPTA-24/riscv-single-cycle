//==============================================================================
// tb_data_mem.v : self-checking testbench for the data memory
//------------------------------------------------------------------------------
// Confirms that the read is truly asynchronous (data appears without a clock
// edge) and that the byte write strobes commit exactly the lanes requested and
// leave the other lanes untouched.
//==============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_data_mem;

    reg         clk = 0;
    reg  [31:0] addr = 0, wdata = 0;
    reg  [3:0]  wstrb = 4'b0000;
    wire [31:0] rdata;
    integer errors = 0, checks = 0;

    data_mem #(.DEPTH(64)) dut (
        .clk(clk), .addr(addr), .wdata(wdata), .wstrb(wstrb), .rdata(rdata)
    );

    always #5 clk = ~clk;

    task wr;
        input [31:0] a;
        input [31:0] d;
        input [3:0]  s;
        begin
            @(negedge clk);
            addr = a; wdata = d; wstrb = s;
            @(posedge clk);
            @(negedge clk);
            wstrb = 4'b0000;
        end
    endtask

    task check;
        input [255:0] name;
        input [31:0]  a;
        input [31:0]  expected;
        begin
            checks = checks + 1;
            addr = a;
            #1;                       // no clock edge: read must be combinational
            if (rdata !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: addr=%08h -> got %08h, expected %08h",
                         name, a, rdata, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_data_mem.vcd");
        $dumpvars(0, tb_data_mem);
        $display("=== tb_data_mem ===");

        check("zero-initialised", 32'h0, 32'h0000_0000);

        // ---- full word writes ------------------------------------------------
        wr(32'h0000_0000, 32'h1122_3344, 4'b1111);
        check("word 0", 32'h0000_0000, 32'h1122_3344);
        wr(32'h0000_0004, 32'hAABB_CCDD, 4'b1111);
        check("word 1", 32'h0000_0004, 32'hAABB_CCDD);
        check("word 0 untouched", 32'h0000_0000, 32'h1122_3344);

        // ---- addr[1:0] is ignored: it belongs to the LSU ----------------------
        check("addr 1 maps to word 0", 32'h0000_0001, 32'h1122_3344);
        check("addr 3 maps to word 0", 32'h0000_0003, 32'h1122_3344);

        // ---- single-byte writes leave the neighbours alone ---------------------
        wr(32'h0000_0000, 32'hFFFF_FFFF, 4'b0001);
        check("sb lane 0", 32'h0000_0000, 32'h1122_33FF);
        wr(32'h0000_0000, 32'h0000_0000, 4'b0100);
        check("sb lane 2", 32'h0000_0000, 32'h1100_33FF);

        // ---- half-word writes --------------------------------------------------
        wr(32'h0000_0008, 32'hFFFF_FFFF, 4'b1111);
        wr(32'h0000_0008, 32'h0000_1234, 4'b0011);
        check("sh low half",  32'h0000_0008, 32'hFFFF_1234);
        wr(32'h0000_0008, 32'h5678_0000, 4'b1100);
        check("sh high half", 32'h0000_0008, 32'h5678_1234);

        // ---- strobe 0 writes nothing -------------------------------------------
        wr(32'h0000_0008, 32'h0000_0000, 4'b0000);
        check("strb=0 is a no-op", 32'h0000_0008, 32'h5678_1234);

        // ---- last word in range -------------------------------------------------
        wr(32'd252, 32'hCAFE_F00D, 4'b1111);    // word 63 of 64
        check("last word", 32'd252, 32'hCAFE_F00D);

        if (errors == 0) $display("PASS tb_data_mem (%0d checks)", checks);
        else             $display("FAIL tb_data_mem (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
