//==============================================================================
// imm_gen.v : immediate extractor and sign-extender
//------------------------------------------------------------------------------
// RISC-V scatters the immediate bits around the instruction word. It looks
// perverse, but it is deliberate: the sign bit is ALWAYS instr[31], and each
// immediate bit keeps the same position across formats wherever possible, so
// the hardware is just wiring - no shifters, no muxes per bit.
//
// Formats (bit numbers are positions in the *immediate*, not the instruction):
//   I : instr[31:20]                                     -> imm[11:0]
//   S : instr[31:25], instr[11:7]                        -> imm[11:0]
//   B : instr[31], instr[7], instr[30:25], instr[11:8]    -> imm[12:1], imm[0]=0
//   U : instr[31:12]                                     -> imm[31:12], low 12 = 0
//   J : instr[31], instr[19:12], instr[20], instr[30:21]  -> imm[20:1], imm[0]=0
//
// B and J immediates are always even (instructions are 2- or 4-byte aligned),
// so bit 0 is not stored at all - it is hard-wired to 0.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module imm_gen #(
    parameter integer WIDTH = `XLEN
) (
    // The whole instruction word comes in, but instr[6:0] (the opcode) is
    // deliberately unused here: the control unit has already looked at the
    // opcode and tells us which format to extract via imm_sel. Keeping the
    // opcode out of this module is what keeps it pure wiring.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0]       instr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [2:0]        imm_sel,
    output reg  [WIDTH-1:0]  imm_out
);

    always @(*) begin
        case (imm_sel)
            `IMM_I : imm_out = {{20{instr[31]}}, instr[31:20]};

            `IMM_S : imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            `IMM_B : imm_out = {{19{instr[31]}}, instr[31], instr[7],
                                instr[30:25], instr[11:8], 1'b0};

            `IMM_U : imm_out = {instr[31:12], 12'b0};

            `IMM_J : imm_out = {{11{instr[31]}}, instr[31], instr[19:12],
                                instr[20], instr[30:21], 1'b0};

            default : imm_out = {WIDTH{1'b0}};
        endcase
    end

endmodule

`default_nettype wire
