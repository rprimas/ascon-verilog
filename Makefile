# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

MAKEFLAGS=-j8

VARIANT ?= V1 # ccw=32, 1 round/cycle
# VARIANT ?= V2 # ccw=32, 2 rounds/cycle
# VARIANT ?= V3 # ccw=32, 4 rounds/cycle
# VARIANT ?= V4 # ccw=64, 1 round/cycle
# VARIANT ?= V5 # ccw=64, 2 rounds/cycle
# VARIANT ?= V6 # ccw=64, 4 rounds/cycle

# Verilator arguments
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
EXTRA_ARGS += --threads 8
# EXTRA_ARGS += --trace
# EXTRA_ARGS += --trace-fst
# EXTRA_ARGS += --trace-threads 2
EXTRA_ARGS += --relative-includes
EXTRA_ARGS += -Wno-UNOPTFLAT
EXTRA_ARGS += -D$(VARIANT)

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = ascon_core

# MODULE is the basename of the Python test file
MODULE = test

# Set source and config files for cocotb, yosys, and surfer
VERILOG_SOURCES = $(PWD)/rtl/ascon_core.sv
SURFER_RON = surfer/sim.ron
ifeq ($(MAKECMDGOALS),syn)
ifeq ($(cell),)
cell = simple
endif
endif
ifeq ($(cell),simple)
YS_SCRIPT = syn/syn.ys
VERILOG_SOURCES = $(PWD)/syn/simple_cells.v $(PWD)/syn.v
SURFER_RON = surfer/syn.ron
endif

# Include cocotb makefile
include $(shell cocotb-config --makefiles)/Makefile.sim

syn:
	yosys -D${VARIANT} ${YS_SCRIPT}

surf:
	surfer -s $(SURFER_RON) dump.fst

clean::
	rm -rf syn.v results.xml

.PHONY: syn
