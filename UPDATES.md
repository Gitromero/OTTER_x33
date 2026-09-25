# OTTER x33 — Progress Log

Newest entries first. Each entry: what changed, why, and how it was verified.

---

## 2026-09-24 — Hazard/branch audit, JALR fix, random differential testing

### Bug fixed
- **JALR did not clear bit 0 of the target** (`rtl/core/BAG.sv`). RISC-V requires
  `target = (rs1 + imm) & ~1`. With an odd offset the PC became odd, so every
  later `jal`/`jalr`/`auipc` produced link/PC values off by 1–3.
  `Test_All` never uses an odd JALR offset, so it passed anyway; random
  testing caught it in 183/200 programs.

### Hazard / branch audit
No holes found in the current hazard unit (`HD.sv`) or branch resolution. Note:
the original `HD.sv` was never in the repo, so this audits the rewritten one.
Covered and confirmed:
- Forwarding from MEM and WB into EX, with MEM taking priority
- Load-use stall (1 cycle), including loads feeding branches, JALR, and store data
- Taken branch/JAL/JALR flushes both younger instructions (IF and ID)
- Wrong-path stores never reach memory or MMIO
- Switch (MMIO) reads return the correct value in WB

### New verification tools
- `scripts/rv32i.py` — small RV32I assembler + reference instruction-set
  simulator. Validated: encodings match `Test_All_Debug.txt`, and it passes
  `Test_All` independently.
- `scripts/fuzz.py` / `make fuzz` — generates random hazard-heavy programs
  (back-to-back dependencies, load-use, all branch types, jal, auipc→jalr with
  odd offsets, a counted backward loop, switch reads, LED writes). Runs each on
  the RTL and the reference model and compares all registers, data memory, and
  the exact LED write sequence. Failures are saved to `build/fuzz_fail_<seed>.s`.
- Testbench: `+DUMP` prints final registers and data memory.

### Verification results
- `make test`: Test_All 37/37 PASS (Icarus and Verilator)
- `make fuzz`: 1000/1000 random programs match the reference model
- Mutation check: each of these planted bugs was caught within 20 programs:
  no load-use stall, no WB forwarding, no MEM forwarding, IF not flushed,
  ID not flushed, MMIO read not delayed

### Still not implemented
- CSR instructions, `ecall`, `mret`, interrupts (SYSTEM opcode executes as a
  NOP; `MTVEC`/`MEPC` tied to 0)

---

## 2026-09-24 — Pipeline repair, project reorganization, simulation setup

### Simulation environment
- `Makefile`: `make test`, `make sim PROG=<name>`, `make wave`, `make lint`, `make clean`
  (Icarus Verilog 12, Verilator 5.020, GTKWave)
- `sim/tb_OTTER_Wrapper.sv`: clock/reset/switches, logs 7-seg writes, reports
  PASS/FAIL for Test_All, writes `build/otter.vcd`
- `README.md` with layout and usage

### File reorganization
```
rtl/core/     CPU pipeline + submodules
rtl/memory/   otter_memory_v1_08.sv
rtl/io/       OTTER_Wrapper, 7-seg display
rtl/legacy/   CU_FSM.sv (multicycle, unused)
constraints/  Basys3_Master.xdc
mem/          Test_All.mem, Test_All_Debug.txt, hazard_test.mem
sim/          testbench
```
Moved with `git mv` so history is kept. The old 6-instruction `Test_All.mem`
is now `mem/hazard_test.mem`.

### Pipeline fixes
- **`OTTER.sv` rewired** as a proper 5-stage pipeline. Previously `ALU_inst` and
  `MEM_inst` had multiple drivers (rejected by Icarus and Verilator), there
  was a combinational loop through `IOBUS_ADDR`, and `Jtype` was undeclared
  (1-bit implicit wire).
- **Added missing modules:** `HD.sv` (forwarding, load-use stall, flush),
  `ThreeMux.sv`, `otter_pkg.sv` (opcode enum + pipeline struct).
  `FLUSH_COUNTER` replaced by an IF/ID valid bit.
- **`CU_DCDR.sv`:** loads now set `REG_WRITE` and branches no longer do (the
  multicycle FSM used to handle this).
- **Memory v1.08:** size/sign/byte-offset/IO-select are registered with the
  read, so load data is correct in WB. Init file selectable via `MEM_FILE`.
- **`REG_FILE.sv`:** `!WA == 5'd0` → `WA != 5'd0`.

### Test program
- `mem/Test_All.mem` rebuilt from `Test_All_Debug.txt`. The listing has no data
  section, so data at 0x3f60–0x3fbf was filled with the standard riscv-tests
  values at the referenced addresses (later confirmed by the reference model
  passing Test_All). Replace with the original class `.mem` if available.

### Verification results
- `make test`: 37/37 PASS
