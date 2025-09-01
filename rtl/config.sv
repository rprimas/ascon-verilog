`ifndef INCL_CONFIG
`define INCL_CONFIG

// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Configuration of the Ascon core.

// UROL: Number of Ascon-p rounds per clock cycle.
// CCW: Width of the data buses.
`ifdef V1
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 32;
`elsif V2
localparam logic [3:0] UROL = 2;
localparam unsigned CCW = 32;
`elsif V3
localparam logic [3:0] UROL = 4;
localparam unsigned CCW = 32;
`elsif V4
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 64;
`elsif V5
localparam logic [3:0] UROL = 2;
localparam unsigned CCW = 64;
`elsif V6
localparam logic [3:0] UROL = 4;
localparam unsigned CCW = 64;
`endif
`ifndef V1
`ifndef V2
`ifndef V3
`ifndef V4
`ifndef V5
`ifndef V6
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 32;
`endif
`endif
`endif
`endif
`endif
`endif

localparam logic [3:0] W64 = CCW == 32 ? 4'd2 : 4'd1;  // Number of words in 64 bits
localparam logic [3:0] W128 = CCW == 32 ? 4'd4 : 4'd2;  // Number of words in 128 bits
localparam logic [3:0] W192 = CCW == 32 ? 4'd6 : 4'd3;  // Number of words in 192 bits

// Ascon parameters
localparam unsigned LANES = 5;
localparam unsigned ROUNDS_A = 12;
localparam unsigned ROUNDS_B = 8;

localparam logic [63:0] IV_AEAD = 64'h00001000808c0001;  // Ascon-AEAD128
localparam logic [63:0] IV_HASH = 64'h0000080100cc0002;  // ASCON-Hash256
localparam logic [63:0] IV_XOF = 64'h0000080000cc0003;  // Ascon-XOF128
localparam logic [63:0] IV_CXOF = 64'h0000080000cc0004;  // Ascon-CXOF128

// Ascon modes
typedef enum logic [3:0] {
  M_NOP  = 0,
  M_ENC  = 1,
  M_DEC  = 2,
  M_HASH = 3,
  M_XOF  = 4,
  M_CXOF = 5
} mode_e;

// Interface data types
typedef enum logic [3:0] {
  D_NULL  = 0,
  D_NONCE = 1,
  D_AD    = 2, // also for customization string of CXOF
  D_MSG   = 3, // for AEAD, HASH, XOF, CXOF
  D_TAG   = 4,
  D_HASH  = 5
} data_type_e;

`endif  // INCL_CONFIG
