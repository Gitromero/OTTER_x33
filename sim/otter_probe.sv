`timescale 1ns / 1ps
// Waveform probe for the pipelined OTTER. Icarus dumps the pipeline structs
// (ID_inst, ALU_inst, ...) as one 328-bit vector, so this module unpacks the
// useful fields into named signals, one group per stage, plus the register
// file as x1..x31. sim/otter.gtkw lays them out Vivado-style.
//
// *_ir is the instruction word in each stage (0 = bubble). It is looked up in
// memory by the stage's PC, so self-modifying code would show the new word.
// *_name signals are 8-char ASCII vectors; GTKWave shows them as text.
module otter_probe;
    import otter_pkg::*;

    // CPU clock and reset
    wire        clk   = tb_OTTER_Wrapper.UUT.clk_50;
    wire        rst   = tb_OTTER_Wrapper.UUT.s_reset;
    wire        STALL = tb_OTTER_Wrapper.UUT.CPU.STALL;
    wire        FLUSH = tb_OTTER_Wrapper.UUT.CPU.FLUSH;

    // Fetch
    wire [31:0] IF_pc = tb_OTTER_Wrapper.UUT.CPU.pc_out;
    wire [2:0]  IF_pc_source = tb_OTTER_Wrapper.UUT.CPU.pc_source;

    // Instruction word of a stage, 0 for a bubble
    `define IMEM(s) (s.valid ? tb_OTTER_Wrapper.UUT.CPU.OTTER_MEMORY.memory[s.pc[15:2]] : 32'b0)

    // Decode
    instr_t ID, EX, MEM, WB;
    assign ID  = tb_OTTER_Wrapper.UUT.CPU.ID_inst;
    assign EX  = tb_OTTER_Wrapper.UUT.CPU.ALU_inst;
    assign MEM = tb_OTTER_Wrapper.UUT.CPU.MEM_inst;
    assign WB  = tb_OTTER_Wrapper.UUT.CPU.WB_inst;

    wire        ID_valid = ID.valid;
    wire [31:0] ID_pc    = ID.pc;
    wire [31:0] ID_ir    = ID.valid ? tb_OTTER_Wrapper.UUT.CPU.ir : 32'b0;
    wire [4:0]  ID_rs1   = ID.rs1_addr;
    wire [4:0]  ID_rs2   = ID.rs2_addr;
    wire [31:0] ID_rs1_data = ID.rs1;
    wire [31:0] ID_rs2_data = ID.rs2;

    // Execute
    wire        EX_valid  = EX.valid;
    wire [31:0] EX_pc     = EX.pc;
    wire [31:0] EX_ir     = `IMEM(EX);
    wire [4:0]  EX_rd     = EX.rd_addr;
    wire [1:0]  EX_fsel1  = tb_OTTER_Wrapper.UUT.CPU.fsel1;
    wire [1:0]  EX_fsel2  = tb_OTTER_Wrapper.UUT.CPU.fsel2;
    wire [31:0] EX_rs1_fwd = tb_OTTER_Wrapper.UUT.CPU.F_MUX_A_OUT;
    wire [31:0] EX_rs2_fwd = tb_OTTER_Wrapper.UUT.CPU.F_MUX_B_OUT;
    wire [31:0] EX_srcA   = tb_OTTER_Wrapper.UUT.CPU.srcA;
    wire [31:0] EX_srcB   = tb_OTTER_Wrapper.UUT.CPU.srcB;
    wire [3:0]  EX_alu_fun = EX.alu_fun;
    wire [31:0] EX_alu_result = tb_OTTER_Wrapper.UUT.CPU.alu_result;

    // Memory
    wire        MEM_valid = MEM.valid;
    wire [31:0] MEM_pc    = MEM.pc;
    wire [31:0] MEM_ir    = `IMEM(MEM);
    wire [31:0] MEM_addr  = MEM.alu_result;
    wire [31:0] MEM_wdata = MEM.rs2;
    wire        MEM_we    = MEM.mem_we2;
    wire        MEM_rden  = MEM.mem_rden2;
    wire        IO_wr     = tb_OTTER_Wrapper.UUT.IOBUS_wr;

    // Writeback
    wire        WB_valid  = WB.valid;
    wire [31:0] WB_pc     = WB.pc;
    wire [31:0] WB_ir     = `IMEM(WB);
    wire [4:0]  WB_rd     = WB.rd_addr;
    wire        WB_reg_wr = WB.reg_wr;
    wire [31:0] WB_data   = tb_OTTER_Wrapper.UUT.CPU.wd;

    // Human-readable decodes (ASCII, shown as text in GTKWave)
    logic [63:0] IF_pc_source_name, EX_alu_name, EX_fsel1_name, EX_fsel2_name;
    always_comb begin
        case (IF_pc_source)
            3'd0: IF_pc_source_name = "pc+4";
            3'd1: IF_pc_source_name = "jalr";
            3'd2: IF_pc_source_name = "branch";
            3'd3: IF_pc_source_name = "jal";
            3'd4: IF_pc_source_name = "mtvec";
            3'd5: IF_pc_source_name = "mepc";
            default: IF_pc_source_name = "?";
        endcase
        case (EX_alu_fun)
            4'b0000: EX_alu_name = "add";
            4'b1000: EX_alu_name = "sub";
            4'b0110: EX_alu_name = "or";
            4'b0111: EX_alu_name = "and";
            4'b0100: EX_alu_name = "xor";
            4'b0101: EX_alu_name = "srl";
            4'b0001: EX_alu_name = "sll";
            4'b1101: EX_alu_name = "sra";
            4'b0010: EX_alu_name = "slt";
            4'b0011: EX_alu_name = "sltu";
            4'b1001: EX_alu_name = "lui";
            default: EX_alu_name = "?";
        endcase
        EX_fsel1_name = fsel_name(EX_fsel1);
        EX_fsel2_name = fsel_name(EX_fsel2);
        IF_pc_source_name = ljust(IF_pc_source_name);
        EX_alu_name       = ljust(EX_alu_name);
        EX_fsel1_name     = ljust(EX_fsel1_name);
        EX_fsel2_name     = ljust(EX_fsel2_name);
    end

    // "\0\0\0add" -> "add     " (GTKWave shows leading NULs as dots)
    function automatic logic [63:0] ljust(logic [63:0] s);
        for (int i = 0; i < 7 && s[63:56] == 8'h00; i++)
            s = {s[55:0], 8'h20};
        return s;
    endfunction

    function automatic logic [63:0] fsel_name(logic [1:0] sel);
        case (sel)
            2'd0: return "regfile";
            2'd1: return "fwd MEM";
            2'd2: return "fwd WB";
            default: return "?";
        endcase
    endfunction

    // Register file, named x<n>_<abi> so they sort and read like a debugger
    `define RF(n) tb_OTTER_Wrapper.UUT.CPU.OTTER_REG_FILE.ram[n]
    wire [31:0] x01_ra = `RF(1);
    wire [31:0] x02_sp = `RF(2);
    wire [31:0] x03_gp = `RF(3);
    wire [31:0] x04_tp = `RF(4);
    wire [31:0] x05_t0 = `RF(5);
    wire [31:0] x06_t1 = `RF(6);
    wire [31:0] x07_t2 = `RF(7);
    wire [31:0] x08_s0 = `RF(8);
    wire [31:0] x09_s1 = `RF(9);
    wire [31:0] x10_a0 = `RF(10);
    wire [31:0] x11_a1 = `RF(11);
    wire [31:0] x12_a2 = `RF(12);
    wire [31:0] x13_a3 = `RF(13);
    wire [31:0] x14_a4 = `RF(14);
    wire [31:0] x15_a5 = `RF(15);
    wire [31:0] x16_a6 = `RF(16);
    wire [31:0] x17_a7 = `RF(17);
    wire [31:0] x18_s2 = `RF(18);
    wire [31:0] x19_s3 = `RF(19);
    wire [31:0] x20_s4 = `RF(20);
    wire [31:0] x21_s5 = `RF(21);
    wire [31:0] x22_s6 = `RF(22);
    wire [31:0] x23_s7 = `RF(23);
    wire [31:0] x24_s8 = `RF(24);
    wire [31:0] x25_s9 = `RF(25);
    wire [31:0] x26_s10 = `RF(26);
    wire [31:0] x27_s11 = `RF(27);
    wire [31:0] x28_t3 = `RF(28);
    wire [31:0] x29_t4 = `RF(29);
    wire [31:0] x30_t5 = `RF(30);
    wire [31:0] x31_t6 = `RF(31);
    `undef RF
endmodule
