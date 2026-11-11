//==============================================================================
// tb_riscv_top.v : full-processor testbench
//------------------------------------------------------------------------------
// Runs a complete program on the RTL and compares the end state against the
// Python reference simulator (tools/iss.py), which was written independently
// from the spec. The RTL is never compared against itself.
//
// Flow:
//   1. the instruction and data memory images (.hex / .data.hex) are loaded by
//      the memories themselves via $readmemh
//   2. the expected end state (.rexp / .mexp) is loaded here
//   3. reset is released and the core runs
//   4. the program parks on a self-loop jump (`j halt`); the testbench sees the
//      PC stop changing and stops the clock
//   5. all 32 registers and the first EXPECT_WORDS data words are compared
//
// Override the file names from the command line, e.g.
//   iverilog -Ptb_riscv_top.PROG_NAME=\"fib\" ...
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module tb_riscv_top;

    parameter         PROG_NAME    = "unnamed";
    parameter         IMEM_FILE    = "";
    parameter         DMEM_FILE    = "";
    parameter         REXP_FILE    = "";
    parameter         MEXP_FILE    = "";
    parameter integer EXPECT_WORDS = 32;
    parameter integer TIMEOUT      = 100000;   // clock cycles
    parameter integer TRACE        = 0;        // 1 = print every instruction
    parameter         VCD_FILE     = "build/tb_riscv_top.vcd";

    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    wire [31:0] dbg_pc, dbg_instr, dbg_rd_data;
    wire [4:0]  dbg_rd_addr;
    wire        dbg_reg_write, dbg_illegal, dbg_misaligned;

    riscv_top #(
        .IMEM_FILE (IMEM_FILE),
        .DMEM_FILE (DMEM_FILE)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_reg_write  (dbg_reg_write),
        .dbg_rd_addr    (dbg_rd_addr),
        .dbg_rd_data    (dbg_rd_data),
        .dbg_illegal    (dbg_illegal),
        .dbg_misaligned (dbg_misaligned)
    );

    always #5 clk = ~clk;      // 100 MHz

    // ---- expected end state, from the reference simulator -------------------
    reg [31:0] exp_regs [0:31];
    reg [31:0] exp_mem  [0:1023];

    // ---- run-time bookkeeping ------------------------------------------------
    integer cycles        = 0;
    integer instr_count   = 0;
    integer errors        = 0;
    integer illegal_seen  = 0;
    integer misalign_seen = 0;
    reg [31:0] prev_pc    = 32'hFFFF_FFFF;
    reg        halted     = 1'b0;

    integer i;

    // ABI register names, so a failure report is readable.
    function [31:0] regname;
        input integer n;
        begin
            case (n)
                 0: regname = "x0  ";   1: regname = "ra  ";   2: regname = "sp  ";
                 3: regname = "gp  ";   4: regname = "tp  ";   5: regname = "t0  ";
                 6: regname = "t1  ";   7: regname = "t2  ";   8: regname = "s0  ";
                 9: regname = "s1  ";  10: regname = "a0  ";  11: regname = "a1  ";
                12: regname = "a2  ";  13: regname = "a3  ";  14: regname = "a4  ";
                15: regname = "a5  ";  16: regname = "a6  ";  17: regname = "a7  ";
                18: regname = "s2  ";  19: regname = "s3  ";  20: regname = "s4  ";
                21: regname = "s5  ";  22: regname = "s6  ";  23: regname = "s7  ";
                24: regname = "s8  ";  25: regname = "s9  ";  26: regname = "s10 ";
                27: regname = "s11 ";  28: regname = "t3  ";  29: regname = "t4  ";
                30: regname = "t5  ";  31: regname = "t6  ";
                default: regname = "??  ";
            endcase
        end
    endfunction

    initial begin
        $dumpfile(VCD_FILE);
        $dumpvars(0, tb_riscv_top);

        for (i = 0; i < 32; i = i + 1)   exp_regs[i] = 32'h0;
        for (i = 0; i < 1024; i = i + 1) exp_mem[i]  = 32'h0;
        if (REXP_FILE != "") $readmemh(REXP_FILE, exp_regs);
        if (MEXP_FILE != "") $readmemh(MEXP_FILE, exp_mem);

        $display("");
        $display("=== tb_riscv_top : %0s ===", PROG_NAME);

        // ---- reset -----------------------------------------------------------
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        if (dbg_pc !== 32'h0) begin
            errors = errors + 1;
            $display("  FAIL reset: pc = %08h, expected 00000000", dbg_pc);
        end
        rst_n = 1'b1;

        // ---- run -------------------------------------------------------------
        while (!halted && cycles < TIMEOUT) begin
            @(posedge clk);
            #1;                                   // let the new PC settle
            cycles = cycles + 1;
            if (TRACE)
                $display("  %5d  pc=%08h  instr=%08h%0s", cycles, dbg_pc, dbg_instr,
                         dbg_reg_write ? "  (writes rd)" : "");
            if (dbg_illegal)    illegal_seen  = illegal_seen  + 1;
            if (dbg_misaligned) misalign_seen = misalign_seen + 1;
            instr_count = instr_count + 1;
            // A `j halt` self-loop leaves the PC unchanged: that is our "done".
            if (dbg_pc === prev_pc) halted = 1'b1;
            prev_pc = dbg_pc;
        end

        if (!halted) begin
            errors = errors + 1;
            $display("  FAIL timeout after %0d cycles (pc=%08h) - infinite loop?",
                     cycles, dbg_pc);
        end else begin
            $display("  halted at pc=%08h after %0d instructions (%0d cycles)",
                     dbg_pc, instr_count, cycles);
        end

        // ---- flags that should never fire ------------------------------------
        if (illegal_seen != 0) begin
            errors = errors + 1;
            $display("  FAIL decoded %0d illegal instruction(s)", illegal_seen);
        end
        if (misalign_seen != 0) begin
            errors = errors + 1;
            $display("  FAIL %0d misaligned memory access(es)", misalign_seen);
        end

        // ---- compare the register file ----------------------------------------
        for (i = 0; i < 32; i = i + 1) begin
            if (i == 0) begin
                if (dut.u_core.u_reg_file.regs[0] !== 32'h0 &&
                    exp_regs[0] === 32'h0) begin
                    // x0 is forced to zero on the read ports, but the storage
                    // itself must never be written either.
                    errors = errors + 1;
                    $display("  FAIL x0 storage was written: %08h",
                             dut.u_core.u_reg_file.regs[0]);
                end
            end else if (dut.u_core.u_reg_file.regs[i] !== exp_regs[i]) begin
                errors = errors + 1;
                $display("  FAIL %0s (x%0d): rtl=%08h  reference=%08h",
                         regname(i), i, dut.u_core.u_reg_file.regs[i], exp_regs[i]);
            end
        end

        // ---- compare data memory ------------------------------------------------
        for (i = 0; i < EXPECT_WORDS; i = i + 1) begin
            if (dut.u_data_mem.mem[i] !== exp_mem[i]) begin
                errors = errors + 1;
                $display("  FAIL mem[0x%03h] (word %0d): rtl=%08h  reference=%08h",
                         i*4, i, dut.u_data_mem.mem[i], exp_mem[i]);
            end
        end

        if (errors == 0)
            $display("PASS %0s : 32 registers + %0d memory words match the reference model",
                     PROG_NAME, EXPECT_WORDS);
        else
            $display("FAIL %0s : %0d mismatch(es)", PROG_NAME, errors);

        $finish;
    end

endmodule
