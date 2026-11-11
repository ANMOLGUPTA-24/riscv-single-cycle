//==============================================================================
// instr_mem.v : instruction memory (read-only, asynchronous read)
//------------------------------------------------------------------------------
// A single-cycle processor must fetch, decode, execute, access memory and write
// back all inside one clock period, so the instruction fetch CANNOT wait for a
// clock edge. The read is therefore combinational (asynchronous).
//
// On an FPGA this maps to distributed / LUT RAM rather than block RAM, because
// block RAM has a registered (synchronous) output. That is the main reason this
// memory is kept small: DEPTH words, word-addressed.
//
// The word index drops the two low address bits, because instructions are 4
// bytes apart: address 0x0000 -> word 0, 0x0004 -> word 1, and so on.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module instr_mem #(
    parameter integer WIDTH = `XLEN,
    parameter integer DEPTH = 1024,          // words (4 KiB of code)
    parameter         INIT_FILE = ""
) (
    input  wire [WIDTH-1:0] addr,
    output wire [31:0]      rdata
);

    localparam integer IDX_BITS = $clog2(DEPTH);

    reg [31:0] mem [0:DEPTH-1];

    // Load the program at time 0. $readmemh is a simulation construct; synthesis
    // tools either use it as a ROM initialiser or ignore it harmlessly.
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h00000000;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    wire [IDX_BITS-1:0] word_idx = addr[IDX_BITS+1:2];

    assign rdata = mem[word_idx];

endmodule

`default_nettype wire
