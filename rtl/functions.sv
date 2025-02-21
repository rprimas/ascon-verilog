// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Generic functions for the Ascon core.

// Swap byte order of bit vector:
// in:   [0x00, 0x01, 0x02, 0x03]
// =>
// swap: [0x03, 0x02, 0x01, 0x00]
function static logic [CCW-1:0] swap(logic [CCW-1:0] in);
  for (int i = 0; i < CCWD8; i += 1) begin
    swap[(i*8)+:8] = in[((CCWD8-i-1)*8)+:8];
  end
endfunction

// Pad input during ABS_AD, ABS_MSG (encryption):
// in:  [0x00, 0x00, 0x11, 0x22]
// val: [   0,    0,    1,    1]
// =>
// pad: [0x00, 0x01, 0x11, 0x22]
function static logic [CCW-1:0] pad(logic [CCW-1:0] in, logic [CCWD8-1:0] val);
  pad[7:0] = val[0] ? in[7:0] : 'd0;
  for (int i = 1; i < CCWD8; i += 1) begin
    pad[i*8+:8] = val[i] ? in[i*8+:8] : val[i-1] ? 'd1 : 'd0;
  end
endfunction

// Pad input during ABS_MSG (decryption):
// in1:  [0x00, 0x11, 0x22, 0x33]
// in2:  [0x44, 0x55, 0x66, 0x77]
// val:  [   0,    0,    1,    1]
// =>
// pad2: [0x44, 0x54, 0x22, 0x33]
function static logic [CCW-1:0] pad2(logic [CCW-1:0] in1, logic [CCW-1:0] in2,
                                     logic [CCWD8-1:0] val);
  pad2[7:0] = val[0] ? in1[7:0] : in2[7:0];
  for (int i = 1; i < CCWD8; i += 1) begin
    pad2[i*8+:8] = val[i] ? in1[i*8+:8] : (val[i-1] ? 'd1 ^ in2[i*8+:8] : in2[i*8+:8]);
  end
endfunction

function static int lanny(logic [7:0] word_idx);
  lanny = (CCW == 64) ? int'(word_idx) / 'd2 : int'(word_idx);
endfunction

function static int wordy(int word_idx);
  wordy = (CCW == 64) ? 'd0 : int'(word_idx) % 'd2;
endfunction
