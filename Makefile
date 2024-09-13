# Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
# for details.
#
# Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
#
# Makefile for running verilog test bench and optionally viewing wave forms
# in GTKWave.

SRC = rtl/config_core.sv rtl/tb.sv rtl/ascon_core.sv rtl/asconp.sv

VARGS = --binary -j 8 --trace-fst --top-module tb # Generate FST waveforms
# VARGS = --binary -j 8 --trace --top-module tb # Generate VCD waveforms

GTKARGS = -6

v1:
	verilator $(VARGS) rtl/config_v1.sv $(SRC)
	./obj_dir/Vtb

v2:
	verilator $(VARGS) rtl/config_v2.sv $(SRC)
	./obj_dir/Vtb

v3:
	verilator $(VARGS) rtl/config_v3.sv $(SRC)
	./obj_dir/Vtb

v4:
	verilator $(VARGS) rtl/config_v4.sv $(SRC)
	./obj_dir/Vtb

v1_wave: v1
	gtkwave ./tb.vcd config.gtkw $(GTKARGS)

v2_wave: v2
	gtkwave ./tb.vcd config.gtkw $(GTKARGS)

v3_wave: v3
	gtkwave ./tb.vcd config.gtkw $(GTKARGS)

v4_wave: v4
	gtkwave ./tb.vcd config.gtkw $(GTKARGS)

.PHONY: clean
clean:
	rm -f -r tb tb.vcd obj_dir/
