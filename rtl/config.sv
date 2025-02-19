// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Configuration parameters for the Ascon core.

// UROL: Number of Ascon-p rounds per clock cycle.
// CCW: Width of the data buses.
`ifdef V1
parameter logic [3:0] UROL = 1;
parameter unsigned CCW = 32;
`elsif V2
parameter logic [3:0] UROL = 2;
parameter unsigned CCW = 32;
`elsif V3
parameter logic [3:0] UROL = 4;
parameter unsigned CCW = 32;
`elsif V4
parameter logic [3:0] UROL = 1;
parameter unsigned CCW = 64;
`elsif V5
parameter logic [3:0] UROL = 2;
parameter unsigned CCW = 64;
`elsif V6
parameter logic [3:0] UROL = 4;
parameter unsigned CCW = 64;
`endif
parameter unsigned CCWD8 =  CCW / 8;  // Number of bytes in one word
parameter unsigned W64 =   64 / CCW;  // Number of words in 64 bits
parameter unsigned W128 = 128 / CCW;  // Number of words in 128 bits
parameter unsigned W192 = 192 / CCW;  // Number of words in 192 bits

// Ascon parameter
parameter unsigned LANES    = 5;
parameter unsigned ROUNDS_A = 12;
parameter unsigned ROUNDS_B = 8;

parameter logic [63:0] IV_AEAD = 64'h00001000808c0001;  // Ascon-AEAD128
parameter logic [63:0] IV_HASH = 64'h0000080100cc0002;  // ASCON-Hash256
parameter logic [63:0] IV_XOF =  64'h0000080000cc0003;  // Ascon-XOF128
parameter logic [63:0] IV_CXOF = 64'h0000080000cc0004;  // Ascon-CXOF128

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
} data_e;
