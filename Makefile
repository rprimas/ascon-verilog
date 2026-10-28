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

# TOPLEVEL is the name of the toplevel verilog module
TOPLEVEL = ascon_core

# MODULE is the basename of the cocotb test file
MODULE = test

# Set source and config files for cocotb, yosys, and surfer
SURFER_RON = surfer/sim.ron
FILE_LIST = file_list.txt
ifeq ($(cell),simple)
SURFER_RON = surfer/syn.ron
FILE_LIST = syn/file_list_syn.txt
endif

# Verilator arguments
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
EXTRA_ARGS += --threads 4
# EXTRA_ARGS += --trace
# EXTRA_ARGS += --trace-fst
# EXTRA_ARGS += --trace-threads 2
EXTRA_ARGS += -Wno-UNOPTFLAT
EXTRA_ARGS += -D$(VARIANT)
EXTRA_ARGS += -f $(FILE_LIST)

# Include cocotb makefile
include $(shell cocotb-config --makefiles)/Makefile.sim

syn:
	yosys -p "plugin -i slang; read_slang -D${VARIANT} --single-unit --top ascon_core --dir-prefix rtl -F./file_list.txt; synth -top ascon_core; dfflibmap -liberty syn/simple_cells.lib; abc -liberty syn/simple_cells.lib; clean; write_verilog syn.v; stat -liberty syn/simple_cells.lib"

surf:
	surfer -s $(SURFER_RON) dump.fst

clean::
	rm -rf syn.v results.xml

.PHONY: syn surf clean
