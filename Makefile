# Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
# for details.
#
# Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
#
# Makefile for running verilog test bench and optionally viewing wave forms
# in GTKWave.

all: v1

v1:
	iverilog -g2012 -o tb rtl/config_v1.sv rtl/config_core.sv rtl/tb.sv rtl/ascon_core.sv rtl/asconp.sv
	vvp tb

v2:
	iverilog -g2012 -o tb rtl/config_v2.sv rtl/config_core.sv rtl/tb.sv rtl/ascon_core.sv rtl/asconp.sv
	vvp tb

v3:
	iverilog -g2012 -o tb rtl/config_v3.sv rtl/config_core.sv rtl/tb.sv rtl/ascon_core.sv rtl/asconp.sv
	vvp tb

v4:
	iverilog -g2012 -o tb rtl/config_v4.sv rtl/config_core.sv rtl/tb.sv rtl/ascon_core.sv rtl/asconp.sv
	vvp tb

wave: v1_wave

v1_wave: v1
	gtkwave tb.vcd config.gtkw -6 --rcvar 'fontname_signals Source Code Pro 10' --rcvar 'fontname_waves Source Code Pro 10'

v2_wave: v2
	gtkwave tb.vcd config.gtkw -6 --rcvar 'fontname_signals Source Code Pro 10' --rcvar 'fontname_waves Source Code Pro 10'

v3_wave: v3
	gtkwave tb.vcd config.gtkw -6 --rcvar 'fontname_signals Source Code Pro 10' --rcvar 'fontname_waves Source Code Pro 10'

v4_wave: v4
	gtkwave tb.vcd config.gtkw -6 --rcvar 'fontname_signals Source Code Pro 10' --rcvar 'fontname_waves Source Code Pro 10'

.PHONY: clean
clean:
	rm -f tb tb.vcd
