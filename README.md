# OTTER x33 — 5-stage pipelined RV32I OTTER

See `UPDATES.md` for the progress log.

## Layout
```
rtl/core/     CPU: OTTER.sv (pipeline top), otter_pkg.sv (types), HD.sv (hazards),
              ALU, CU_DCDR, ImmediateGenerator, REG_FILE, PC/PC_MUX/PC_REG, BAG, BCG, muxes
rtl/memory/   otter_memory_v1_08.sv (dual-port BRAM + MMIO)
rtl/io/       OTTER_Wrapper (Basys3 top), SevSegDisp, CathodeDriver, BCD
rtl/legacy/   CU_FSM.sv from the multicycle OTTER (not used by the pipeline)
constraints/  Basys3_Master.xdc
mem/          Test_All.mem (full RV32I test), Test_All_Debug.txt (its listing),
              hazard_test.mem (small forwarding test)
asm/          assembly sources; asm/<name>.s is assembled to mem/<name>.mem on demand
sim/          tb_OTTER_Wrapper.sv, otter_probe.sv (named per-stage signals for waves),
              otter.gtkw (GTKWave layout), unit/tb_<Module>.sv (unit tests)
scripts/      rv32i.py (assembler, disassembler, reference ISS), fuzz.py (random
              differential test), gtkwave_disasm.py (shows instructions as text in
              GTKWave), new_hdl_project.sh (copy this environment to a new project)
.vscode/      Verilator lint-on-save, build tasks (Ctrl+Shift+B = make test)
```

## Commands (Icarus Verilog + GTKWave)
```
make help                       list everything below
make check-env                  check iverilog / verilator / gtkwave / python3 are installed

make test                       full Test_All, prints PASS/FAIL (~12 s)
make sim PROG=hazard_test       run any mem/<PROG>.mem (or asm/<PROG>.s, assembled first)
make sim CYCLES=5000 VERBOSE=1  longer run, also log LED writes
make sim SWITCHES=abcd          set the switch inputs (hex)
make wave                       open the last run in GTKWave with the pipeline layout
make fuzz [N=200]               random programs vs. the reference model

make asm PROG=example           asm/example.s -> mem/example.mem
make dis PROG=Test_All          disassembly listing of mem/Test_All.mem
make iss PROG=example           run on the Python reference model, print registers

make unit T=ALU                 run sim/unit/tb_ALU.sv (self-checking)
make units                      run every sim/unit/tb_*.sv
make unit-wave T=ALU            waveform of a unit test

make lint                       Verilator lint
make clean
WAVE_FMT=fst|vcd|none           waveform format (default fst; none = fastest)
```

## Waveforms (Vivado-style)
`make sim` / `make test` write `build/otter.fst`; `make wave` opens it in GTKWave
with `sim/otter.gtkw`, which has one colored group per pipeline stage:

- **Clock / Control**: CPU clock, reset, STALL, FLUSH
- **IF**: PC and next-PC source (`pc+4`, `branch`, `jal`, `jalr`)
- **ID / EX / MEM / WB**: each stage's PC, valid bit and instruction shown as
  assembly (`addi x1, x0, 10`; `--` is a bubble), plus the stage's key values:
  forwarding source (`regfile` / `fwd MEM` / `fwd WB`), ALU op name and inputs,
  memory address/data/write enable, writeback register and data
- **Register File**: x1..x31 with ABI names
- **Board I/O**: switches, LEDs, 7-seg value

These come from `sim/otter_probe.sv`, which unpacks the pipeline structs (Icarus
dumps them as one 328-bit vector). Everything else is still in the tree on the
left under `tb_OTTER_Wrapper.UUT`.

GTKWave tips: after re-running the sim press **Ctrl+Shift+R** to reload and keep
the view. Save layout changes with **Ctrl+S** (writes `sim/otter.gtkw`). Select
signals + **G** makes a group. Right-click a signal > Data Format for radix; for
any other instruction-word signal use Data Format > Translate Filter Process >
`scripts/gtkwave_disasm.py`. Zoom: Ctrl+scroll, or the zoom-fit button.

## Writing test programs
Put assembly in `asm/<name>.s` (syntax: x0..x31 registers, labels, `#` comments,
pseudo-ops `nop li mv j beqz bnez`), then `make sim PROG=<name>`; the `.mem` is
rebuilt whenever the `.s` changes. `asm/example.s` is a starting point.
`make iss PROG=<name>` runs the same program on the reference model so you can
compare final registers.

## Unit tests
`sim/unit/tb_ALU.sv` checks the ALU against a reference model (corner cases +
random). Copy it to `sim/unit/tb_<Module>.sv` for other modules; a testbench
passes if it prints a line starting with `PASS` and none starting with `FAIL`.

## VS Code
`.vscode/` enables Verilator lint-on-save through the Verilog-HDL extension
(`mshr-h.veriloghdl`), and tasks: Ctrl+Shift+B runs `make test`, Ctrl+Shift+P >
Run Task for sim/wave/units/fuzz/lint (lint warnings show in the Problems panel).

## New projects
`scripts/new_hdl_project.sh` sets up this same environment for another project
(generic Makefile, testbench + unit test + GTKWave layout templates, VS Code
config, README/UPDATES, a working example):
```
scripts/new_hdl_project.sh ~/CalPoly/systemverilog/my_proj            # new project
scripts/new_hdl_project.sh ~/path/my_cpu --top my_cpu --riscv         # + RISC-V tools
scripts/new_hdl_project.sh ~/path/my_proj --install                   # also apt/dnf/pacman/brew install tools
scripts/new_hdl_project.sh ~/path/existing --force                    # add missing files only
```

## Fuzzing
`scripts/fuzz.py` generates random programs dense in hazards (back-to-back
dependencies, load-use, forward branches, jal/jalr, a counted loop, switch
reads and LED writes), runs them on the RTL and on `scripts/rv32i.py`, and
compares all registers, data memory, and the LED write sequence. Failing
programs are saved as `build/fuzz_fail_<seed>.s`; rerun one with
`python3 scripts/fuzz.py --seed <seed> --keep` and inspect `make wave`
(program source in `build/fuzz.s`).

`rv32i.py` also works standalone:
```
python3 scripts/rv32i.py asm mytest.s -o mem/mytest.mem
python3 scripts/rv32i.py dis mem/mytest.mem
python3 scripts/rv32i.py run mytest.s --switches 00ff
```

## Vivado
Add every file under `rtl/core`, `rtl/memory`, `rtl/io`, plus `mem/Test_All.mem`
and `constraints/Basys3_Master.xdc`. Set `OTTER_Wrapper` as top. Memory loads
`Test_All.mem` by default (override with the `MEM_FILE` define).

## Note on mem/Test_All.mem
Instructions were extracted from `Test_All_Debug.txt`. That listing has no data
section, so the data words at 0x3f60–0x3fbf were rebuilt from the standard
riscv-tests values at the addresses the listing references.
