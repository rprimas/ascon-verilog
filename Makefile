# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

MAKEFLAGS=-j8

# The following variants require "CCW = 32" in test.py:
VARIANT = V1
# VARIANT = V2
# VARIANT = V3

# The following variants require "CCW = 64" in test.py:
# VARIANT = V4
# VARIANT = V5
# VARIANT = V6

# Verilator arguments
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
EXTRA_ARGS += --threads 8
EXTRA_ARGS += --trace
EXTRA_ARGS += -Wno-UNOPTFLAT
EXTRA_ARGS += -D$(VARIANT)

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = ascon_core

# MODULE is the basename of the Python test file
MODULE = test

# Set source and config files
ifeq (1,$(synth))
SURFER_RON = surfer/synth.ron
VERILOG_SOURCES = $(PWD)/synth/cmos_cells.v $(PWD)/synth.v
else
SURFER_RON = surfer/sim.ron
VERILOG_SOURCES = $(PWD)/rtl/ascon_core.sv
endif

# Include cocotb makefile
include $(shell cocotb-config --makefiles)/Makefile.sim

synth:
	yosys -D${VARIANT} synth/synth.ys

surf:
	surfer -s $(SURFER_RON) dump.vcd

clean::
	rm -rf synth.v results.xml

.PHONY: synth
