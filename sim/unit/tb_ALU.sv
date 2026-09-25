`timescale 1ns / 1ps
// Self-checking unit test for ALU.sv, and a template for testing other modules:
// copy to sim/unit/tb_<Module>.sv and run `make unit T=<Module>`.
// Prints PASS/FAIL; the waveform goes to build/tb_ALU.fst (`make unit-wave T=ALU`).
module tb_ALU;
    logic [31:0] SRC_A, SRC_B, RESULT;
    logic [3:0]  ALU_FUN;

    ALU dut (.*);

    // Reference model
    function automatic logic [31:0] model(logic [3:0] fun, logic [31:0] a, b);
        case (fun)
            4'b0000: return a + b;
            4'b1000: return a - b;
            4'b0110: return a | b;
            4'b0111: return a & b;
            4'b0100: return a ^ b;
            4'b0101: return a >> b[4:0];
            4'b0001: return a << b[4:0];
            4'b1101: return $signed(a) >>> b[4:0];
            4'b0010: return {31'b0, $signed(a) < $signed(b)};
            4'b0011: return {31'b0, a < b};
            4'b1001: return a;
            default: return 32'b0;
        endcase
    endfunction

    int errors = 0;
    task automatic check(logic [3:0] fun, logic [31:0] a, b);
        ALU_FUN = fun; SRC_A = a; SRC_B = b;
        #1;
        if (RESULT !== model(fun, a, b)) begin
            errors++;
            if (errors <= 10)
                $display("FAIL: fun=%b a=%h b=%h -> %h, expected %h",
                         fun, a, b, RESULT, model(fun, a, b));
        end
        #9;
    endtask

    // Corner-case operands
    function automatic logic [31:0] edge_val(int i);
        case (i)
            0: return 32'h0;         1: return 32'h1;         2: return 32'hFFFFFFFF;
            3: return 32'h7FFFFFFF;  4: return 32'h80000000;  default: return 32'h1F;
        endcase
    endfunction
    initial begin
        string wave;
        if (!$value$plusargs("WAVE=%s", wave)) wave = "build/tb_ALU.fst";
        $dumpfile(wave);
        $dumpvars(0, tb_ALU);

        for (int f = 0; f < 16; f++) begin
            for (int i = 0; i < 6; i++)
                for (int j = 0; j < 6; j++) check(f, edge_val(i), edge_val(j));
            repeat (200) check(f, $urandom, $urandom);
        end
        if (errors == 0) $display("PASS: tb_ALU");
        else             $display("FAIL: tb_ALU, %0d errors", errors);
        $finish;
    end
endmodule
