`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: California Polytechnic University, San Luis Obispo
// Engineer: Diego Renato Curiel
// Create Date: 02/23/2023 09:39:49 AM
// Module Name: CU_DCDR
//////////////////////////////////////////////////////////////////////////////////

module CU_DCDR(
    input logic IR_30,
    input logic [6:0] IR_OPCODE,
    input logic [2:0] IR_FUNCT,
    input logic BR_EQ,
    input logic BR_LT,
    input logic BR_LTU,
    output logic [3:0] ALU_FUN,
    output logic ALU_SRCA,
    output logic [1:0] ALU_SRCB,
    output logic [2:0] PC_SOURCE,

    output logic REG_WRITE,
    output logic MEM_WE2,
    output logic MEM_RDEN2,
    
    output logic [1:0] RF_WR_SEL
    );
    
    //Create always comb clock for decoder logic
    always_comb begin
        //Instantiate all outputs to 0 so as to avoid
        //unwanted leftovers from previous operations
        //and maintain direct control of outputs through
        //case statement below
        ALU_FUN = 4'b0000;
        ALU_SRCA = 1'b0;
        ALU_SRCB = 2'b00;
        PC_SOURCE = 3'b000;
        RF_WR_SEL = 2'b00;
        
        REG_WRITE = 1'b0;
        MEM_WE2 = 1'b0;
        MEM_RDEN2 = 1'b0;
        //Case statement depending on the opcode for the 
        //instruction, or the last seven bits of each instruction
        case (IR_OPCODE)
            7'b0010111: begin // AUIPC
                ALU_SRCA = 1'b1;
                ALU_SRCB = 2'b11;
                RF_WR_SEL = 2'b11;
                REG_WRITE = 1'b1;
            end
            7'b1101111: begin // JAL
                PC_SOURCE = 3'b011;
                REG_WRITE = 1'b1;
            end
            7'b1100111: begin // JALR
                PC_SOURCE = 3'b001;
                REG_WRITE = 1'b1;
            end
            7'b0100011: begin // Store Instructions
                ALU_SRCB = 2'b10;
                //REG_WRITE = 1'b1;
                        MEM_WE2 = 1'b1;
            end
            7'b0000011: begin // Load Instructions
                ALU_SRCB = 2'b01;
                RF_WR_SEL = 2'b10;
                        MEM_RDEN2 = 1'b1;
                        REG_WRITE = 1'b0;
            end
            7'b0110111: begin // LUI
                ALU_FUN = 4'b1001;
                ALU_SRCA = 1'b1;
                RF_WR_SEL = 2'b11;
                REG_WRITE = 1'b1;
            end
            7'b0010011: begin // I-Type
                //set constants for all I-type instructions
                ALU_SRCB = 2'b01;
                RF_WR_SEL = 2'b11;
                REG_WRITE = 1'b1;
                
                //Nested case statement
                //dependent on the function 3 bits
                case (IR_FUNCT)
                    3'b000: begin ALU_FUN = 4'b0000; end
                    3'b001: begin ALU_FUN = 4'b0001; end
                    3'b010: begin ALU_FUN = 4'b0010; end
                    3'b011: begin ALU_FUN = 4'b0011; end
                    3'b100: begin ALU_FUN = 4'b0100; end
                    3'b101: begin
                        //nested case statement
                        //dependent on the 30th bit for 
                        //instructions that have the same opcode and 
                        //fucntion 3 bits
                        case(IR_30)
                            1'b0: begin ALU_FUN = 4'b0101; end
                            1'b1: begin ALU_FUN = 4'b1101; end
                            default: begin end
                        endcase
                    end
                    3'b110: begin ALU_FUN = 4'b0110; end
                    3'b111: begin ALU_FUN = 4'b0111; end
                endcase
            end
            7'b0110011: begin // R-Type
                //set constants for all R-types;
                //ALU_FUN is just the concatenation of
                //the 30th bit and the function 3 bits
                RF_WR_SEL = 2'b11;
                REG_WRITE = 1'b1;
                ALU_FUN = {IR_30, IR_FUNCT};
            end
            7'b1100011: begin // B-Type
            REG_WRITE = 1'b1;
                //nested case statement dependent on the
                //function three bits.
                //Because there are six real branch instructions, there
                //are six pairs of if-else statements in each of six cases
                //for the branch instructions.
                case(IR_FUNCT)
                    3'b000: begin
                        if (BR_EQ == 1'b1)
                            PC_SOURCE = 3'b010;
                        else
                            PC_SOURCE = 3'b000; 
                    end
                    3'b001: begin 
                        if (BR_EQ == 1'b0)
                            PC_SOURCE = 3'b010;
                        else
                            PC_SOURCE = 3'b000; 
                    end
                    3'b100: begin 
                        if (BR_LT == 1'b1)
                            PC_SOURCE = 3'b010;
                        else
                            PC_SOURCE = 3'b000;
                    end
                    3'b101: begin 
                        if (BR_LT == 1'b0)
                            PC_SOURCE = 3'b010;
                        else
                            PC_SOURCE = 3'b000;
                    end
                    3'b110: begin 
                        if (BR_LTU == 1'b1)
                            PC_SOURCE = 3'b010;
                        else
                            PC_SOURCE = 3'b000;
                    end
                    3'b111: begin 
                        if (BR_LTU == 1'b0)
                            PC_SOURCE = 3'b010;
                        else
                            PC_SOURCE = 3'b000;
                    end
                endcase
            end
            default: begin end
        endcase
    end
    
endmodule
