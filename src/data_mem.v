//==============================================================================
// data_mem.v : data memory (asynchronous read, synchronous byte-enabled write)
//------------------------------------------------------------------------------
// Read: combinational, for the same single-cycle reason as the instruction
//       memory - a load must have its data back before the clock edge that
//       writes the register file.
// Write: on the rising edge, one byte lane per bit of wstrb. Byte lanes are what
//       make sb and sh possible without a read-modify-write.
//
// Addresses wrap within DEPTH words; there is no bus error. The memory is
// word-organised, so addr[1:0] never reaches here - the LSU handles it.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module data_mem #(
    parameter integer WIDTH = `XLEN,
    parameter integer DEPTH = 1024,         // words (4 KiB of data)
    parameter         INIT_FILE = ""
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] addr,
    input  wire [WIDTH-1:0] wdata,
    input  wire [3:0]       wstrb,
    output wire [WIDTH-1:0] rdata
);

    localparam integer IDX_BITS = $clog2(DEPTH);

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h00000000;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    wire [IDX_BITS-1:0] word_idx = addr[IDX_BITS+1:2];

    assign rdata = mem[word_idx];

    always @(posedge clk) begin
        if (wstrb[0]) mem[word_idx][7:0]   <= wdata[7:0];
        if (wstrb[1]) mem[word_idx][15:8]  <= wdata[15:8];
        if (wstrb[2]) mem[word_idx][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[word_idx][31:24] <= wdata[31:24];
    end

endmodule

`default_nettype wire
