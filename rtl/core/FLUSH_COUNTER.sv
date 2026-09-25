`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/31/2025 10:37:00 AM
// Design Name: 
// Module Name: FLUSH_COUNTER
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module FLUSH_COUNTER(
    input  logic clk,
    input  logic FLUSH, // Connected directly to flush
    input  logic reset, // connect to BTN
    output logic FLUSH_OUT          // Output filtered for 2 flush 
);
logic [1:0] zero_counter;

always_ff @(posedge clk) begin
        if (!reset) begin
            zero_counter <= 0;
            FLUSH_OUT    <= 0;
        end 
        else if (FLUSH) begin
            zero_counter <= 1;  // hold for 2 cycles
        end 
        else if (zero_counter != 0) begin
            zero_counter <= zero_counter - 1;
        end

        if (zero_counter != 0) begin
            FLUSH_OUT <= 1;
        end 
	    else begin
	        FLUSH_OUT <= 0;
        end 	
    end
endmodule