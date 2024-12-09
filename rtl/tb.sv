// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Test bench for controlling the Ascon core.

`timescale 1s / 100ms

module tb;

  // Test bench config
  int SIM_CYCLES = 800;

  // Test bench signals
  logic start_tb;
  logic [6:0]   byte_cnt;
  logic [31:0]  ad_byte_cnt;
  logic [31:0]  msg_byte_cnt;

  // Finite state machine
  typedef enum bit [63:0] {
    IDLE          = "IDLE",
    WR_KEY        = "WR_KEY",
    WR_NONCE      = "WR_NONCE",
    WR_AD         = "WR_AD",
    WR_MSG        = "WR_MSG",
    RD_MSG        = "RD_MSG",
    RD_TAG        = "RD_TAG",
    WR_TAG        = "WR_TAG",
    RD_HASH       = "RD_HASH",
    RD_XOF        = "RD_XOF"
  } fsm_t;
  fsm_t fsm;      // Current state
  fsm_t fsm_nx;   // Next state

  // Ascon modes
  typedef enum bit [63:0] {
    AEAD_ENC    = "AEAD_ENC",
    AEAD_DEC    = "AEAD_DEC",
    HASH        = "HASH",
    XOF         = "XOF",
    NONE        = "NONE"
  } mode_t;
  mode_t [1:0] modes = {AEAD_ENC, AEAD_DEC, HASH};//, XOF};
  mode_t mode;

  //////////////////////////
  // FSM Next State Logic //
  //////////////////////////

  always_comb begin
    fsm_nx = fsm;
    if (fsm == IDLE && start_tb) begin
      if (mode inside{AEAD_ENC, AEAD_DEC}) fsm_nx = WR_KEY;
      else fsm_nx = WR_MSG;
    end
    if ((fsm == WR_KEY)   && (byte_cnt + 4 == 16) && (key_ready)) fsm_nx = WR_NONCE;
    if ((fsm == WR_NONCE) && (byte_cnt + 4 == 16) && (bdi_ready)) begin
      if (ad_len > 'd0) fsm_nx = WR_AD;
      else if (msg_len > 'd0) fsm_nx = WR_MSG;
      else fsm_nx = RD_TAG;
    end
    if ((fsm == WR_AD) && (bdi_ready) && ((ad_byte_cnt + 'd4) == ad_len)) begin
      if (msg_len > 'd0) fsm_nx = WR_MSG;
      else fsm_nx = RD_TAG;
    end
    if ((fsm == WR_MSG) && (bdi_ready) && ((msg_byte_cnt + 'd4) == msg_len)) begin
      if (mode == AEAD_ENC) fsm_nx = RD_TAG;
      if (mode == AEAD_DEC) fsm_nx = WR_TAG;
      if (mode == HASH) fsm_nx     = RD_HASH;
      if (mode == XOF) fsm_nx      = RD_XOF;
    end
    if ((fsm == RD_TAG)   && (byte_cnt == 12) && (bdo_valid)) fsm_nx = IDLE;
    if ((fsm == WR_TAG)   && (byte_cnt == 12) && (bdi_ready)) fsm_nx = IDLE;
  end

  //////////////////////
  // FSM State Update //
  //////////////////////

  always @(posedge clk) begin
    if (rst == 1) begin
      fsm <= IDLE;
    end else begin
      fsm <= fsm_nx;
    end
  end

  //////////////////////
  // Counter Update //
  //////////////////////

  always @(posedge clk) begin
    if (rst == 1) begin
      byte_cnt <= '0;
    end else begin
      if ((fsm inside {WR_KEY}) && (key_ready)) byte_cnt <= byte_cnt + 'd4;
      if ((fsm inside {WR_NONCE}) && (bdi_ready)) byte_cnt <= byte_cnt + 'd4;
      if ((fsm inside {WR_AD}) && (bdi_ready)) begin
        byte_cnt <= (byte_cnt + 'd4) % 16;
        ad_byte_cnt <= ad_byte_cnt + 'd4;
      end
      if ((fsm inside {WR_MSG}) && (bdi_ready)) begin
        byte_cnt <= (byte_cnt + 'd4) % 16;
        msg_byte_cnt <= msg_byte_cnt + 'd4;
      end
      if ((fsm == RD_TAG) && (bdo_valid)) begin
        byte_cnt <= (byte_cnt + 'd4) % 16;
      end
      if ((fsm == WR_TAG) && (bdi_ready)) begin
        byte_cnt <= (byte_cnt + 'd4) % 16;
      end
      if (fsm_nx == IDLE) begin
        ad_byte_cnt <= 'd0;
        msg_byte_cnt <= 'd0;
      end
      if (fsm_nx != fsm) byte_cnt <= 'd0;
    end
  end

  // Set interface signals
  always_comb begin
    key             = '0;
    key_valid       = '0;
    bdi             = '0;
    bdi_type        = D_NULL;
    bdi_eoi         = '0;
    bdi_valid_bytes = {4{fsm inside {WR_NONCE, WR_AD, WR_MSG, WR_TAG}}};
    bdo_ready       = '0;
    decrypt         = mode == AEAD_DEC;
    hash            = mode inside {HASH, XOF};
    bdi_valid = (fsm inside {WR_NONCE, WR_AD, WR_MSG, WR_TAG});
    bdo_ready = (fsm inside {WR_MSG, RD_TAG, RD_HASH, RD_XOF});
    bdi_eot   = (fsm inside {WR_NONCE, WR_AD, WR_MSG}) && (fsm_nx != fsm);
    if (fsm == WR_KEY) begin
      key_valid = 'd1;
      key       = tb_key[byte_cnt*8+:'d32];
    end
    if (fsm == WR_NONCE) begin
      bdi         = tb_nonce[byte_cnt*8+:'d32];
      bdi_type    = D_NONCE;
      if ((ad_len == 'd0) && (msg_len == 'd0)) begin
        bdi_eoi   = fsm_nx != fsm;
      end
    end
    if (fsm == WR_AD) begin
      bdi_type    = D_AD;
      bdi         = {ad_byte_cnt[7:0]+8'd3, ad_byte_cnt[7:0]+8'd2, ad_byte_cnt[7:0]+8'd1, ad_byte_cnt[7:0]};
      if (msg_len == 'd0) begin
        bdi_eoi   = fsm_nx != fsm;
      end
    end
    if (fsm == WR_MSG) begin
      bdi_type  = D_MSG;
      bdi       = tb_msg[msg_byte_cnt*8+:'d32];
      if (mode == AEAD_DEC) bdi = tb_ct[msg_byte_cnt*8+:'d32];
      bdi_eoi   = fsm_nx != fsm;
    end
    if (fsm == WR_TAG) begin
      bdi_type   = D_TAG;
      bdi        = tb_tag[byte_cnt*8+:'d32];
    end
  end

  // Print message output from Ascon core
  always @(posedge clk) begin
    if (bdo_valid) begin
      if (bdo_type == D_PTCT) begin
        if (decrypt) $display("msg  => %h", bdo);
        else $display("ct   => %h", bdo);
      end
      if (bdo_type == D_TAG) $display("tag  => %h", bdo);
      if (bdo_type == D_HASH) $display("hash => %h", bdo);
    end
  end

  // Print tag verification output from Ascon core
  always @(posedge auth_valid) begin
    $display("auth => %h", auth);
  end

  // Interface signals
  logic             clk = 1;
  logic             rst = 0;
  logic  [CCSW-1:0] key;
  logic             key_valid;
  logic             key_ready;
  logic  [ CCW-1:0] bdi;
  logic             bdi_valid;
  logic             bdi_ready;
  logic  [     3:0] bdi_type;
  logic             bdi_eot;
  logic             bdi_eoi;
  logic             decrypt;
  logic             hash;
  logic  [ CCW-1:0] bdo;
  logic             bdo_valid;
  logic             bdo_ready;
  logic  [     3:0] bdo_type;
  logic             bdo_eot;
  logic  [     3:0] bdi_valid_bytes;
  logic             auth;
  logic             auth_valid;
  logic             auth_ready;
  logic             done;

  // Instatiate Ascon core
  ascon_core ascon_core_i (
      .clk(clk),
      .rst(rst),
      .key(key),
      .key_valid(key_valid),
      .key_ready(key_ready),
      .bdi(bdi),
      .bdi_valid(bdi_valid),
      .bdi_valid_bytes(bdi_valid_bytes),
      .bdi_ready(bdi_ready),
      .bdi_type(bdi_type),
      .bdi_eot(bdi_eot),
      .bdi_eoi(bdi_eoi),
      .decrypt(decrypt),
      .hash(hash),
      .bdo(bdo),
      .bdo_valid(bdo_valid),
      .bdo_ready(bdo_ready),
      .bdo_type(bdo_type),
      .bdo_eot(bdo_eot),
      .auth(auth),
      .auth_valid(auth_valid),
      .done(done)
  );

  // Generate clock signal
  always #5 clk = !clk;

  `include "rtl/tv.sv"

  logic [31:0] ad_len     = $size(tb_ad)/'d8;
  logic [31:0] msg_len    = $size(tb_msg)/'d8;

  // Specify debug variables and set simulation start/finish
  initial begin
    $dumpfile("wave.fst");
    $dumpvars(0, clk);
    clk = 1;
    rst = 0;
    #10;
    rst = 1;
    #10;
    rst = 0;
    foreach (modes[i]) begin
      mode = modes[i];
      start_tb = 1;
      #10;
      start_tb = 0;
      #100;
      wait(done);
      #10;
    end
    $finish;
  end

endmodule  // tb
