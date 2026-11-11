//==============================================================================
// tb_reg_file.v : self-checking testbench for the register file
//------------------------------------------------------------------------------
// Checks the three things that matter: a write followed by a read works, x0
// cannot be written, and both read ports work independently (including the
// case where both read the same register).
//==============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_reg_file;

    reg         clk = 0, rst_n = 0, we = 0;
    reg  [4:0]  rs1_addr = 0, rs2_addr = 0, rd_addr = 0;
    reg  [31:0] rd_data = 0;
    wire [31:0] rs1_data, rs2_data;
    integer errors = 0, checks = 0, i;

    reg_file dut (
        .clk(clk), .rst_n(rst_n), .we(we),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    always #5 clk = ~clk;      // 100 MHz

    // Write one register, synchronously.
    task wr;
        input [4:0]  a;
        input [31:0] d;
        begin
            @(negedge clk);    // change inputs away from the active edge
            we = 1'b1; rd_addr = a; rd_data = d;
            @(posedge clk);
            @(negedge clk);
            we = 1'b0;
        end
    endtask

    task check1;
        input [255:0] name;
        input [4:0]   a;
        input [31:0]  expected;
        begin
            checks = checks + 1;
            rs1_addr = a;
            #1;
            if (rs1_data !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: x%0d -> got %08h, expected %08h",
                         name, a, rs1_data, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_reg_file.vcd");
        $dumpvars(0, tb_reg_file);
        $display("=== tb_reg_file ===");

        // ---- reset clears everything ---------------------------------------
        rst_n = 0; @(posedge clk); @(negedge clk); rst_n = 1;
        for (i = 0; i < 32; i = i + 1) begin
            check1("after reset", i[4:0], 32'h0);
        end

        // ---- basic write / read --------------------------------------------
        wr(5'd1,  32'hDEAD_BEEF);  check1("write x1",  5'd1,  32'hDEAD_BEEF);
        wr(5'd31, 32'h1234_5678);  check1("write x31", 5'd31, 32'h1234_5678);
        check1("x1 unchanged by x31 write", 5'd1, 32'hDEAD_BEEF);

        // ---- x0 must stay zero ---------------------------------------------
        wr(5'd0, 32'hFFFF_FFFF);   check1("x0 discards writes", 5'd0, 32'h0);

        // ---- overwrite ------------------------------------------------------
        wr(5'd1, 32'h0000_0001);   check1("overwrite x1", 5'd1, 32'h0000_0001);

        // ---- write disabled -------------------------------------------------
        @(negedge clk);
        we = 1'b0; rd_addr = 5'd1; rd_data = 32'hAAAA_AAAA;
        @(posedge clk); @(negedge clk);
        check1("we=0 does not write", 5'd1, 32'h0000_0001);

        // ---- both read ports ------------------------------------------------
        wr(5'd7,  32'h0000_00AA);
        wr(5'd8,  32'h0000_00BB);
        rs1_addr = 5'd7; rs2_addr = 5'd8; #1;
        checks = checks + 1;
        if (rs1_data !== 32'h0000_00AA || rs2_data !== 32'h0000_00BB) begin
            errors = errors + 1;
            $display("  FAIL dual read: %08h / %08h", rs1_data, rs2_data);
        end
        rs1_addr = 5'd7; rs2_addr = 5'd7; #1;
        checks = checks + 1;
        if (rs1_data !== rs2_data) begin
            errors = errors + 1;
            $display("  FAIL same-register dual read");
        end

        if (errors == 0) $display("PASS tb_reg_file (%0d checks)", checks);
        else             $display("FAIL tb_reg_file (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
