`timescale 1ns/1ps
`default_nettype none

// Module: pc
// Purpose: holds the address of the current instruction
// Type: sequential

module pc (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc_current
);

    always @(posedge clk) begin
        if (rst) pc_current <= 32'b0;
        else     pc_current <= pc_next;
    end

endmodule

`default_nettype wire
