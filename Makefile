# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

MAKEFLAGS=-j8

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
EXTRA_ARGS += --threads 8
EXTRA_ARGS += --trace
EXTRA_ARGS += -Wno-UNOPTFLAT

# The following variants require "CCW = 32" in test.py:
EXTRA_ARGS += -DV1
# EXTRA_ARGS += -DV2
# EXTRA_ARGS += -DV3

# The following variants require "CCW = 64" in test.py:
# EXTRA_ARGS += -DV4
# EXTRA_ARGS += -DV5
# EXTRA_ARGS += -DV6

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = ascon_core

# MODULE is the basename of the Python test file
MODULE = test

ifeq (1,$(synth))
SURER_CONFIG = surf_synth.ron
VERILOG_SOURCES = $(PWD)/cmos_cells.v $(PWD)/synth.v
else
SURER_CONFIG = surf.ron
VERILOG_SOURCES = $(PWD)/rtl/ascon_core.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

synth:
	yosys synth.ys

surf:
	surfer -s $(SURER_CONFIG) dump.vcd

clean::
	rm -rf synth.v results.xml
