// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Implementation of the Ascon permutation (Ascon-p).

module asconp (
    input  logic [ 3:0] round_cnt,
    input  logic [63:0] x0_i,
    input  logic [63:0] x1_i,
    input  logic [63:0] x2_i,
    input  logic [63:0] x3_i,
    input  logic [63:0] x4_i,
    output logic [63:0] x0_o,
    output logic [63:0] x1_o,
    output logic [63:0] x2_o,
    output logic [63:0] x3_o,
    output logic [63:0] x4_o
);
  logic [63:0] x0_1, x0_2, x0_3;
  logic [63:0] x1_1, x1_2, x1_3;
  logic [63:0] x2_1, x2_2, x2_3;
  logic [63:0] x3_1, x3_2, x3_3;
  logic [63:0] x4_1, x4_2, x4_3;
  logic [3:0] t;

  // 1st affine layer
  assign t = (4'hC) - round_cnt;
  assign x0_1 = x0_i ^ x4_i;
  assign x1_1 = x1_i;
  assign x2_1 = x2_i ^ x1_i ^ {(4'hF - t), t};
  assign x3_1 = x3_i;
  assign x4_1 = x4_i ^ x3_i;

  // non-linear chi layer
  assign x0_2 = x0_1 ^ ((~x1_1) & x2_1);
  assign x1_2 = x1_1 ^ ((~x2_1) & x3_1);
  assign x2_2 = x2_1 ^ ((~x3_1) & x4_1);
  assign x3_2 = x3_1 ^ ((~x4_1) & x0_1);
  assign x4_2 = x4_1 ^ ((~x0_1) & x1_1);

  // 2nd affine layer
  assign x0_3 = x0_2 ^ x4_2;
  assign x1_3 = x1_2 ^ x0_2;
  assign x2_3 = ~x2_2;
  assign x3_3 = x3_2 ^ x2_2;
  assign x4_3 = x4_2;

  // linear layer
  assign x0_o = x0_3 ^ {x0_3[18:0], x0_3[63:19]} ^ {x0_3[27:0], x0_3[63:28]};
  assign x1_o = x1_3 ^ {x1_3[60:0], x1_3[63:61]} ^ {x1_3[38:0], x1_3[63:39]};
  assign x2_o = x2_3 ^ {x2_3[0:0], x2_3[63:01]} ^ {x2_3[05:0], x2_3[63:06]};
  assign x3_o = x3_3 ^ {x3_3[9:0], x3_3[63:10]} ^ {x3_3[16:0], x3_3[63:17]};
  assign x4_o = x4_3 ^ {x4_3[6:0], x4_3[63:07]} ^ {x4_3[40:0], x4_3[63:41]};
endmodule
