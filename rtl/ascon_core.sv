// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// This module contains an implementation of Ascon-128.

module ascon_core (
    input  logic            clk,
    input  logic            rst,
    input  logic [CCSW-1:0] key,
    input  logic            key_valid,
    output logic            key_ready,
    input  logic [ CCW-1:0] bdi,
    input  logic            bdi_valid,
    output logic            bdi_ready,
    input  logic [     3:0] bdi_type,
    input  logic            bdi_eot,
    input  logic            bdi_eoi,
    input  logic            decrypt_in,
    input  logic            hash_in,
    output logic [ CCW-1:0] bdo,
    output logic            bdo_valid,
    input  logic            bdo_ready,
    output logic [     3:0] bdo_type,
    output logic            bdo_eot,
    output logic            msg_auth,
    output logic            msg_auth_valid,
    input  logic            msg_auth_ready
);

  logic [LANE_BITS/2-1:0] state       [      LANES] [2];
  logic [LANE_BITS/2-1:0] asconp_o    [      LANES] [2];
  logic [    LANE_BITS/2] ascon_key   [KEY_BITS/32];
  logic [            1:0] word_cnt;
  logic [            3:0] round_cnt;
  logic [        CCW-1:0] state_i;
  logic [        CCW-1:0] state_slice;
  logic [            3:0] state_idx;

  // Utility registers
  logic flag_ad_eot, flag_dec, flag_eoi, flag_hash, msg_auth_intern;

  // Utility signals
  assign idle_done = (fsm_state == IDLE) & (key_valid | (bdi_valid & (bdi_type == D_NONCE)));
  assign ld_key_do = (fsm_state == LOAD_KEY) & key_valid & key_ready;
  assign ld_key_done = (word_cnt == 3) & ld_key_do;
  assign ld_nonce_do = (fsm_state == LOAD_NONCE) & (bdi_type == D_NONCE) & bdi_valid & bdi_ready;
  assign ld_nonce_done = (word_cnt == 3) & ld_nonce_do;
  assign init_do = (fsm_state == INIT);
  assign init_done = (round_cnt == 1) & init_do;
  assign key_add_2_done = (fsm_state == KEY_ADD_2);

  assign abs_ad_req = (bdi_type == D_AD) & bdi_valid;
  assign abs_ad_do = (fsm_state == ABS_AD) & (bdi_type == D_AD) & bdi_valid & bdi_ready;
  assign abs_ad_done = ((word_cnt == 1) | bdi_eot) & abs_ad_do;
  assign pro_ad_do = (fsm_state == PRO_AD);
  assign pro_ad_done = (round_cnt == 1) & pro_ad_do;

  assign abs_msg_req = bdi_valid && (bdi_type == D_MSG);
  assign abs_msg_do = (fsm_state == ABS_MSG) & (bdi_type == D_MSG) & bdi_valid & bdi_ready & bdo_ready;
  assign abs_msg_done = ((word_cnt == 1) | bdi_eot) & abs_msg_do;
  assign pro_msg_do = (fsm_state == PRO_MSG);
  assign pro_msg_done = (round_cnt == 1) & pro_msg_do;

  assign final_do = (fsm_state == FINAL);
  assign final_done = (round_cnt == 1) & final_do;
  assign key_add_3_done = (fsm_state == KEY_ADD_3);

  assign sqz_tag_do = (fsm_state == SQUEEZE_TAG) & bdo_ready;
  assign sqz_tag_done = (word_cnt == 3) & sqz_tag_do;
  assign ver_tag_do = (fsm_state == VERIF_TAG) & (bdi_type == D_TAG) & bdi_valid & bdi_ready;
  assign ver_tag_done = (word_cnt == 3) & ver_tag_do;

  assign state_slice = state[state_idx/2][state_idx%2];  // Dynamic slicing

  // Finate state machine
  typedef enum {
    IDLE        = "IDLE",
    LOAD_KEY    = "LDK",
    LOAD_NONCE  = "LDN",
    INIT        = "INIT",
    KEY_ADD_2   = "KEY2",
    ABS_AD      = "ABSA",
    PRO_AD      = "PROA",
    DOM_SEP     = "DOMS",
    ABS_MSG     = "ABSM",
    PRO_MSG     = "PROM",
    KEY_ADD_3   = "KEY3",
    FINAL       = "FIN",
    KEY_ADD_4   = "KEY4",
    SQUEEZE_TAG = "STAG",
    VERIF_TAG   = "VTAG"
  } fsm_states_t;
  fsm_states_t fsm_state;
  fsm_states_t fsm_state_nxt;

  // Instantiation of Ascon-p permutation
  asconp asconp_i (
      .round_cnt(round_cnt),
      .x0_i({state[0][0], state[0][1]}),
      .x1_i({state[1][0], state[1][1]}),
      .x2_i({state[2][0], state[2][1]}),
      .x3_i({state[3][0], state[3][1]}),
      .x4_i({state[4][0], state[4][1]}),
      .x0_o({asconp_o[0][0], asconp_o[0][1]}),
      .x1_o({asconp_o[1][0], asconp_o[1][1]}),
      .x2_o({asconp_o[2][0], asconp_o[2][1]}),
      .x3_o({asconp_o[3][0], asconp_o[3][1]}),
      .x4_o({asconp_o[4][0], asconp_o[4][1]})
  );

  /////////////////////
  // Control Signals //
  /////////////////////

  always_comb begin
    state_i   = 32'h0;
    state_idx = 0;
    key_ready = 0;
    bdi_ready = 0;
    case (fsm_state)
      LOAD_KEY: key_ready = 1;
      LOAD_NONCE: begin
        bdi_ready = 1;
        state_idx = word_cnt + 6;
        state_i   = bdi;
      end
      ABS_AD: begin
        bdi_ready = 1;
        state_idx = word_cnt;
        state_i   = state_slice ^ bdi;
      end
      ABS_MSG: begin
        bdi_ready = 1;
        state_idx = word_cnt;
        if (decrypt_in) begin
          state_i = bdi;
        end else begin
          state_i = state_slice ^ bdi;
        end
      end
      SQUEEZE_TAG: state_idx = word_cnt + 6;
      VERIF_TAG: begin
        state_idx = word_cnt + 6;
        bdi_ready = 1;
      end
      default: ;
    endcase
  end

  /////////
  // BDO //
  /////////

  always_comb begin
    bdo = 0;
    bdo_valid = 0;
    bdo_type = D_NULL;
    bdo_eot = 0;
    case (fsm_state)
      ABS_MSG: begin
        if (decrypt_in) begin
          bdo = state_i ^ state_slice;
        end else begin
          bdo = state_i;
        end
        bdo_valid = 1;
        bdo_type  = D_MSG;
        bdo_eot   = bdi_eot;
      end
      SQUEEZE_TAG: begin
        bdo       = state_slice;
        bdo_valid = 1;
        bdo_type  = D_TAG;
        bdo_eot   = word_cnt == 3;
      end
      default: ;
    endcase
  end

  //////////////////////////
  // FSM Next State Logic //
  //////////////////////////

  always_comb begin
    fsm_state_nxt = fsm_state;
    if (idle_done) fsm_state_nxt = key_valid === 1 ? LOAD_KEY : LOAD_NONCE;
    if (ld_key_done) fsm_state_nxt = LOAD_NONCE;
    if (ld_nonce_done) fsm_state_nxt = INIT;
    if (init_done) fsm_state_nxt = KEY_ADD_2;
    if (fsm_state == KEY_ADD_2) fsm_state_nxt = (flag_eoi | abs_msg_req) === 1 ? DOM_SEP : ABS_AD;
    if (abs_ad_done) fsm_state_nxt = PRO_AD;
    if (pro_ad_done) fsm_state_nxt = flag_ad_eot === 1 ? DOM_SEP : ABS_AD;
    if (fsm_state == DOM_SEP) fsm_state_nxt = flag_eoi === 1 ? KEY_ADD_3 : ABS_MSG;
    if (abs_msg_done) fsm_state_nxt = bdi_eot === 1 ? KEY_ADD_3 : PRO_MSG;
    if (pro_msg_done) fsm_state_nxt = flag_eoi === 1 ? KEY_ADD_3 : ABS_MSG;
    if (fsm_state == KEY_ADD_3) fsm_state_nxt = FINAL;
    if (final_done) fsm_state_nxt = KEY_ADD_4;
    if (fsm_state == KEY_ADD_4) fsm_state_nxt = flag_dec === 1 ? VERIF_TAG : SQUEEZE_TAG;
    if (sqz_tag_done) fsm_state_nxt = IDLE;
    if (ver_tag_done) fsm_state_nxt = IDLE;
  end

  /////////////////////////
  // Ascon State Updates //
  /////////////////////////

  always @(posedge clk) begin
    if (rst == 0) begin
      if (ld_nonce_do || abs_ad_do || abs_msg_do) begin
        state[state_idx/2][state_idx%2] <= state_i;  // Dynamic slicing
      end
      // Key addition 1
      if (ld_nonce_done) begin
        state[0][0] <= IV_AEAD[31:0];
        state[0][1] <= IV_AEAD[63:32];
        for (int i = 0; i < 4; i++) state[1+i/2][i%2] <= ascon_key[i];
      end
      // Perform Ascon-p
      if (init_do || pro_ad_do || pro_msg_do || final_do) begin
        for (int i = 0; i < 10; i++) state[i/2][i%2] <= asconp_o[i/2][i%2];
      end
      // Key addition 2/4
      if (fsm_state == KEY_ADD_2 || fsm_state == KEY_ADD_4) begin
        for (int i = 0; i < 4; i++) state[3+i/2][i%2] <= state[3+i/2][i%2] ^ ascon_key[i];
      end
      // Domain separation
      if (fsm_state == DOM_SEP) begin
        state[4][1] <= state[4][1] ^ 32'h00000001;
        if (flag_eoi) state[0][0] <= state[0][0] ^ 32'h80000000;  // Padding of empty message
      end
      // Key addition 3
      if (fsm_state == KEY_ADD_3) begin
        for (int i = 0; i < 4; i++) state[1+i/2][i%2] <= state[1+i/2][i%2] ^ ascon_key[i];
      end
      // Store key
      if (ld_key_do) begin
        ascon_key[word_cnt] <= key;
      end
    end
  end

  /////////////////////
  // Counter Updates //
  /////////////////////

  always @(posedge clk) begin
    if (rst == 1) begin
      word_cnt <= 0;
    end else begin
      // Setting word counter
      if ((ld_key_do&!ld_key_done)|(ld_nonce_do&!ld_nonce_done)|abs_ad_do|abs_msg_do|sqz_tag_do|ver_tag_do) begin
        word_cnt <= word_cnt + 1;
      end
      if (ld_key_done | ld_nonce_done | abs_ad_done | abs_msg_done) begin // fix: tag
        word_cnt <= 0;
      end
      // Setting round counter
      if (ld_nonce_done | key_add_3_done) round_cnt <= ROUNDS_A;
      if (abs_ad_done | (abs_msg_done & !bdi_eot)) round_cnt <= ROUNDS_B;
      if (init_do | pro_ad_do | pro_msg_do | final_do) round_cnt <= round_cnt - 1;
    end
  end

  //////////////////
  // Flag Updates //
  //////////////////

  always @(posedge clk) begin
    if (rst == 1) begin
      flag_ad_eot <= 0;
      flag_dec <= 0;
      flag_eoi <= 0;
      flag_hash <= 0;
      msg_auth <= 0;
      msg_auth_intern <= 0;
      msg_auth_valid <= 0;
    end else begin
      if (idle_done) begin
        flag_ad_eot <= 0;
        flag_dec <= 0;
        flag_eoi <= 0;
        flag_hash <= 0;
        msg_auth <= 0;
        msg_auth_intern <= 0;
        msg_auth_valid <= 0;
      end
      if (ld_nonce_done) begin
        if (bdi_eoi) flag_eoi <= 1;
        flag_dec <= decrypt_in;
      end
      if (abs_ad_done) begin
        if (bdi_eot == 1) flag_ad_eot <= 1;
        if (bdi_eoi == 1) flag_eoi <= 1;
      end
      if (abs_msg_done) if (bdi_eoi == 1) flag_eoi <= 1;
      if ((fsm_state == KEY_ADD_4) & flag_dec) msg_auth_intern <= 1;
      if (ver_tag_do) msg_auth_intern <= msg_auth_intern & (bdi == state_slice);
      if (ver_tag_done) begin
        msg_auth_valid <= 1;
        msg_auth <= msg_auth_intern;
      end
    end
  end

  /////////////////////////////////
  // Reset and FSM State Updates //
  /////////////////////////////////

  always @(posedge clk) begin
    if (rst == 1) begin
      fsm_state <= IDLE;
      word_cnt  <= 0;
    end else begin
      fsm_state <= fsm_state_nxt;
    end
  end

  //////////////////////////////////////////////////
  // Debug Signals (can be removed for synthesis) //
  //////////////////////////////////////////////////

  logic [63:0] x0, x1, x2, x3, x4;
  assign x0 = {state[0][0], state[0][1]};
  assign x1 = {state[1][0], state[1][1]};
  assign x2 = {state[2][0], state[2][1]};
  assign x3 = {state[3][0], state[3][1]};
  assign x4 = {state[4][0], state[4][1]};

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, fsm_state, flag_ad_eot, flag_dec, flag_eoi, flag_hash, word_cnt, round_cnt, x0,
              x1, x2, x3, x4);
  end

endmodule  // ascon_core
