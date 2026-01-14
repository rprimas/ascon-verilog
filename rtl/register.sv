`ifndef INCL_REGISTER
`define INCL_REGISTER

// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Generic register module.

module register #(parameter DATA_WIDTH, parameter RST_VALUE = DATA_WIDTH'('d0)) (
  clk,
  rst,
  data_d, // input
  data_q  // output
);

  input logic clk;
  input logic rst;
  input  logic[DATA_WIDTH-1:0] data_d;
  output logic[DATA_WIDTH-1:0] data_q;

  always_ff @(posedge clk, posedge rst) begin : register_update
    if (rst) begin
      data_q <= RST_VALUE;
    end else begin
      data_q <= data_d;
    end
  end

endmodule

`endif  // INCL_REGISTER
