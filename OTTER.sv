`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Diego 
// Create Date: 07/21/2025 09:19:50 PM
// Design Name: 
// Module Name: OTTER_P
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
 
typedef struct packed{
    opcode_t opcode;
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;
    logic rs1_used;
    logic rs2_used;
    logic rd_used;
    logic [3:0] alu_fun;
    logic alu_src_a;
    logic [1:0] alu_src_b;
    logic [31:0] alu_result;
    logic [31:0] rs2;

    logic mem_we2;
    logic mem_rden2;
    logic reg_wr;
    logic [1:0] rf_wr_sel;
    logic [2:0] mem_type;  //sign, size
    logic [31:0] pc;
     logic [2:0] pc_source;
} instr_t;

module OTTER(
    input logic RST,
    input logic [31:0] IOBUS_IN,
    input logic CLK,
    output logic IOBUS_WR,
    output logic [31:0] IOBUS_OUT,
    output logic [31:0] IOBUS_ADDR
    );
 //instr made   
    instr_t ID_inst, ALU_inst, MEM_inst, WB_inst;
    

//==== Fetch =================================================================================================================
//Create logic for PC; connecting wires to Memory module and RegFile Mux
    	logic pc_rst, pc_write, FLUSH, STALL, FC_FLUSH;
    	logic [2:0] pc_source;
    	logic [31:0] pc_out, pc_out_inc, jalr, branch, jal;
        assign pc_write = !FLUSH; 	

        //assign pc_rst = 1;
// data clash        
        logic mem_rden1;
        assign mem_rden1 = 1;
        logic [31:0] dout2, ir, rs1, wd;//, id_pc;
        
     
PC OTTER_PC(
        .CLK(CLK), 
       .RST(RST), 
       .PC_WRITE(pc_write), 
       .PC_SOURCE(pc_source),
       .JALR(jalr), 
       .JAL(jal), 
       .BRANCH(branch), 
       .MTVEC(32'b0), 
       .MEPC(32'b0), 
       .PC_OUT(pc_out), 
       .PC_OUT_INC(pc_out_inc));
       
       logic [31:0] memdin2;
       
        always_comb begin
            if(MEM_inst.opcode == STORE)begin
                memdin2 = wd;
            end
            else begin
                memdin2 = MEM_inst.rs2;
            end
        end
	assign IOBUS_ADDR = MEM_inst.alu_result;
// Memory Module   
Memory OTTER_MEMORY (
        .MEM_CLK   (CLK),
        .MEM_RDEN1 (mem_rden1),              // IF input
        .MEM_RDEN2 (MEM_inst.mem_rden2),   // WB
        .MEM_WE2   (MEM_inst.mem_we2),   // WB
        .MEM_ADDR1 (pc_out[15:2]),          // IF input
        .MEM_ADDR2 (MEM_inst.alu_result),        // WB input
        .MEM_DIN2  (memdin2),         // rs2 here is a problem currently
        .MEM_SIZE  (MEM_inst.mem_type[1:0]),         // IR[13:12] 
        .MEM_SIGN  (MEM_inst.mem_type[2]),            // input 
        .IO_IN     (IOBUS_IN),          // OUTPUT
        .IO_WR     (IOBUS_WR),          // OUTPUT
        .MEM_DOUT1 (ir),                // ouput usd for decode
        .MEM_DOUT2 (dout2)           // to regfile mux in WB
        );
        logic [24:0] imgen_ir;
        assign imgen_ir = ir[31:7];
                        
        logic ir30;
        assign ir30 = ir[30];

        logic [6:0] opcode;
       
//==== Decode ================================================================================================================
//assigned all values in decode for neatness :)
//pontential data reduncancy
//alu data
    	logic alu_src_a;
    	logic [1:0] alu_src_b;
        //logic [3:0] alu_fun; => direct connection to struct
	    logic [31:0] srcA, srcB;
  
//branch cond
    	logic br_eq, br_lt, br_ltu;    
    	//mem


//memery assign
        assign opcode = ir[6:0];

        logic [2:0] funct;
        assign funct = ir[14:12];  
        assign ID_inst.rs1_addr = ir[19:15];
        assign ID_inst.rs2_addr = ir[24:20];
        assign  ID_inst.rd_addr  = ir[11:7];

        assign ID_inst.mem_type[1:0] = ir[13:12];
        assign ID_inst.mem_type[2] = ir[14];
        assign ID_inst.rs2 = IOBUS_OUT; // okay saved too early and doesn't get catched if comp moves too quickly
        
    	//logic mem_rden2, mem_we2; => direct connection to struct
    	assign ID_inst.opcode = opcode_t'(ir[6:0]);
        assign ID_inst.pc = pc_out; //id_pc;        
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
                                
     	assign ID_inst.rd_used =  ID_inst.rd_addr != 0
                                && ID_inst.opcode != BRANCH
                                && ID_inst.opcode != STORE;
                                
//regFile BEGIN======================================================
FourMux OTTER_REG_MUX(
                .SEL(WB_inst.rf_wr_sel), 
                .ZERO(WB_inst.pc + 4), 
                .ONE(32'b0), 
                .TWO(dout2), 
                .THREE(WB_inst.alu_result),
                .OUT(wd));
				

    //Instantiate RegFile, connect all relevant I/O    
REG_FILE OTTER_REG_FILE(
                .CLK(CLK), 
                .EN(WB_inst.reg_wr), 
                .ADR1(ID_inst.rs1_addr), 
                .ADR2(ID_inst.rs2_addr),  
                .WA(WB_inst.rd_addr), 
                .WD(wd), 
                .RS1(rs1), 
                .RS2(IOBUS_OUT)); 
 //regFile END======================================================
                    
          
         
         //200 ns in instantlyy grabbed
//Instantiate Decoder, connect all relevant I/O               
CU_DCDR OTTER_DCDR(
		 .IR_30(ir30), 
		 .IR_OPCODE(opcode), 
		 .IR_FUNCT(funct), 
		 .BR_EQ(br_eq), 
		 .BR_LT(br_lt),
         .BR_LTU(br_ltu), 
		 .ALU_FUN(ID_inst.alu_fun), 
		 .ALU_SRCA(ID_inst.alu_src_a), 
		 .ALU_SRCB(ID_inst.alu_src_b), 
		 .PC_SOURCE(pc_source),
         .RF_WR_SEL(ID_inst.rf_wr_sel),
         .REG_WRITE(ID_inst.reg_wr), 
         .MEM_WE2(ID_inst.mem_we2), 
         .MEM_RDEN2(ID_inst.mem_rden2)
         ); 
//================ stall sel ??
         logic [1:0] fsel1, fsel2, s_fsel1, s_fsel2;
//Hazard Detection Unit
HD OTTER_HD(
        .opcode(ALU_inst.opcode),
        .ID_rs1(ID_inst.rs1_addr),
        .ID_rs2(ID_inst.rs2_addr),
        .EX_rs1(ALU_inst.rs1_addr),
        .EX_rs2(ALU_inst.rs2_addr),
        .EX_rd(ALU_inst.rd_addr),
        .MEM_rd(MEM_inst.rd_addr),
        .WB_rd(WB_inst.rd_addr),
        .PC_src(pc_source),
        .MEM_REGWE(MEM_inst.reg_wr),
        .WB_REGWE(WB_inst.reg_wr),
        .ALU_memRead2(ALU_inst.mem_rden2),
        .fsel1(fsel1),
        .fsel2(fsel2),
        .STALL(STALL),
        .FLUSH(FLUSH)
        );
//Flush COunter
FLUSH_COUNTER OTTER_FC(
        .clk(CLK),
        .FLUSH(FLUSH),
        .reset(RST),
        .FLUSH_OUT(FC_FLUSH)
        );
//Create logic for Immediate Generator outputs and BAG and ALU MUX inputs    
            logic [31:0] Utype, Itype, Stype, Btype, d_Jtype, d_Utype, d_Itype, d_Stype, d_Btype;
    
//Immediate Generator, connect all relevant I/O
ImmediateGenerator OTTER_IMGEN(
            .IR(imgen_ir),  
            .U_TYPE(Utype), 
            .I_TYPE(Itype), 
            .S_TYPE(Stype),
            .B_TYPE(Btype), 
            .J_TYPE(Jtype));
            

//==== ALU =================================================================================================================
     logic [31:0]F_MUX_A_OUT, F_MUX_B_OUT, d_rs1, d_rs2;
     always_ff @(posedge CLK) begin
        //d_rs1 <= rs1;
        //d_rs2 <= IOBUS_OUT;
        //s_fsel1 <= fsel1;
        //s_fsel2 <= fsel2;
		d_rs1 <= rs1;
		d_rs2 <= IOBUS_OUT;
		d_Utype <= Utype;
		d_Itype <= Itype;
		d_Stype <= Stype;
		d_Btype <= Btype;
		d_Jtype <= Jtype;
		
     //order doesnt matter
        if(FC_FLUSH) begin
            ALU_inst.reg_wr <= 0;
            ALU_inst.mem_we2 <= 0;            
        end
        ALU_inst <= ID_inst;
        MEM_inst <= ALU_inst;
       
        ALU_inst.pc_source = pc_source; //issac
     end
     

//Fowarding Muxes attempting to sync with alu properly
ThreeMux F_OTTER_A(
        .SEL(fsel1),
        .ZERO(d_rs1), //gotta get delayed too
        .ONE(ALU_inst.alu_result),// ALU <= MEM (NEEDS TO BE DELAYED)
        .TWO(dout2),
        .OUT(F_MUX_A_OUT)
        );
            
ThreeMux F_OTTER_B(
        .SEL(fsel2),
        .ZERO(d_rs2), //gotta be delayed
        .ONE(ALU_inst.alu_result),//try alu
        .TWO(dout2),
        .OUT(F_MUX_B_OUT)
        );

//ADDED LOGIC HERE FOR ALU REGISTER SAVING 
                       
// muxA to ALU
TwoMux OTTER_ALU_MUXA(
        .ALU_SRC_A(ALU_inst.alu_src_a),
        .RS1(F_MUX_A_OUT), 
        .U_TYPE(Utype), 
        .SRC_A(srcA));
    
// muxB to ALU
FourMux OTTER_ALU_MUXB(
        .SEL(ALU_inst.alu_src_b), 
        .ZERO(F_MUX_B_OUT), 
        .ONE(d_Itype), 
        .TWO(d_Stype), 
        .THREE(ALU_inst.pc), 
        .OUT(srcB));   
            
//literal alu
//here me out, we change this
ALU OTTER_ALU(
        .SRC_A(srcA),
        .SRC_B(srcB),
        .ALU_FUN(ALU_inst.alu_fun),//=testing alu => id
        .RESULT(ALU_inst.alu_result));
        
//Instantiate Branch Condition Generator, connect all 
//relevant I/O
 BCG OTTER_BCG(
	    	.RS1(F_MUX_A_OUT), 
		.RS2(F_MUX_B_OUT), 
		.BR_EQ(br_eq), 
		.BR_LT(br_lt), 
		.BR_LTU(br_ltu));      
		
    //Instantiate Branch Address Generator, connect all relevant I/O    
BAG OTTER_BAG(
         .RS1(F_MUX_A_OUT), //delayed 
         .I_TYPE(d_Itype), 
         .J_TYPE(d_Jtype), 
         .B_TYPE(d_Btype), 
         .FROM_PC(ALU_inst.pc),
         .JAL(jal), 
         .JALR(jalr), 
         .BRANCH(branch));
         
   


//==== Memory =================================================================================================================
//wired in IF
     assign MEM_inst.alu_result= IOBUS_ADDR;
     always_ff @(posedge CLK) begin
        WB_inst <= MEM_inst;
     end
//==== WriteBack =================================================================================================================
//FourMux OTTER_REG_MUX(
//                .SEL(WB_inst.rf_wr_sel), 
//                .ZERO(WB_inst.pc + 4), 
//                .ONE(32'b0), 
//                .TWO(dout2), 
//                .THREE(WB_inst.alu_result),
//                .OUT(wd));

//    //Instantiate RegFile, connect all relevant I/O    
//REG_FILE OTTER_REG_FILE(
//                .CLK(CLK), 
//                .EN(WB_inst.reg_wr), 
//                .ADR1(ID_inst.rs1_addr), 
//                .ADR2(ID_inst.rs2_addr),  
//                .WA(WB_inst.rd_addr), 
//                .WD(wd), 
//                .RS1(rs1), 
//                .RS2(IOBUS_OUT)); 
                
endmodule

