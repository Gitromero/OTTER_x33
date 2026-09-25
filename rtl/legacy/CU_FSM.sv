`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: California Polytechnic University, San Luis Obispo
// Engineer: Diego Renato Curiel
// Create Date: 02/23/2023 09:39:49 AM
// Module Name: CU_FSM
//////////////////////////////////////////////////////////////////////////////////

module CU_FSM(
    input logic CLK,
    input logic RST,
    input logic [6:0] IR_OPCODE,
    output logic PC_WRITE,
    output logic REG_WRITE,
    output logic MEM_WE2,
    output logic MEM_RDEN1,
    output logic MEM_RDEN2,
    output logic rst
    );
    
    //Create labels for each state using enumeration, along with state variable
    typedef enum {INIT, FETCH, EXEC, WRITE_BACK} state;
    
    //create state variables
    state NS, PS;
    
    //Create state register
    always_ff@(posedge CLK) begin
        if (RST == 1'b1)
            PS <= INIT;
        else
            PS <= NS;
    end
    
    //Create input logic for each state.
    always_comb begin
        //initialize all outputs to zero, always, only 
        //to be changed within case statement for Present State
        PC_WRITE = 1'b0;
        REG_WRITE = 1'b0;
        MEM_WE2 = 1'b0;
        MEM_RDEN1 = 1'b0;
        MEM_RDEN2 = 1'b0;
        rst = 1'b0;
        
        //Present State case statement
        case(PS)
            //Initial state, set PC reset to 1 so that first address
            //is output, and make next state Fetch
            INIT: begin 
                NS = FETCH;
                rst = 1'b1;
            end
            
            //Fetch state, set Memory read enable one to high
            //so that the instruction is output at the address 
            //given by the PC
            FETCH: begin 
                NS = EXEC;
                MEM_RDEN1 = 1'b1;
            end
            
            //Execute state: employ case statements to set all read/write outputs
            EXEC: begin
                NS = FETCH;
                case (IR_OPCODE)
                    7'b0010111: begin // AUIPC
                        PC_WRITE = 1'b1;
                        REG_WRITE = 1'b1;
                    end
                    7'b1101111: begin // JAL
                        PC_WRITE = 1'b1;
                        REG_WRITE = 1'b1;
                    end
                    7'b1100111: begin // JALR
                        PC_WRITE = 1'b1;
                        REG_WRITE = 1'b1;
                    end
                    7'b0100011: begin // Store Instructions
                        PC_WRITE = 1'b1;
                        MEM_WE2 = 1'b1;
                    end
                    7'b0000011: begin // Load Instructions
                        //For load instructions, make next state
                        //Write Back; in order to prevent the wrong
                        //data from showing up at DOUT2, set PCwrite and
                        //regWrite low while setting Mem Read enable 2 high
                        NS = WRITE_BACK;
                        MEM_RDEN2 = 1'b1;
                        PC_WRITE = 1'b0;
                        REG_WRITE = 1'b0;
                    end
                    7'b0110111: begin // LUI
                        PC_WRITE = 1'b1;
                        REG_WRITE = 1'b1;
                    end
                    7'b0010011: begin // I-type
                        PC_WRITE = 1'b1;
                        REG_WRITE = 1'b1;
                    end
                    7'b0110011: begin // R-type
                        PC_WRITE = 1'b1;
                        REG_WRITE = 1'b1;
                    end
                    7'b1100011: begin // B-type
                        PC_WRITE = 1'b1;
                    end
                    default: begin end
                endcase
            end
            
            //Write back state, set next state to Fetch
            //set pcWrite and RegWrite to high so that the
            //program advances and writes the correct data to the 
            //reg file
            WRITE_BACK: begin
                NS = FETCH;
                PC_WRITE = 1'b1;
                REG_WRITE = 1'b1;
            end
            
            default: begin
                NS = INIT;
            end
        endcase
    end
    
endmodule
