`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: Diego
// Create Date: 07/21/2025 09:19:50 PM
// Design Name:
// Module Name: OTTER
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 5-stage pipelined RV32I OTTER (IF, ID, EX, MEM, WB)
//              - forwarding from MEM and WB into EX (HD)
//              - 1-cycle stall on load-use hazards (HD)
//              - branches/jumps resolved in EX; a taken one flushes IF and ID
//
// Dependencies: otter_pkg
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Rewired pipeline registers, added hazard unit and flushing
// Additional Comments:
//   Memory reads are synchronous, so the memory's MEM_DOUT1 output register
//   acts as the IF/ID instruction register, and MEM_DOUT2 is valid in WB.
//////////////////////////////////////////////////////////////////////////////////
import otter_pkg::*;

module OTTER(
    input logic RST,
    input logic [31:0] IOBUS_IN,
    input logic CLK,
    output logic IOBUS_WR,
    output logic [31:0] IOBUS_OUT,
    output logic [31:0] IOBUS_ADDR
    );

    instr_t ID_inst, ALU_inst, MEM_inst, WB_inst;

    logic STALL, FLUSH;
    logic [2:0] pc_source;
    logic [31:0] pc_out, pc_out_inc, jalr, branch, jal;
    logic [31:0] ir, dout2, wd;

//==== Fetch =================================================================================================================
PC OTTER_PC(
        .CLK(CLK),
        .RST(RST),
        .PC_WRITE(!STALL),
        .PC_SOURCE(pc_source),
        .JALR(jalr),
        .JAL(jal),
        .BRANCH(branch),
        .MTVEC(32'b0),
        .MEPC(32'b0),
        .PC_OUT(pc_out),
        .PC_OUT_INC(pc_out_inc));

    // IF/ID register (the instruction itself is registered inside Memory)
    logic [31:0] if_id_pc;
    logic if_id_valid;
    always_ff @(posedge CLK) begin
        if (RST || FLUSH)
            if_id_valid <= 1'b0;     // instruction being fetched is wrong-path
        else if (!STALL)
            if_id_valid <= 1'b1;
        if (!STALL)
            if_id_pc <= pc_out;
    end

// Memory Module
Memory OTTER_MEMORY (
        .MEM_CLK   (CLK),
        .MEM_RDEN1 (!STALL),                  // IF: hold instruction on stall
        .MEM_RDEN2 (MEM_inst.mem_rden2),      // MEM
        .MEM_WE2   (MEM_inst.mem_we2),        // MEM
        .MEM_ADDR1 (pc_out[15:2]),            // IF
        .MEM_ADDR2 (MEM_inst.alu_result),     // MEM
        .MEM_DIN2  (MEM_inst.rs2),            // MEM: forwarded store data
        .MEM_SIZE  (MEM_inst.funct3[1:0]),
        .MEM_SIGN  (MEM_inst.funct3[2]),
        .IO_IN     (IOBUS_IN),
        .IO_WR     (IOBUS_WR),
        .MEM_DOUT1 (ir),                      // ID
        .MEM_DOUT2 (dout2)                    // WB
        );

//==== Decode ================================================================================================================
    logic [31:0] rs1, rs2;

    assign ID_inst.valid     = if_id_valid;
    assign ID_inst.opcode    = opcode_t'(ir[6:0]);
    assign ID_inst.funct3    = ir[14:12];
    assign ID_inst.rs1_addr  = ir[19:15];
    assign ID_inst.rs2_addr  = ir[24:20];
    assign ID_inst.rd_addr   = ir[11:7];
    assign ID_inst.pc        = if_id_pc;
    assign ID_inst.rs1       = rs1;
    assign ID_inst.rs2       = rs2;
    assign ID_inst.alu_result = 32'b0;

    assign ID_inst.rs1_used =   ID_inst.rs1_addr != 0
                             && ID_inst.opcode != LUI
                             && ID_inst.opcode != AUIPC
                             && ID_inst.opcode != JAL;

    assign ID_inst.rs2_used =   ID_inst.rs2_addr != 0
                             && ID_inst.opcode != LUI
                             && ID_inst.opcode != AUIPC
                             && ID_inst.opcode != JAL
                             && ID_inst.opcode != LOAD
                             && ID_inst.opcode != OP_IMM
                             && ID_inst.opcode != JALR;

//Instantiate Decoder (branch conditions are evaluated in EX, so BR_* = 0)
CU_DCDR OTTER_DCDR(
        .IR_30(ir[30]),
        .IR_OPCODE(ir[6:0]),
        .IR_FUNCT(ir[14:12]),
        .BR_EQ(1'b0),
        .BR_LT(1'b0),
        .BR_LTU(1'b0),
        .ALU_FUN(ID_inst.alu_fun),
        .ALU_SRCA(ID_inst.alu_src_a),
        .ALU_SRCB(ID_inst.alu_src_b),
        .PC_SOURCE(),
        .RF_WR_SEL(ID_inst.rf_wr_sel),
        .REG_WRITE(ID_inst.reg_wr),
        .MEM_WE2(ID_inst.mem_we2),
        .MEM_RDEN2(ID_inst.mem_rden2)
        );

//Immediate Generator
ImmediateGenerator OTTER_IMGEN(
        .IR(ir[31:7]),
        .U_TYPE(ID_inst.u_imm),
        .I_TYPE(ID_inst.i_imm),
        .S_TYPE(ID_inst.s_imm),
        .B_TYPE(ID_inst.b_imm),
        .J_TYPE(ID_inst.j_imm));

//RegFile: read in ID, written in WB (on the falling edge, so ID sees WB's write)
REG_FILE OTTER_REG_FILE(
        .CLK(CLK),
        .EN(WB_inst.reg_wr),
        .ADR1(ID_inst.rs1_addr),
        .ADR2(ID_inst.rs2_addr),
        .WA(WB_inst.rd_addr),
        .WD(wd),
        .RS1(rs1),
        .RS2(rs2));

//Hazard Detection Unit
    logic [1:0] fsel1, fsel2;
HD OTTER_HD(
        .ID_valid(ID_inst.valid),
        .ID_rs1(ID_inst.rs1_addr),
        .ID_rs2(ID_inst.rs2_addr),
        .ID_rs1_used(ID_inst.rs1_used),
        .ID_rs2_used(ID_inst.rs2_used),
        .EX_rs1(ALU_inst.rs1_addr),
        .EX_rs2(ALU_inst.rs2_addr),
        .EX_rs1_used(ALU_inst.rs1_used),
        .EX_rs2_used(ALU_inst.rs2_used),
        .EX_rd(ALU_inst.rd_addr),
        .EX_memRead2(ALU_inst.mem_rden2),
        .MEM_rd(MEM_inst.rd_addr),
        .MEM_REGWE(MEM_inst.reg_wr),
        .WB_rd(WB_inst.rd_addr),
        .WB_REGWE(WB_inst.reg_wr),
        .PC_src(pc_source),
        .fsel1(fsel1),
        .fsel2(fsel2),
        .STALL(STALL),
        .FLUSH(FLUSH)
        );

    // ID/EX register: insert a bubble on stall, flush, or invalid instruction
    always_ff @(posedge CLK) begin
        if (RST || FLUSH || STALL || !ID_inst.valid)
            ALU_inst <= '0;
        else
            ALU_inst <= ID_inst;
    end

//==== Execute =================================================================================================================
    logic [31:0] F_MUX_A_OUT, F_MUX_B_OUT, mem_fwd, srcA, srcB, alu_result;
    logic br_eq, br_lt, br_ltu;

    // value the MEM-stage instruction will write back (loads stall instead)
    assign mem_fwd = (MEM_inst.rf_wr_sel == 2'b00) ? MEM_inst.pc + 4 : MEM_inst.alu_result;

//Forwarding Muxes
ThreeMux F_OTTER_A(
        .SEL(fsel1),
        .ZERO(ALU_inst.rs1),
        .ONE(mem_fwd),
        .TWO(wd),
        .OUT(F_MUX_A_OUT)
        );

ThreeMux F_OTTER_B(
        .SEL(fsel2),
        .ZERO(ALU_inst.rs2),
        .ONE(mem_fwd),
        .TWO(wd),
        .OUT(F_MUX_B_OUT)
        );

// muxA to ALU
TwoMux OTTER_ALU_MUXA(
        .ALU_SRC_A(ALU_inst.alu_src_a),
        .RS1(F_MUX_A_OUT),
        .U_TYPE(ALU_inst.u_imm),
        .SRC_A(srcA));

// muxB to ALU
FourMux OTTER_ALU_MUXB(
        .SEL(ALU_inst.alu_src_b),
        .ZERO(F_MUX_B_OUT),
        .ONE(ALU_inst.i_imm),
        .TWO(ALU_inst.s_imm),
        .THREE(ALU_inst.pc),
        .OUT(srcB));

ALU OTTER_ALU(
        .SRC_A(srcA),
        .SRC_B(srcB),
        .ALU_FUN(ALU_inst.alu_fun),
        .RESULT(alu_result));

//Branch Condition Generator
BCG OTTER_BCG(
        .RS1(F_MUX_A_OUT),
        .RS2(F_MUX_B_OUT),
        .BR_EQ(br_eq),
        .BR_LT(br_lt),
        .BR_LTU(br_ltu));

//Branch Address Generator
BAG OTTER_BAG(
        .RS1(F_MUX_A_OUT),
        .I_TYPE(ALU_inst.i_imm),
        .J_TYPE(ALU_inst.j_imm),
        .B_TYPE(ALU_inst.b_imm),
        .FROM_PC(ALU_inst.pc),
        .JAL(jal),
        .JALR(jalr),
        .BRANCH(branch));

    // Branch/jump resolution (bubbles have opcode 0, so they never redirect)
    always_comb begin
        pc_source = 3'b000;
        case (ALU_inst.opcode)
            JAL:    pc_source = 3'b011;
            JALR:   pc_source = 3'b001;
            BRANCH: begin
                case (ALU_inst.funct3)
                    3'b000: if (br_eq)   pc_source = 3'b010;  // beq
                    3'b001: if (!br_eq)  pc_source = 3'b010;  // bne
                    3'b100: if (br_lt)   pc_source = 3'b010;  // blt
                    3'b101: if (!br_lt)  pc_source = 3'b010;  // bge
                    3'b110: if (br_ltu)  pc_source = 3'b010;  // bltu
                    3'b111: if (!br_ltu) pc_source = 3'b010;  // bgeu
                    default: ;
                endcase
            end
            default: ;
        endcase
    end

    // EX/MEM register
    always_ff @(posedge CLK) begin
        if (RST)
            MEM_inst <= '0;
        else begin
            MEM_inst            <= ALU_inst;
            MEM_inst.rs1        <= F_MUX_A_OUT;
            MEM_inst.rs2        <= F_MUX_B_OUT;
            MEM_inst.alu_result <= alu_result;
        end
    end

//==== Memory =================================================================================================================
    assign IOBUS_ADDR = MEM_inst.alu_result;
    assign IOBUS_OUT  = MEM_inst.rs2;

    // MEM/WB register
    always_ff @(posedge CLK) begin
        if (RST)
            WB_inst <= '0;
        else
            WB_inst <= MEM_inst;
    end

//==== WriteBack =================================================================================================================
FourMux OTTER_REG_MUX(
        .SEL(WB_inst.rf_wr_sel),
        .ZERO(WB_inst.pc + 4),
        .ONE(32'b0),
        .TWO(dout2),
        .THREE(WB_inst.alu_result),
        .OUT(wd));

endmodule
