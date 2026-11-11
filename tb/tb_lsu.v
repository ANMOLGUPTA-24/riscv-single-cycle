//==============================================================================
// tb_lsu.v : self-checking testbench for the load/store alignment unit
//------------------------------------------------------------------------------
// Byte and half-word accesses at every alignment, plus sign vs zero extension.
// These are the cases that silently corrupt data if you get them wrong, because
// lw/sw keep working fine while lb/lh quietly return the wrong lane.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module tb_lsu;

    reg  [1:0]  addr_lo;
    reg  [2:0]  f3;
    reg  [31:0] store_data, mem_rdata;
    reg         mem_write;
    wire [3:0]  wstrb;
    wire [31:0] mem_wdata, load_data;
    wire        misaligned;
    integer errors = 0, checks = 0;

    lsu dut (
        .addr_lo(addr_lo), .funct3(f3), .store_data(store_data),
        .mem_rdata(mem_rdata), .mem_write(mem_write),
        .wstrb(wstrb), .mem_wdata(mem_wdata),
        .load_data(load_data), .misaligned(misaligned)
    );

    task check_load;
        input [255:0] name;
        input [31:0]  expected;
        begin
            checks = checks + 1;
            #1;
            if (load_data !== expected) begin
                errors = errors + 1;
                $display("  FAIL %0s: word=%08h off=%0d -> got %08h, expected %08h",
                         name, mem_rdata, addr_lo, load_data, expected);
            end
        end
    endtask

    task check_store;
        input [255:0] name;
        input [3:0]   e_strb;
        input [31:0]  e_wdata_masked;   // only the enabled lanes are compared
        integer k;
        reg [31:0] got_masked, exp_masked;
        begin
            checks = checks + 1;
            #1;
            got_masked = 32'h0; exp_masked = 32'h0;
            for (k = 0; k < 4; k = k + 1) begin
                if (e_strb[k]) begin
                    got_masked[8*k +: 8] = mem_wdata[8*k +: 8];
                    exp_masked[8*k +: 8] = e_wdata_masked[8*k +: 8];
                end
            end
            if (wstrb !== e_strb || got_masked !== exp_masked) begin
                errors = errors + 1;
                $display("  FAIL %0s: strb got %b exp %b, lanes got %08h exp %08h",
                         name, wstrb, e_strb, got_masked, exp_masked);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_lsu.vcd");
        $dumpvars(0, tb_lsu);
        $display("=== tb_lsu ===");

        mem_write = 1'b0;
        mem_rdata = 32'h8192_A3F0;    // lanes: [0]=F0 [1]=A3 [2]=92 [3]=81

        // ---- LW -------------------------------------------------------------
        f3 = `F3_LW;  addr_lo = 2'b00; check_load("lw", 32'h8192_A3F0);

        // ---- LB (sign-extended) ---------------------------------------------
        f3 = `F3_LB;  addr_lo = 2'b00; check_load("lb off0 (F0 -> -16)", 32'hFFFF_FFF0);
        f3 = `F3_LB;  addr_lo = 2'b01; check_load("lb off1 (A3)",        32'hFFFF_FFA3);
        f3 = `F3_LB;  addr_lo = 2'b10; check_load("lb off2 (92)",        32'hFFFF_FF92);
        f3 = `F3_LB;  addr_lo = 2'b11; check_load("lb off3 (81)",        32'hFFFF_FF81);

        // ---- LBU (zero-extended) --------------------------------------------
        f3 = `F3_LBU; addr_lo = 2'b00; check_load("lbu off0", 32'h0000_00F0);
        f3 = `F3_LBU; addr_lo = 2'b01; check_load("lbu off1", 32'h0000_00A3);
        f3 = `F3_LBU; addr_lo = 2'b10; check_load("lbu off2", 32'h0000_0092);
        f3 = `F3_LBU; addr_lo = 2'b11; check_load("lbu off3", 32'h0000_0081);

        // ---- positive byte stays positive -----------------------------------
        mem_rdata = 32'h0000_007F;
        f3 = `F3_LB;  addr_lo = 2'b00; check_load("lb 7F positive", 32'h0000_007F);
        mem_rdata = 32'h8192_A3F0;

        // ---- LH / LHU --------------------------------------------------------
        f3 = `F3_LH;  addr_lo = 2'b00; check_load("lh low  (A3F0 -> neg)", 32'hFFFF_A3F0);
        f3 = `F3_LH;  addr_lo = 2'b10; check_load("lh high (8192 -> neg)", 32'hFFFF_8192);
        f3 = `F3_LHU; addr_lo = 2'b00; check_load("lhu low",  32'h0000_A3F0);
        f3 = `F3_LHU; addr_lo = 2'b10; check_load("lhu high", 32'h0000_8192);
        mem_rdata = 32'h0000_1234;
        f3 = `F3_LH;  addr_lo = 2'b00; check_load("lh 1234 positive", 32'h0000_1234);

        // ---- stores: strobe and lane placement -------------------------------
        mem_write = 1'b1;
        store_data = 32'hAABB_CCDD;
        f3 = `F3_SW; addr_lo = 2'b00; check_store("sw",      4'b1111, 32'hAABB_CCDD);
        f3 = `F3_SB; addr_lo = 2'b00; check_store("sb off0", 4'b0001, 32'h0000_00DD);
        f3 = `F3_SB; addr_lo = 2'b01; check_store("sb off1", 4'b0010, 32'h0000_DD00);
        f3 = `F3_SB; addr_lo = 2'b10; check_store("sb off2", 4'b0100, 32'h00DD_0000);
        f3 = `F3_SB; addr_lo = 2'b11; check_store("sb off3", 4'b1000, 32'hDD00_0000);
        f3 = `F3_SH; addr_lo = 2'b00; check_store("sh low",  4'b0011, 32'h0000_CCDD);
        f3 = `F3_SH; addr_lo = 2'b10; check_store("sh high", 4'b1100, 32'hCCDD_0000);

        // ---- no store means no write strobe, ever ----------------------------
        mem_write = 1'b0;
        f3 = `F3_SW; addr_lo = 2'b00;
        checks = checks + 1; #1;
        if (wstrb !== 4'b0000) begin
            errors = errors + 1;
            $display("  FAIL wstrb must be 0 when mem_write=0 (got %b)", wstrb);
        end

        // ---- misalignment flag -----------------------------------------------
        mem_write = 1'b1;
        f3 = `F3_SW; addr_lo = 2'b01;
        checks = checks + 1; #1;
        if (misaligned !== 1'b1) begin errors = errors + 1; $display("  FAIL sw@1 should flag misaligned"); end
        f3 = `F3_SH; addr_lo = 2'b10;
        checks = checks + 1; #1;
        if (misaligned !== 1'b0) begin errors = errors + 1; $display("  FAIL sh@2 is aligned"); end
        f3 = `F3_SB; addr_lo = 2'b11;
        checks = checks + 1; #1;
        if (misaligned !== 1'b0) begin errors = errors + 1; $display("  FAIL sb is always aligned"); end

        if (errors == 0) $display("PASS tb_lsu (%0d checks)", checks);
        else             $display("FAIL tb_lsu (%0d/%0d checks failed)", errors, checks);
        $finish;
    end

endmodule
