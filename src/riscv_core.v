//==============================================================================
// riscv_core.v : single-cycle RV32I core (datapath + control, no memories)
//------------------------------------------------------------------------------
// One instruction per clock cycle. Within a single cycle, in this order of
// combinational cause and effect:
//
//   1. FETCH      imem_addr = PC, the instruction comes back on imem_rdata
//   2. DECODE     fields are sliced out; control_unit sets the switches;
//                 imm_gen builds the immediate; the register file is read
//   3. EXECUTE    the ALU computes; branch_unit decides taken / not taken
//   4. MEMORY     dmem_addr is driven; a load's data comes back on dmem_rdata
//   5. WRITE-BACK the result mux picks ALU / memory / PC+4
//
// None of 1-5 is clocked. The only state in the whole core is the PC and the
// register file (plus the memories outside). At the rising clock edge, the PC
// and the register file capture the values that settled during the cycle, and
// the next instruction begins. The clock period must therefore be long enough
// for the WHOLE chain - that is single-cycle's one big weakness.
//
// Memories are kept outside the core so that the synthesisable unit is pure
// logic, and so the same core can be dropped onto an FPGA with block RAM, a
// cache, or a bus wrapper without touching this file.
//==============================================================================
`include "riscv_defs.vh"
`timescale 1ns/1ps
`default_nettype none

module riscv_core #(
    parameter integer WIDTH = `XLEN,
    parameter [WIDTH-1:0] RESET_ADDR = {WIDTH{1'b0}}
) (
    input  wire             clk,
    input  wire             rst_n,

    // instruction memory port (asynchronous read)
    output wire [WIDTH-1:0] imem_addr,
    input  wire [31:0]      imem_rdata,

    // data memory port (asynchronous read, synchronous write)
    output wire [WIDTH-1:0] dmem_addr,
    output wire [WIDTH-1:0] dmem_wdata,
    output wire [3:0]       dmem_wstrb,
    input  wire [WIDTH-1:0] dmem_rdata,

    // debug / observation (free to leave unconnected)
    output wire [WIDTH-1:0] dbg_pc,
    output wire [31:0]      dbg_instr,
    output wire             dbg_reg_write,
    output wire [4:0]       dbg_rd_addr,
    output wire [WIDTH-1:0] dbg_rd_data,
    output wire             dbg_illegal,
    output wire             dbg_misaligned
);

    //--------------------------------------------------------------------------
    // 1. FETCH
    //--------------------------------------------------------------------------
    wire [WIDTH-1:0] pc_current;
    wire [WIDTH-1:0] next_pc;

    pc #(
        .WIDTH      (WIDTH),
        .RESET_ADDR (RESET_ADDR)
    ) u_pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (1'b1),           // never stalls: every instruction takes 1 cycle
        .next_pc (next_pc),
        .pc_out  (pc_current)
    );

    assign imem_addr = pc_current;
    wire [31:0] instr = imem_rdata;

    //--------------------------------------------------------------------------
    // 2. DECODE - field extraction
    //--------------------------------------------------------------------------
    wire [6:0] opcode    = instr[6:0];
    wire [4:0] rd_addr   = instr[11:7];
    wire [2:0] funct3    = instr[14:12];
    wire [4:0] rs1_addr  = instr[19:15];
    wire [4:0] rs2_addr  = instr[24:20];
    wire       funct7_b5 = instr[30];

    //--------------------------------------------------------------------------
    // 2. DECODE - control
    //--------------------------------------------------------------------------
    wire       reg_write;
    wire [1:0] alu_src_a;
    wire       alu_src_b;
    wire [1:0] alu_op;
    wire [2:0] imm_sel;
    wire       mem_read;
    wire       mem_write;
    wire [1:0] result_src;
    wire       branch;
    wire       jump;
    wire       jalr;
    wire       illegal;

    control_unit u_control (
        .opcode     (opcode),
        .reg_write  (reg_write),
        .alu_src_a  (alu_src_a),
        .alu_src_b  (alu_src_b),
        .alu_op     (alu_op),
        .imm_sel    (imm_sel),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .result_src (result_src),
        .branch     (branch),
        .jump       (jump),
        .jalr       (jalr),
        .illegal    (illegal)
    );

    wire [3:0] alu_ctrl;
    alu_control u_alu_control (
        .alu_op    (alu_op),
        .funct3    (funct3),
        .funct7_b5 (funct7_b5),
        .alu_ctrl  (alu_ctrl)
    );

    wire [WIDTH-1:0] imm;
    imm_gen #(.WIDTH(WIDTH)) u_imm_gen (
        .instr   (instr),
        .imm_sel (imm_sel),
        .imm_out (imm)
    );

    //--------------------------------------------------------------------------
    // 2. DECODE - register read / write-back port
    //--------------------------------------------------------------------------
    wire [WIDTH-1:0] rs1_data;
    wire [WIDTH-1:0] rs2_data;
    reg  [WIDTH-1:0] rd_data;

    reg_file #(.WIDTH(WIDTH)) u_reg_file (
        .clk      (clk),
        .rst_n    (rst_n),
        .we       (reg_write),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    //--------------------------------------------------------------------------
    // 3. EXECUTE
    //--------------------------------------------------------------------------
    reg  [WIDTH-1:0] alu_a;
    always @(*) begin
        case (alu_src_a)
            `SRCA_RS1  : alu_a = rs1_data;
            `SRCA_PC   : alu_a = pc_current;     // auipc
            `SRCA_ZERO : alu_a = {WIDTH{1'b0}};  // lui
            default    : alu_a = rs1_data;
        endcase
    end

    wire [WIDTH-1:0] alu_b = (alu_src_b == `SRCB_IMM) ? imm : rs2_data;

    wire [WIDTH-1:0] alu_result;
    alu #(.WIDTH(WIDTH)) u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_ctrl (alu_ctrl),
        .result   (alu_result)
    );

    wire branch_taken;
    branch_unit #(.WIDTH(WIDTH)) u_branch_unit (
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .funct3   (funct3),
        .taken    (branch_taken)
    );

    //--------------------------------------------------------------------------
    // 4. MEMORY
    //--------------------------------------------------------------------------
    wire [WIDTH-1:0] load_data;
    wire             misaligned;

    lsu #(.WIDTH(WIDTH)) u_lsu (
        .addr_lo    (alu_result[1:0]),
        .funct3     (funct3),
        .store_data (rs2_data),
        .mem_rdata  (dmem_rdata),
        .mem_write  (mem_write),
        .wstrb      (dmem_wstrb),
        .mem_wdata  (dmem_wdata),
        .load_data  (load_data),
        .misaligned (misaligned)
    );

    assign dmem_addr = alu_result;   // loads and stores both address rs1 + imm

    //--------------------------------------------------------------------------
    // 5. WRITE-BACK
    //--------------------------------------------------------------------------
    wire [WIDTH-1:0] pc_plus4 = pc_current + 32'd4;

    always @(*) begin
        case (result_src)
            `RES_ALU : rd_data = alu_result;
            `RES_MEM : rd_data = load_data;
            `RES_PC4 : rd_data = pc_plus4;      // jal / jalr return address
            default  : rd_data = alu_result;
        endcase
    end

    //--------------------------------------------------------------------------
    // NEXT PC
    //--------------------------------------------------------------------------
    // Separate adder for PC-relative targets: the ALU cannot do this job for a
    // branch, because for a branch the ALU is idle but the comparator result
    // arrives from branch_unit, and for jal there is no rs1 to add to.
    wire [WIDTH-1:0] pc_target = pc_current + imm;

    // JALR: target comes from the ALU (rs1 + imm) with bit 0 forced to zero,
    // exactly as the RISC-V spec requires.
    wire [WIDTH-1:0] jalr_target = {alu_result[WIDTH-1:1], 1'b0};

    reg [1:0] pc_src;
    always @(*) begin
        if (jalr)                            pc_src = `PCSRC_ALU;
        else if (jump || (branch && branch_taken)) pc_src = `PCSRC_TARGET;
        else                                 pc_src = `PCSRC_PC4;
    end

    reg [WIDTH-1:0] next_pc_r;
    always @(*) begin
        case (pc_src)
            `PCSRC_TARGET : next_pc_r = pc_target;
            `PCSRC_ALU    : next_pc_r = jalr_target;
            default       : next_pc_r = pc_plus4;
        endcase
    end
    assign next_pc = next_pc_r;

    //--------------------------------------------------------------------------
    // debug taps
    //--------------------------------------------------------------------------
    assign dbg_pc         = pc_current;
    assign dbg_instr      = instr;
    assign dbg_reg_write  = reg_write && (rd_addr != 5'd0);
    assign dbg_rd_addr    = rd_addr;
    assign dbg_rd_data    = rd_data;
    assign dbg_illegal    = illegal;
    assign dbg_misaligned = misaligned && (mem_read || mem_write);

endmodule

`default_nettype wire
