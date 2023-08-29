// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// This module contains configuration parameters for the Ascon core.

///////////
// Ascon //
///////////

parameter unsigned LANES = 5;
parameter unsigned LANE_BITS = 64;
parameter unsigned KEY_BITS = 128;
parameter logic [63:0] IV_AEAD = 64'h0000000080400c06;
parameter unsigned ROUNDS_A = 12;
parameter unsigned ROUNDS_B = 6;

///////////////
// Interface //
///////////////

// Bus width
parameter unsigned CCW = 32;
parameter unsigned CCSW = 32;

// Operation types
parameter logic [4] OP_ENC = 4'b0000;
parameter logic [4] OP_DEC = 4'b0001;
parameter logic [4] OP_HASH = 4'b0010;
parameter logic [4] OP_LD_KEY = 4'b0011;
parameter logic [4] OP_LD_NONCE = 4'b0100;
parameter logic [4] OP_LD_AD = 4'b0101;
parameter logic [4] OP_LD_MSG = 4'b0110;
parameter logic [4] OP_LD_TAG = 4'b0111;

// Interface data types
parameter logic [4] D_NULL = 4'b0000;
parameter logic [4] D_NONCE = 4'b0001;
parameter logic [4] D_AD = 4'b0010;
parameter logic [4] D_MSG = 4'b0011;
parameter logic [4] D_TAG = 4'b0100;
