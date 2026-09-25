#!/usr/bin/env bash
# Create a new SystemVerilog project with the same simulation environment as
# OTTER_x33: Icarus Verilog + GTKWave (FST waves, saved layouts), Verilator lint,
# self-checking unit tests, VS Code settings/tasks, and a working example.
#
#   scripts/new_hdl_project.sh <dir> [options]
#     --top <name>   top module name (default: the directory name)
#     --riscv        also copy the RV32I assembler/ISS/disassembler + GTKWave
#                    instruction filter (for RISC-V CPU projects)
#     --install      install the tools first (apt, dnf, pacman or brew; uses sudo)
#     --no-git       don't run `git init`
#     --force        allow a non-empty target directory (existing files are kept)
#
# Afterwards:  cd <dir> && make help
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

DIR="" TOP="" RISCV=0 INSTALL=0 GIT=1 FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --top)     TOP="$2"; shift 2 ;;
        --riscv)   RISCV=1; shift ;;
        --install) INSTALL=1; shift ;;
        --no-git)  GIT=0; shift ;;
        --force)   FORCE=1; shift ;;
        -h|--help) usage ;;
        -*)        echo "unknown option $1" >&2; usage 1 ;;
        *)         [[ -z "$DIR" ]] || usage 1; DIR="$1"; shift ;;
    esac
