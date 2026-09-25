`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/09/2025 11:10:53 PM
// Design Name: 
// Module Name: HD
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

module HD(  

    input logic [6:0] opcode,
    input logic [4:0] ID_rs1,
    input logic [4:0] ID_rs2,

    input logic [4:0] EX_rs1,
    input logic [4:0] EX_rs2,

    input logic [4:0] EX_rd,
    input logic [4:0] MEM_rd,
    input logic [4:0] WB_rd,

    input logic [2:0] PC_src,

    input logic MEM_REGWE,
    input logic WB_REGWE,
    input logic ALU_memRead2,


    output logic [1:0] fsel1,
    output logic [1:0] fsel2,

    output logic STALL,
    output logic FLUSH
    );

    always_comb begin
        fsel1 = 2'b00;
        fsel2 = 2'b00;

        STALL = 1'b0;
        FLUSH = 1'b0;
//maybe do id and change the logix

//RS1 forwarding MUX
        if (MEM_rd == EX_rs1 && (MEM_rd != 0) && MEM_REGWE) begin	// mem.inst ALU_result EDIT: Changing MEM_rd => EX_rd EDIT2: CHANGING BACK TO MEM
            fsel1 = 2'b01; 						// ALU foaward case
        end
        else if (WB_rd == EX_rs1 && (WB_rd != 0) && WB_REGWE) begin	// mem_dout2 wired 
            fsel1 = 2'b10; 						//  MEM foward case
        end
        else begin
            fsel1 = 2'b00; 						// deafault where rs1 is not foward
        end
        
//RS2 Fowarding MUX        
        if (MEM_rd == EX_rs2 && (MEM_rd != 0) && MEM_REGWE)begin 	// mem.inst ALU_result EDIT: Changing MEM_rd => EX_rd
		fsel2 = 2'b01;						 // ALU foaward case
	end
        else if (WB_rd == EX_rs2 && (WB_rd != 0) && WB_REGWE) begin	// mem_dout2 wired 
		fsel2 = 2'b10; 						//  MEM foward case
	end
        else begin
		fsel2 = 2'b00; 						// deafault where rs1 is not foward
	end

// Load-use data hazard
        if ((opcode == 7'b0000011) && ((ID_rs1 == EX_rd) || (ID_rs2 == EX_rd))) begin
            STALL = 1'b1;
        end
        else begin
            STALL = 1'b0;
        end
        
// Branch Control Hazard
        if (PC_src != 3'b000) begin
            FLUSH = 1'b1;
        end
        else begin
            FLUSH = 1'b0;
        end
    end

endmodule
