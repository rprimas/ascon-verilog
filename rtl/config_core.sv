// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Configuration parameters for the Ascon core.

`ifdef V1
`define CCW32
parameter logic [3:0] UROL = 1;
parameter unsigned CCW = 32;
`elsif V2
`define CCW32
parameter logic [3:0] UROL = 2;
parameter unsigned CCW = 32;
`elsif V3
`define CCW32
parameter logic [3:0] UROL = 4;
parameter unsigned CCW = 32;
`elsif V4
`define CCW64
parameter logic [3:0] UROL = 1;
parameter unsigned CCW = 64;
`elsif V5
`define CCW64
parameter logic [3:0] UROL = 2;
parameter unsigned CCW = 64;
`elsif V6
`define CCW64
parameter logic [3:0] UROL = 4;
parameter unsigned CCW = 64;
`endif

///////////
// Ascon //
///////////

parameter unsigned LANES = 5;
parameter unsigned LANE_BITS = 64;
parameter unsigned KEY_BITS = 128;

// ///////////////////
// // Ascon-AEAD128 //
// ///////////////////

parameter logic [63:0] IV_AEAD = 64'h00001000808c0001;
parameter unsigned ROUNDS_A = 12;
parameter unsigned ROUNDS_B = 8;
parameter unsigned RATE_AEAD_BITS = 128;
parameter unsigned RATE_AEAD_WORDS = RATE_AEAD_BITS / 32;

// ///////////////////
// // ASCON-Hash256 //
// ///////////////////

parameter logic [63:0] IV_HASH = 64'h0000080100cc0002;
parameter unsigned RATE_HASH_BITS = 64;
parameter unsigned RATE_HASH_WORDS = RATE_HASH_BITS / 32;

///////////////
// Interface //
///////////////

// Mode types
typedef enum logic [3:0] {
  M_NOP  = 0,
  M_ENC  = 1,
  M_DEC  = 2,
  M_HASH = 3
} mode_e;

// Interface data types
parameter logic [3:0] D_NULL = 4'h0;
parameter logic [3:0] D_NONCE = 4'h1;
parameter logic [3:0] D_AD = 4'h2;
parameter logic [3:0] D_PTCT = 4'h3;
parameter logic [3:0] D_MSG = 4'h3;
parameter logic [3:0] D_TAG = 4'h4;
parameter logic [3:0] D_HASH = 4'h5;