done
[[ -n "$DIR" ]] || usage 1
TOP="${TOP:-$(basename "$DIR" | tr -c 'A-Za-z0-9_\n' '_')}"
[[ "$TOP" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "bad top module name '$TOP' (use --top)" >&2; exit 1; }

#---- Tools --------------------------------------------------------------------------
if [[ $INSTALL == 1 ]]; then
    if command -v apt-get >/dev/null; then
        sudo apt-get update && sudo apt-get install -y iverilog verilator gtkwave python3 make git
    elif command -v dnf >/dev/null; then
        sudo dnf install -y iverilog verilator gtkwave python3 make git
    elif command -v pacman >/dev/null; then
        sudo pacman -S --needed iverilog verilator gtkwave python make git
    elif command -v brew >/dev/null; then
        brew install icarus-verilog verilator python make git && brew install --cask gtkwave
    else
        echo "no known package manager; install iverilog, verilator, gtkwave, python3, make by hand" >&2
    fi
fi
missing=()
for t in iverilog vvp verilator gtkwave python3 make; do command -v "$t" >/dev/null || missing+=("$t"); done
[[ ${#missing[@]} -eq 0 ]] || echo "warning: not installed: ${missing[*]} (rerun with --install)" >&2

#---- Target directory ---------------------------------------------------------------
if [[ -d "$DIR" && -n "$(ls -A "$DIR")" && $FORCE == 0 ]]; then
    echo "$DIR exists and is not empty (use --force to add files without overwriting)" >&2
    exit 1
fi
mkdir -p "$DIR"/{rtl,sim/unit,.vscode}
cd "$DIR"

# write <path>: stdin -> file, never overwriting; @TOP@ is replaced with the top name
write() {
    if [[ -e "$1" ]]; then echo "  keep   $1"; cat >/dev/null; return; fi
    sed "s/@TOP@/$TOP/g" > "$1"
    echo "  create $1"
}

write Makefile <<'EOF'
# Simulation / lint flow (Icarus Verilog, Verilator, GTKWave). `make help` lists targets.
# Sources: every .sv under rtl/ (files named *_pkg.sv are compiled first).
# Testbench: sim/tb_$(TOP).sv. Unit tests: sim/unit/tb_<Module>.sv.
# Testbenches print a line starting with PASS or FAIL; FAIL makes make fail.

TOP      ?= @TOP@
WAVE_FMT ?= fst

RTL   := $(shell find rtl -name '*.sv' | sort)
PKGS  := $(filter %_pkg.sv,$(RTL))
SRCS  := $(PKGS) $(filter-out $(PKGS),$(RTL))
BUILD := build
UNIT_TBS := $(wildcard sim/unit/tb_*.sv)

IVERILOG := iverilog -g2012 -Wno-timescale $(addprefix -I,$(sort $(dir $(RTL))))
QUIET    := 2>&1 | { grep -v 'sorry: constant selects' || true; }
SHELL    := /bin/bash -o pipefail
WAVE_ARGS = $(if $(filter none,$(WAVE_FMT)),+NOWAVE,+WAVE=$(BUILD)/$(1).$(WAVE_FMT) $(if $(filter fst,$(WAVE_FMT)),-fst))

.PHONY: help sim test wave unit units unit-wave lint check-env clean

help:
	@echo "  make sim                  run sim/tb_$(TOP).sv (plusargs: ARGS='+FOO=1')"
	@echo "  make test                 same, fails unless it prints PASS"
	@echo "  make wave                 open the waveform (layout: sim/tb_$(TOP).gtkw)"
	@echo "  make unit T=<Module>      run sim/unit/tb_<Module>.sv"
	@echo "  make units                run every unit test"
	@echo "  make unit-wave T=<Module> open a unit test's waveform"
	@echo "  make lint                 Verilator lint of rtl/"
	@echo "  make check-env / clean"
	@echo "Options: TOP=<module> WAVE_FMT=fst|vcd|none"

# $(call run,<tb name>,<tb file>)
define run
	@mkdir -p $(BUILD)
	$(IVERILOG) -s $(1) -o $(BUILD)/$(1).vvp $(SRCS) $(2) $(QUIET)
	vvp -n $(BUILD)/$(1).vvp $(call WAVE_ARGS,$(1)) $(ARGS) | tee $(BUILD)/$(1).log
	@! grep -q '^FAIL' $(BUILD)/$(1).log
endef

sim:
	$(call run,tb_$(TOP),sim/tb_$(TOP).sv)

test: sim
	@grep -q '^PASS' $(BUILD)/tb_$(TOP).log || { echo "no PASS line"; exit 1; }

wave:
	gtkwave $(BUILD)/tb_$(TOP).$(WAVE_FMT) $(wildcard sim/tb_$(TOP).gtkw) >/dev/null 2>&1 &

unit:
	@test -n "$(T)" || { echo "usage: make unit T=<Module>  (have: $(patsubst sim/unit/tb_%.sv,%,$(UNIT_TBS)))"; exit 1; }
	$(call run,tb_$(T),sim/unit/tb_$(T).sv)

units:
	@fail=0; for t in $(patsubst sim/unit/tb_%.sv,%,$(UNIT_TBS)); do \
		$(MAKE) --no-print-directory unit T=$$t >/dev/null 2>&1; \
		grep -E '^(PASS|FAIL)' $(BUILD)/tb_$$t.log | tail -1 || { echo "FAIL: tb_$$t (no result)"; fail=1; }; \
		grep -q '^FAIL' $(BUILD)/tb_$$t.log && fail=1; done; exit $$fail

unit-wave:
	gtkwave $(BUILD)/tb_$(T).$(WAVE_FMT) $(wildcard sim/unit/tb_$(T).gtkw) >/dev/null 2>&1 &

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(SRCS)

check-env:
	@for t in iverilog vvp verilator gtkwave python3; do \
		printf '%-10s ' $$t; command -v $$t >/dev/null && echo ok || echo MISSING; done

clean:
	rm -rf $(BUILD)
EOF

write "rtl/$TOP.sv" <<'EOF'
`timescale 1ns / 1ps
// Example design (replace me): 8-bit counter with enable and synchronous reset.
module @TOP@ (
    input  logic       clk,
    input  logic       rst,
    input  logic       en,
    output logic [7:0] count
);
    always_ff @(posedge clk) begin
        if (rst)     count <= '0;
        else if (en) count <= count + 1;
    end
endmodule
EOF

write "sim/tb_$TOP.sv" <<'EOF'
`timescale 1ns / 1ps
// Top-level testbench. Prints PASS/FAIL; waveform path comes from +WAVE=<file>.
module tb_@TOP@;
    logic       clk = 0, rst = 1, en = 0;
    logic [7:0] count;
    int errors = 0;

    @TOP@ dut (.*);

    always #5 clk = ~clk;   // 100 MHz

    initial begin
        string wave;
        if (!$test$plusargs("NOWAVE")) begin
            if (!$value$plusargs("WAVE=%s", wave)) wave = "build/tb_@TOP@.vcd";
            $dumpfile(wave);
            $dumpvars(0, tb_@TOP@);
        end

        repeat (2) @(posedge clk);
        rst <= 0;
        en  <= 1;
        repeat (10) @(posedge clk);
        en  <= 0;
        @(posedge clk);
        #1 if (count !== 8'd10) begin
            errors++;
            $display("FAIL: count = %0d, expected 10", count);
        end
        if (errors == 0) $display("PASS: tb_@TOP@");
        $finish;
    end
endmodule
EOF

write "sim/unit/tb_$TOP.sv" <<'EOF'
`timescale 1ns / 1ps
// Unit test template: copy to sim/unit/tb_<Module>.sv and run `make unit T=<Module>`.
// Pattern: drive inputs, compare against a reference model, print PASS/FAIL.
module tb_@TOP@;
    logic       clk = 0, rst = 1, en;
    logic [7:0] count, expected;
    int errors = 0;

    @TOP@ dut (.*);

    always #5 clk = ~clk;

    initial begin
        string wave;
        if (!$value$plusargs("WAVE=%s", wave)) wave = "build/tb_@TOP@.vcd";
        $dumpfile(wave);
        $dumpvars(0, tb_@TOP@);

        en = 0;
        expected = 0;
        @(posedge clk);
        #1 rst = 0;
        repeat (600) begin                 // random enables, wraps past 255
            en = $urandom_range(0, 1);
            @(posedge clk);
            if (en) expected++;
            #1 if (count !== expected) begin
                errors++;
                if (errors <= 10) $display("FAIL: count=%0d expected=%0d", count, expected);
            end
        end
        if (errors == 0) $display("PASS: tb_@TOP@");
        else             $display("FAIL: tb_@TOP@, %0d errors", errors);
        $finish;
    end
endmodule
EOF

write "sim/tb_$TOP.gtkw" <<'EOF'
[*] GTKWave layout for tb_@TOP@. Change it in GTKWave, then File > Write Save File (Ctrl+S).
[timestart] 0
*-16.000000 0 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1
[treeopen] tb_@TOP@.
[sst_width] 220
[signals_width] 180
[sst_expanded] 1
@800200
-Inputs
@28
tb_@TOP@.clk
tb_@TOP@.rst
tb_@TOP@.en
@1000200
-Inputs
@800200
-Outputs
@24
tb_@TOP@.count[7:0]
@1000200
-Outputs
EOF

write .gitignore <<'EOF'
build/
*.vcd
*.fst
*.vvp
__pycache__/
EOF

write .vscode/settings.json <<'EOF'
{
    // Verilog-HDL/SystemVerilog extension (mshr-h.veriloghdl): lint on save with Verilator.
    // Add package files to the arguments (before the file) if modules import them.
    "verilog.linting.linter": "verilator",
    "verilog.linting.verilator.runAtFileLocation": false,
    "verilog.linting.verilator.arguments": "-Wno-fatal -Wno-DECLFILENAME -Wno-MULTITOP -Irtl",
    "files.associations": { "*.sv": "systemverilog", "*.svh": "systemverilog", "*.gtkw": "ini" },
    "files.exclude": { "build": true, "**/__pycache__": true }
}
EOF

write .vscode/tasks.json <<'EOF'
{
    // Ctrl+Shift+B runs `make test`; Ctrl+Shift+P > "Run Task" for the rest.
    "version": "2.0.0",
    "tasks": [
        { "label": "make test", "type": "shell", "command": "make test",
          "group": { "kind": "build", "isDefault": true }, "problemMatcher": [] },
        { "label": "make wave", "type": "shell", "command": "make wave", "problemMatcher": [] },
        { "label": "make units", "type": "shell", "command": "make units", "group": "test", "problemMatcher": [] },
        { "label": "make lint", "type": "shell", "command": "make lint",
          "problemMatcher": {
              "owner": "verilator", "fileLocation": ["relative", "${workspaceFolder}"],
              "pattern": { "regexp": "^%(Warning|Error)[^:]*: ([^:]+):(\\d+):(\\d+): (.*)$",
                           "severity": 1, "file": 2, "line": 3, "column": 4, "message": 5 } } }
    ]
}
EOF

write .vscode/extensions.json <<'EOF'
{ "recommendations": ["mshr-h.veriloghdl"] }
EOF

write README.md <<'EOF'
# @TOP@

## Layout
```
rtl/          design sources (*_pkg.sv compiled first)
sim/          tb_@TOP@.sv (top testbench), tb_@TOP@.gtkw (waveform layout)
sim/unit/     tb_<Module>.sv self-checking unit tests
build/        generated: compiled sims, logs, waveforms
```

## Commands
```
make help                 list targets
make test                 run sim/tb_@TOP@.sv, PASS/FAIL
make sim ARGS='+X=1'      run with plusargs
make wave                 open the waveform in GTKWave with the saved layout
make unit T=<Module>      run sim/unit/tb_<Module>.sv
make units                run all unit tests
make unit-wave T=<Module> waveform of a unit test
make lint                 Verilator lint
make check-env            check the tools are installed
WAVE_FMT=vcd|none         change waveform format (default fst)
```

## Waveforms
`make wave` opens `build/tb_@TOP@.fst` with `sim/tb_@TOP@.gtkw`. Add signals from
the tree on the left, group them (select + `G`), change radix (right-click >
Data Format), then Ctrl+S to save the layout. After re-running the simulation,
press Ctrl+Shift+R in GTKWave to reload without losing the view.
EOF

write UPDATES.md <<'EOF'
# @TOP@ — Progress Log

Newest entries first. Each entry: what changed, why, and how it was verified.
EOF

#---- Optional RISC-V tools ----------------------------------------------------------
if [[ $RISCV == 1 ]]; then
    mkdir -p scripts asm
    for f in rv32i.py gtkwave_disasm.py; do
        if [[ -e "scripts/$f" ]]; then echo "  keep   scripts/$f"
        else cp "$SRC_DIR/$f" "scripts/$f"; chmod +x "scripts/$f"; echo "  create scripts/$f"; fi
    done
    grep -q "## RISC-V tools" README.md || cat >> README.md <<'EOF'

## RISC-V tools
```
python3 scripts/rv32i.py asm asm/prog.s -o mem/prog.mem   # assemble
python3 scripts/rv32i.py dis mem/prog.mem                 # disassemble
python3 scripts/rv32i.py run asm/prog.s                   # reference ISS, prints registers
```
To show an instruction-word signal as assembly in GTKWave: right-click it >
Data Format > Translate Filter Process > Enable and Select >
`scripts/gtkwave_disasm.py`, then Ctrl+S to keep it in the layout.
EOF
fi

if [[ $GIT == 1 ]] && command -v git >/dev/null && ! git rev-parse --git-dir >/dev/null 2>&1; then
    git init -q && echo "  git init"
fi

echo
echo "Done: $(pwd)"
command -v iverilog >/dev/null && make --no-print-directory test >/dev/null 2>&1 \
    && echo "Self-check: make test PASS" || echo "Self-check: 'make test' did not pass (tools installed?)"
echo "Next: cd $DIR && make help"
