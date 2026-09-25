`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: otter_pkg
// Description: Shared types for the pipelined OTTER: opcodes and the per-stage
//              instruction record carried through the pipeline registers.
//////////////////////////////////////////////////////////////////////////////////
package otter_pkg;

    typedef enum logic [6:0] {
        LUI      = 7'b0110111,
        AUIPC    = 7'b0010111,
        JAL      = 7'b1101111,
        JALR     = 7'b1100111,
        BRANCH   = 7'b1100011,
        LOAD     = 7'b0000011,
        STORE    = 7'b0100011,
        OP_IMM   = 7'b0010011,
        OP       = 7'b0110011,
        SYSTEM   = 7'b1110011
    } opcode_t;

    typedef struct packed {
        logic        valid;      // 0 = bubble / flushed instruction
        opcode_t     opcode;
        logic [2:0]  funct3;     // branch type, or {sign, size} for loads/stores
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;
        logic [4:0]  rd_addr;
        logic        rs1_used;
        logic        rs2_used;
        logic [3:0]  alu_fun;
        logic        alu_src_a;
        logic [1:0]  alu_src_b;
        logic        reg_wr;
        logic        mem_we2;
        logic        mem_rden2;
        logic [1:0]  rf_wr_sel;
        logic [31:0] pc;
        logic [31:0] i_imm;
        logic [31:0] s_imm;
        logic [31:0] b_imm;
        logic [31:0] u_imm;
        logic [31:0] j_imm;
        logic [31:0] rs1;        // register values (forwarded values after EX)
        logic [31:0] rs2;
        logic [31:0] alu_result;
    } instr_t;

endpackage
