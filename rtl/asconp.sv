`ifndef INCL_ASCONP
`define INCL_ASCONP

// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Implementation of the Ascon permutation (Ascon-p).
// Performs UROL rounds per clock cycle.

`include "rtl/config.sv"

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

  logic [UROL-1:0][63:0] x0_aff1, x0_chi, x0_aff2;
  logic [UROL-1:0][63:0] x1_aff1, x1_chi, x1_aff2;
  logic [UROL-1:0][63:0] x2_aff1, x2_chi, x2_aff2;
  logic [UROL-1:0][63:0] x3_aff1, x3_chi, x3_aff2;
  logic [UROL-1:0][63:0] x4_aff1, x4_chi, x4_aff2;
  logic [UROL : 0][63:0] x0, x1, x2, x3, x4;
  logic [UROL-1:0][3:0] t;

  assign x0[0] = x0_i;
  assign x1[0] = x1_i;
  assign x2[0] = x2_i;
  assign x3[0] = x3_i;
  assign x4[0] = x4_i;

  genvar i;
  generate
    for (i = 0; i < UROL; i++) begin : g_asconp
      // 1st affine layer
      assign t[i] = (4'hC) - (round_cnt - i);
      assign x0_aff1[i] = x0[i] ^ x4[i];
      assign x1_aff1[i] = x1[i];
      assign x2_aff1[i] = x2[i] ^ x1[i] ^ {56'd0, (4'hF - t[i]), t[i]};
      assign x3_aff1[i] = x3[i];
      assign x4_aff1[i] = x4[i] ^ x3[i];
      // non-linear chi layer
      assign x0_chi[i] = x0_aff1[i] ^ ((~x1_aff1[i]) & x2_aff1[i]);
      assign x1_chi[i] = x1_aff1[i] ^ ((~x2_aff1[i]) & x3_aff1[i]);
      assign x2_chi[i] = x2_aff1[i] ^ ((~x3_aff1[i]) & x4_aff1[i]);
      assign x3_chi[i] = x3_aff1[i] ^ ((~x4_aff1[i]) & x0_aff1[i]);
      assign x4_chi[i] = x4_aff1[i] ^ ((~x0_aff1[i]) & x1_aff1[i]);
      // 2nd affine layer
      assign x0_aff2[i] = x0_chi[i] ^ x4_chi[i];
      assign x1_aff2[i] = x1_chi[i] ^ x0_chi[i];
      assign x2_aff2[i] = ~x2_chi[i];
      assign x3_aff2[i] = x3_chi[i] ^ x2_chi[i];
      assign x4_aff2[i] = x4_chi[i];
      // linear layer
      assign x0[i+1] = x0_aff2[i] ^ {x0_aff2[i][18:0], x0_aff2[i][63:19]} ^ {x0_aff2[i][27:0], x0_aff2[i][63:28]};
      assign x1[i+1] = x1_aff2[i] ^ {x1_aff2[i][60:0], x1_aff2[i][63:61]} ^ {x1_aff2[i][38:0], x1_aff2[i][63:39]};
      assign x2[i+1] = x2_aff2[i] ^ {x2_aff2[i][0:0], x2_aff2[i][63:01]} ^ {x2_aff2[i][05:0], x2_aff2[i][63:06]};
      assign x3[i+1] = x3_aff2[i] ^ {x3_aff2[i][9:0], x3_aff2[i][63:10]} ^ {x3_aff2[i][16:0], x3_aff2[i][63:17]};
      assign x4[i+1] = x4_aff2[i] ^ {x4_aff2[i][6:0], x4_aff2[i][63:07]} ^ {x4_aff2[i][40:0], x4_aff2[i][63:41]};
    end
  endgenerate

  assign x0_o = x0[UROL];
  assign x1_o = x1[UROL];
  assign x2_o = x2[UROL];
  assign x3_o = x3[UROL];
  assign x4_o = x4[UROL];

endmodule

`endif  // INCL_ASCONP
