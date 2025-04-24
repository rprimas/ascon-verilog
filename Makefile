# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
EXTRA_ARGS += --trace

# The following variants require "CCW = 32" in test.py:
# EXTRA_ARGS += -DV1
# EXTRA_ARGS += -DV2
# EXTRA_ARGS += -DV3

# The following variants require "CCW = 64" in test.py:
EXTRA_ARGS += -DV4
# EXTRA_ARGS += -DV5
# EXTRA_ARGS += -DV6

VERILOG_SOURCES += $(PWD)/rtl/ascon_core.sv

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = ascon_core

# MODULE is the basename of the Python test file
MODULE = test

# Include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

surf:
	surfer -s surfer.ron dump.vcd
