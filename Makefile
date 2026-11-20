# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

MAKEFLAGS=-j4

# Variants for the Ascon core implementation:
# - V1: ccw=32, 1 rounds/cycle
# - V2: ccw=32, 2 rounds/cycle
# - V3: ccw=32, 4 rounds/cycle
# - V4: ccw=64, 1 rounds/cycle
# - V5: ccw=64, 2 rounds/cycle
# - V6: ccw=64, 4 rounds/cycle
VARIANT ?= V1
VARIANT_DIR := $(shell printf '%s' '$(VARIANT)' | tr '[:upper:]' '[:lower:]')
VARIANT_DEFINE := $(shell printf '%s' '$(VARIANT_DIR)' | tr '[:lower:]' '[:upper:]')

# TOPLEVEL is the name of the toplevel verilog module
TOPLEVEL = ascon_core

# MODULE is the basename of the cocotb test file
MODULE = test

# Set source and config files for cocotb, yosys, and surfer
SURFER_RON = surfer/sim.ron
SYN_NETLIST = builds/net/$(VARIANT_DIR)/syn.v
SIM_MODE = rtl
ifeq ($(cell),simple)
SURFER_RON = surfer/syn.ron
SIM_MODE = simple
NETLIST_SOURCES = syn/simple_cells.v $(SYN_NETLIST)
CUSTOM_COMPILE_DEPS += $(NETLIST_SOURCES)
EXTRA_ARGS += $(NETLIST_SOURCES)
else
CUSTOM_COMPILE_DEPS += file_list.txt $(shell cat file_list.txt)
EXTRA_ARGS += -f file_list.txt
endif
TRACE ?= 0
SIM_BUILD ?= builds/sim/$(VARIANT_DIR)$(if $(filter 1,$(TRACE)),-$(SIM_MODE)-trace,$(if $(filter simple,$(SIM_MODE)),-simple))
COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml

# Verilator arguments
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
EXTRA_ARGS += --threads 4
ifeq ($(TRACE),1)
EXTRA_ARGS += --trace
EXTRA_ARGS += --trace-fst
EXTRA_ARGS += --trace-threads 2
SIM_ARGS += --trace-file $(SIM_BUILD)/dump.fst
endif
EXTRA_ARGS += -Wno-UNOPTFLAT
EXTRA_ARGS += -D$(VARIANT_DEFINE)

# Include cocotb makefile
include $(shell cocotb-config --makefiles)/Makefile.sim

syn: $(SYN_NETLIST)

$(SYN_NETLIST): Makefile file_list.txt $(shell cat file_list.txt) syn/simple_cells.lib
	mkdir -p $(@D)
	yosys -p "plugin -i slang; read_slang -D$(VARIANT_DEFINE) --single-unit --top ascon_core --dir-prefix rtl -F./file_list.txt; synth -top ascon_core; dfflibmap -liberty syn/simple_cells.lib; abc -liberty syn/simple_cells.lib; clean; write_verilog $@; stat -liberty syn/simple_cells.lib"

dump surf: override TRACE = 1

dump:
	$(MAKE) sim TRACE=1 VARIANT=$(VARIANT) $(if $(cell),cell=$(cell)) $(if $(COCOTB_TEST_FILTER),COCOTB_TEST_FILTER=$(COCOTB_TEST_FILTER))

surf: dump
	cd $(SIM_BUILD) && surfer -s $(abspath $(SURFER_RON)) dump.fst

clean::
	rm -rf builds sim_build syn.v results.xml dump.fst

.PHONY: syn dump surf clean
