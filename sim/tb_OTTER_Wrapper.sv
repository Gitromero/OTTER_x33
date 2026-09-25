`timescale 1ns / 1ps
// Testbench for OTTER_Wrapper: drives clock/reset/switches, logs 7-seg writes
// (and LED writes with +VERBOSE), and dumps a waveform (default build/otter.vcd;
// the Makefile passes +WAVE=build/otter.fst and `vvp -fst` for FST).
//   Plusargs: +CYCLES=<n> +SWITCHES=<hex> +PASS_COUNT=<n> +VERBOSE
//             +WAVE=<file> (waveform path) +NOWAVE (no waveform, faster)
//             +DUMP [+DUMP_LO=<hex> +DUMP_HI=<hex>] (print regs + data words)
//   Test_All convention: the 7-seg counts up once per passed test and is set
//   to 0xFFFFFFFF on a failure (x3/gp holds the failing case number).
module tb_OTTER_Wrapper;
    logic        CLK = 0;
    logic        BTNC = 1;
    logic [15:0] SWITCHES;
    logic [15:0] LEDS;
    logic [7:0]  CATHODES;
    logic [3:0]  ANODES;

    OTTER_Wrapper UUT (.*);
    otter_probe   probe();   // named per-stage signals for the waveform viewer

    always #5 CLK = ~CLK;   // 100 MHz board clock -> 50 MHz CPU clock

    localparam logic [31:0] LEDS_AD = 32'h11000020;
    localparam logic [31:0] SSEG_AD = 32'h11000040;

    int cycles, pass_count;
    bit verbose;
    string wave;
    initial begin
        if (!$value$plusargs("CYCLES=%d", cycles))         cycles     = 2000;
        if (!$value$plusargs("SWITCHES=%h", SWITCHES))     SWITCHES   = 16'h0000;
        if (!$value$plusargs("PASS_COUNT=%d", pass_count)) pass_count = -1;
        verbose = $test$plusargs("VERBOSE");

        if (!$test$plusargs("NOWAVE")) begin
            if (!$value$plusargs("WAVE=%s", wave)) wave = "build/otter.vcd";
            $dumpfile(wave);
            $dumpvars(0, tb_OTTER_Wrapper);
        end

        repeat (4) @(posedge UUT.clk_50);
        BTNC = 0;

        repeat (cycles) @(posedge UUT.clk_50);
        $display("[%0t] Stopped after %0d CPU cycles: LEDS=%h SSEG=%h",
                 $time, cycles, LEDS, UUT.r_SSEG);
        if (pass_count >= 0) $display("TIMEOUT: expected SSEG to reach %0d", pass_count);
        if ($test$plusargs("DUMP")) dump_state();
        $finish;
    end

    // Final architectural state, used by scripts/fuzz.py to compare with the ISS
    task automatic dump_state();
        int lo, hi;
        if (!$value$plusargs("DUMP_LO=%h", lo)) lo = 'h2000;
        if (!$value$plusargs("DUMP_HI=%h", hi)) hi = 'h2100;
        for (int r = 1; r < 32; r++)
            $display("REG %0d %h", r, UUT.CPU.OTTER_REG_FILE.ram[r]);
        for (int a = lo; a < hi; a += 4)
            $display("MEM %h %h", a, UUT.CPU.OTTER_MEMORY.memory[a >> 2]);
    endtask

    always @(posedge UUT.clk_50) begin
        if (!BTNC && UUT.IOBUS_wr) begin
            if (UUT.IOBUS_addr == SSEG_AD) begin
                $display("[%0t] SSEG <= %h", $time, UUT.IOBUS_out);
                if (UUT.IOBUS_out == 32'hFFFFFFFF) begin
                    $display("FAIL: test #%0d, case %0d (x3), LEDS=%h",
                             UUT.r_SSEG + 1, UUT.CPU.OTTER_REG_FILE.ram[3], LEDS);
                    $finish;
                end
                if (pass_count >= 0 && UUT.IOBUS_out == pass_count) begin
                    $display("PASS: all %0d tests passed", pass_count);
                    $finish;
                end
            end
            else if (verbose)
                $display("[%0t] IO write addr=%h data=%h", $time,
                         UUT.IOBUS_addr, UUT.IOBUS_out);
        end
    end
endmodule
