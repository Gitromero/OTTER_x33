`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: HD
// Description: Hazard detection unit for the 5-stage OTTER.
//              - Forwarding selects for the EX operands
//                  0 = register file value, 1 = MEM stage result, 2 = WB data
//              - STALL: load-use hazard (load in EX, dependent instr in ID).
//                Holds PC and IF/ID one cycle and inserts a bubble into EX.
//              - FLUSH: taken branch/jump in EX; squash the two younger
//                instructions (in IF and ID).
//////////////////////////////////////////////////////////////////////////////////
module HD(
    input logic ID_valid,
    input logic [4:0] ID_rs1,
    input logic [4:0] ID_rs2,
    input logic ID_rs1_used,
    input logic ID_rs2_used,
    input logic [4:0] EX_rs1,
    input logic [4:0] EX_rs2,
    input logic EX_rs1_used,
    input logic EX_rs2_used,
    input logic [4:0] EX_rd,
    input logic EX_memRead2,
    input logic [4:0] MEM_rd,
    input logic MEM_REGWE,
    input logic [4:0] WB_rd,
    input logic WB_REGWE,
    input logic [2:0] PC_src,
    output logic [1:0] fsel1,
    output logic [1:0] fsel2,
    output logic STALL,
    output logic FLUSH
    );

    // Forwarding: the youngest producer (MEM) wins over the older one (WB).
    // *_used is only set for rs != x0, so x0 is never forwarded.
    always_comb begin
        fsel1 = 2'b00;
        if (EX_rs1_used && MEM_REGWE && MEM_rd == EX_rs1)
            fsel1 = 2'b01;
        else if (EX_rs1_used && WB_REGWE && WB_rd == EX_rs1)
            fsel1 = 2'b10;

        fsel2 = 2'b00;
        if (EX_rs2_used && MEM_REGWE && MEM_rd == EX_rs2)
            fsel2 = 2'b01;
        else if (EX_rs2_used && WB_REGWE && WB_rd == EX_rs2)
            fsel2 = 2'b10;
    end

    // Load data is only available in WB, so a dependent instruction right
    // behind a load waits one cycle and then gets it through fsel = 2.
    assign STALL = ID_valid && EX_memRead2 && EX_rd != 5'd0
                && ((ID_rs1_used && ID_rs1 == EX_rd)
                 || (ID_rs2_used && ID_rs2 == EX_rd));

    assign FLUSH = PC_src != 3'b000;

endmodule
