# OTTER simulation / lint flow (Icarus Verilog, Verilator, GTKWave). `make help` lists targets.
# Options: PROG=<mem/NAME.mem> CYCLES=<n> SWITCHES=<hex> VERBOSE=1 WAVE_FMT=fst|vcd|none

TOP      ?= OTTER_Wrapper
PROG     ?= Test_All
CYCLES   ?= 2000
SWITCHES ?= 0000
WAVE_FMT ?= fst
TEST_ALL_COUNT := 37

PKG   := rtl/core/otter_pkg.sv
SRCS  := $(PKG) $(filter-out $(PKG),$(wildcard rtl/core/*.sv rtl/memory/*.sv rtl/io/*.sv))
TB    := sim/tb_$(TOP).sv sim/otter_probe.sv
BUILD := build
VVP   := $(BUILD)/$(PROG).vvp
WAVE  := $(BUILD)/otter.$(WAVE_FMT)
GTKW  := sim/otter.gtkw

IVERILOG := iverilog -g2012 -Wno-timescale
# Icarus prints a harmless "sorry: constant selects in always_*" per such line
QUIET    := 2>&1 | { grep -v 'sorry: constant selects' || true; }
SHELL    := /bin/bash -o pipefail

WAVE_ARGS = $(if $(filter none,$(WAVE_FMT)),+NOWAVE,+WAVE=$(WAVE) $(if $(filter fst,$(WAVE_FMT)),-fst))
SIM_ARGS  = +CYCLES=$(CYCLES) +SWITCHES=$(SWITCHES) $(if $(VERBOSE),+VERBOSE)

.PHONY: help sim test fuzz wave lint asm dis iss unit units unit-wave check-env clean

help:
	@echo "Simulation"
	@echo "  make test                  full Test_All program, PASS/FAIL"
	@echo "  make sim PROG=<name>       run mem/<name>.mem (built from asm/<name>.s if present)"
	@echo "  make wave                  open the last waveform in GTKWave (pipeline layout)"
	@echo "  make fuzz [N=200]          random programs vs. the Python reference model"
	@echo "  make unit T=<Module>       run sim/unit/tb_<Module>.sv;  make units = all of them"
	@echo "  make unit-wave T=<Module>  open that unit test's waveform"
	@echo "Programs"
	@echo "  make asm PROG=<name>       asm/<name>.s -> mem/<name>.mem"
	@echo "  make dis PROG=<name>       disassemble mem/<name>.mem"
	@echo "  make iss PROG=<name>       run on the reference ISS, print registers"
	@echo "Other"
	@echo "  make lint                  Verilator lint"
	@echo "  make check-env             check the tools are installed"
	@echo "  make clean"
	@echo "Options: CYCLES=<n> SWITCHES=<hex> VERBOSE=1 WAVE_FMT=fst|vcd|none"

#---- CPU simulation ---------------------------------------------------------------
$(VVP): $(SRCS) $(TB) mem/$(PROG).mem | $(BUILD)
	$(IVERILOG) -DMEM_FILE='"mem/$(PROG).mem"' -s tb_$(TOP) -o $@ $(SRCS) $(TB) $(QUIET)

sim: $(VVP)
	vvp -n $< $(WAVE_ARGS) $(SIM_ARGS)

test: CYCLES = 200000
test: $(VVP)
	vvp -n $< $(WAVE_ARGS) $(SIM_ARGS) +PASS_COUNT=$(TEST_ALL_COUNT) | tail -5

fuzz:
	python3 scripts/fuzz.py -n $(or $(N),200)

wave:
	@test -f $(WAVE) || { echo "no $(WAVE); run 'make sim' or 'make test' first"; exit 1; }
	gtkwave $(WAVE) $(GTKW) >/dev/null 2>&1 &

#---- Programs ---------------------------------------------------------------------
# mem/<name>.mem is rebuilt whenever asm/<name>.s is newer
mem/%.mem: asm/%.s scripts/rv32i.py
	python3 scripts/rv32i.py asm $< -o $@

asm: mem/$(PROG).mem

dis: mem/$(PROG).mem
	python3 scripts/rv32i.py dis $<

iss: mem/$(PROG).mem
	python3 scripts/rv32i.py run $< --switches $(SWITCHES)

#---- Unit tests (sim/unit/tb_<Module>.sv) ----------------------------------------
UNIT_TBS := $(wildcard sim/unit/tb_*.sv)

unit:
	@test -n "$(T)" || { echo "usage: make unit T=<Module>  (have: $(patsubst sim/unit/tb_%.sv,%,$(UNIT_TBS)))"; exit 1; }
	@mkdir -p $(BUILD)
	$(IVERILOG) -DMEM_FILE='"mem/Test_All.mem"' -s tb_$(T) -o $(BUILD)/tb_$(T).vvp \
		$(SRCS) sim/unit/tb_$(T).sv $(QUIET)
	vvp -n $(BUILD)/tb_$(T).vvp +WAVE=$(BUILD)/tb_$(T).fst -fst | tee $(BUILD)/tb_$(T).log
	@! grep -q '^FAIL' $(BUILD)/tb_$(T).log

units:
	@fail=0; for t in $(patsubst sim/unit/tb_%.sv,%,$(UNIT_TBS)); do \
		$(MAKE) --no-print-directory unit T=$$t >/dev/null 2>&1; \
		grep -E '^(PASS|FAIL)' $(BUILD)/tb_$$t.log | tail -1 || { echo "FAIL: tb_$$t (no result)"; fail=1; }; \
		grep -q '^FAIL' $(BUILD)/tb_$$t.log && fail=1; done; exit $$fail

unit-wave:
	gtkwave $(BUILD)/tb_$(T).fst $(wildcard sim/unit/tb_$(T).gtkw) >/dev/null 2>&1 &

#---- Misc -------------------------------------------------------------------------
lint:
	verilator --lint-only -Wall -Wno-fatal -DMEM_FILE='"mem/Test_All.mem"' \
		--top-module $(TOP) $(SRCS)

check-env:
	@for t in iverilog vvp verilator gtkwave python3; do \
		printf '%-10s ' $$t; command -v $$t >/dev/null && echo ok || echo MISSING; done
	@iverilog -V 2>&1 | head -1; verilator --version

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
