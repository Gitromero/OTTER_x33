`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ThreeMux
// Description: Generic 3-to-1 MUX, used for the forwarding paths into EX.
//////////////////////////////////////////////////////////////////////////////////
module ThreeMux(
    input logic [1:0] SEL,
    input logic [31:0] ZERO,
    input logic [31:0] ONE,
    input logic [31:0] TWO,
    output logic [31:0] OUT
    );

    always_comb begin
        case(SEL)
            2'b00: begin OUT = ZERO; end
            2'b01: begin OUT = ONE; end
            2'b10: begin OUT = TWO; end
            default: begin OUT = 32'b0; end
        endcase
    end

endmodule
