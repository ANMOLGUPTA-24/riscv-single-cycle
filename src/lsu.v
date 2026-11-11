//==============================================================================
// lsu.v : load / store alignment unit
//------------------------------------------------------------------------------
// The data memory is organised as 32-bit words, but RV32I can access bytes and
// half-words. This block is the glue:
//
//   STORES - take the register value and replicate it into the right byte lanes,
//            and produce a 4-bit write strobe saying which lanes to commit.
//            Replicating (rather than shifting) is a classic hardware trick:
//            the strobe already decides which lane lands, so the same wiring
//            serves every alignment.
//
//   LOADS  - pick the addressed byte / half-word out of the returned word and
//            either sign-extend (lb, lh) or zero-extend (lbu, lhu) it to 32 bits.
//
// Only addr[1:0] matters here - the word index goes to the memory itself.
// Misaligned accesses (e.g. lw at an address that is not a multiple of 4) are
// flagged on `misaligned` but not trapped: this core has no exception support,
// so the flag exists for the waveform and for future work.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module lsu #(
    parameter integer WIDTH = `XLEN
) (
    input  wire [1:0]        addr_lo,     // byte offset within the word
    input  wire [2:0]        funct3,      // size + signedness
    input  wire [WIDTH-1:0]  store_data,  // rs2
    input  wire [WIDTH-1:0]  mem_rdata,   // aligned word read from memory
    input  wire              mem_write,   // store in progress

    output reg  [3:0]        wstrb,       // per-byte write enable
    output reg  [WIDTH-1:0]  mem_wdata,   // data presented to memory
    output reg  [WIDTH-1:0]  load_data,   // value to write back to rd
    output reg               misaligned
);

    // ---------------------------------------------------------------- stores --
    always @(*) begin
        mem_wdata = store_data;
        wstrb     = 4'b0000;
        if (mem_write) begin
            case (funct3)
                `F3_SB : begin
                    mem_wdata = {4{store_data[7:0]}};
                    wstrb     = 4'b0001 << addr_lo;
                end
                `F3_SH : begin
                    mem_wdata = {2{store_data[15:0]}};
                    wstrb     = addr_lo[1] ? 4'b1100 : 4'b0011;
                end
                `F3_SW : begin
                    mem_wdata = store_data;
                    wstrb     = 4'b1111;
                end
                default : wstrb = 4'b0000;   // unsupported store size: do nothing
            endcase
        end
    end

    // ----------------------------------------------------------------- loads --
    reg [7:0]  sel_byte;
    reg [15:0] sel_half;

    always @(*) begin
        case (addr_lo)
            2'b00   : sel_byte = mem_rdata[7:0];
            2'b01   : sel_byte = mem_rdata[15:8];
            2'b10   : sel_byte = mem_rdata[23:16];
            default : sel_byte = mem_rdata[31:24];
        endcase

        sel_half = addr_lo[1] ? mem_rdata[31:16] : mem_rdata[15:0];

        case (funct3)
            `F3_LB  : load_data = {{24{sel_byte[7]}},  sel_byte};
            `F3_LBU : load_data = {24'b0,              sel_byte};
            `F3_LH  : load_data = {{16{sel_half[15]}}, sel_half};
            `F3_LHU : load_data = {16'b0,              sel_half};
            `F3_LW  : load_data = mem_rdata;
            default : load_data = mem_rdata;
        endcase
    end

    // ---------------------------------------------------------- alignment chk --
    // RISC-V encodes the ACCESS SIZE in funct3[1:0] for both loads and stores
    // (00 = byte, 01 = half, 10 = word); funct3[2] is only the zero-extend flag
    // on loads. So the alignment rule needs the size bits alone - listing the
    // load and store mnemonics separately would be redundant, because lh and sh
    // share funct3 = 001 and lw and sw share funct3 = 010.
    always @(*) begin
        case (funct3[1:0])
            2'b00   : misaligned = 1'b0;                  // byte: always aligned
            2'b01   : misaligned = addr_lo[0];            // half: must be even
            2'b10   : misaligned = (addr_lo != 2'b00);    // word: multiple of 4
            default : misaligned = 1'b0;                  // size 11 does not exist
        endcase
    end

endmodule

`default_nettype wire
