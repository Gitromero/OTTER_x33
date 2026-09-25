# OTTER simulation / lint flow (Icarus Verilog, Verilator, GTKWave)
#   make test    - run the full RV32I Test_All program, reports PASS/FAIL
#   make sim     - run a program (PROG=<name> from mem/), writes build/otter.vcd
#   make fuzz    - random programs vs. a Python reference model (N=<count>)
#   make wave    - open the waveform in GTKWave
#   make lint    - Verilator lint of the design
#   make clean
# Options: PROG=<mem/NAME.mem> CYCLES=<n> SWITCHES=<hex> VERBOSE=1

TOP      ?= OTTER_Wrapper
PROG     ?= Test_All
CYCLES   ?= 2000
SWITCHES ?= 0000
TEST_ALL_COUNT := 37

PKG   := rtl/core/otter_pkg.sv
SRCS  := $(PKG) $(filter-out $(PKG),$(wildcard rtl/core/*.sv rtl/memory/*.sv rtl/io/*.sv))
TB    := sim/tb_$(TOP).sv
BUILD := build
VVP   := $(BUILD)/$(PROG).vvp

SIM_ARGS = +CYCLES=$(CYCLES) +SWITCHES=$(SWITCHES) $(if $(VERBOSE),+VERBOSE)

.PHONY: sim test fuzz wave lint clean

$(VVP): $(SRCS) $(TB) mem/$(PROG).mem | $(BUILD)
	iverilog -g2012 -Wno-timescale -DMEM_FILE='"mem/$(PROG).mem"' \
		-s tb_$(TOP) -o $@ $(SRCS) $(TB)

sim: $(VVP)
	vvp -n $< $(SIM_ARGS)

test: CYCLES = 200000
test: $(VVP)
	vvp -n $< $(SIM_ARGS) +PASS_COUNT=$(TEST_ALL_COUNT) | tail -5

fuzz:
	python3 scripts/fuzz.py -n $(or $(N),200)

wave:
	gtkwave $(BUILD)/otter.vcd &

lint:
	verilator --lint-only -Wall -Wno-fatal -DMEM_FILE='"mem/Test_All.mem"' \
		--top-module $(TOP) $(SRCS)

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
