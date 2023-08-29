# Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE for details.
#
# Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
#
# Makefile for running verilog testbench and optionally viewing wave forms in GTKWave.

all:
	iverilog -g2012 -o tb rtl/tb.sv rtl/ascon_core.sv rtl/asconp.sv
	vvp tb

wave: all
	gtkwave tb.vcd config.gtkw -6 --rcvar 'fontname_signals Source Code Pro 10' --rcvar 'fontname_waves Source Code Pro 10'

.PHONY: clean
clean:
	rm -f KAT_tmp.txt tb tb.vcd

