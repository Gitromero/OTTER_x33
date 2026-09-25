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
sim/          tb_OTTER_Wrapper.sv
scripts/      rv32i.py (assembler + reference ISS), fuzz.py (random differential test)
```

## Simulating (Icarus Verilog + GTKWave)
```
make test                       # full Test_All, prints PASS/FAIL (~10 s)
make sim PROG=hazard_test       # run any mem/<PROG>.mem
make fuzz                       # 200 random programs vs. the reference model (~1 min)
make sim CYCLES=5000 VERBOSE=1  # longer run, also log LED writes
make wave                       # open build/otter.vcd in GTKWave
make lint                       # Verilator lint
```

## Fuzzing
`scripts/fuzz.py` generates random programs dense in hazards (back-to-back
dependencies, load-use, forward branches, jal/jalr, a counted loop, switch
reads and LED writes), runs them on the RTL and on `scripts/rv32i.py`, and
compares all registers, data memory, and the LED write sequence. Failing
programs are saved as `build/fuzz_fail_<seed>.s`; rerun one with
`python3 scripts/fuzz.py --seed <seed> --keep` and inspect `make wave`.

`rv32i.py` can also assemble your own tests:
```
python3 -c "import sys; sys.path.insert(0,'scripts'); from rv32i import *; \
  write_mem('mem/mytest.mem', assemble(open('mytest.s').read()), 16)"
```

## Vivado
Add every file under `rtl/core`, `rtl/memory`, `rtl/io`, plus `mem/Test_All.mem`
and `constraints/Basys3_Master.xdc`. Set `OTTER_Wrapper` as top. Memory loads
`Test_All.mem` by default (override with the `MEM_FILE` define).

## Note on mem/Test_All.mem
Instructions were extracted from `Test_All_Debug.txt`. That listing has no data
section, so the data words at 0x3f60–0x3fbf were rebuilt from the standard
riscv-tests values at the addresses the listing references.
