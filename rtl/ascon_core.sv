`ifndef INCL_ASCON_CORE
`define INCL_ASCON_CORE

// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Implementation of the Ascon core.

`include "asconp.sv"
`include "config.sv"
`include "functions.sv"

module ascon_core (
    input  logic                   clk,
    input  logic                   rst,
    input  logic       [  CCW-1:0] key,
    input  logic                   key_valid,
    output logic                   key_ready,
    input  logic       [  CCW-1:0] bdi,
    input  logic       [CCW/8-1:0] bdi_valid,
    output logic                   bdi_ready,
    input  e_data_type             bdi_type,
    input  logic                   bdi_eot,
    input  logic                   bdi_eoi,
    input  e_mode                  mode,
    output logic       [  CCW-1:0] bdo,
    output logic                   bdo_valid,
    input  logic                   bdo_ready,
    output e_data_type             bdo_type,
    output logic                   bdo_eot,
    input  logic                   bdo_eoo,
    output logic                   auth,
    output logic                   auth_valid,
    output logic                   done
);
  // Core registers
  logic [LANES-1:0][W64-1:0][CCW-1:0] state;
  logic [ W128-1:0][CCW-1:0]          ascon_key;
  logic [      3:0]                   round_cnt;
  logic [      3:0]                   word_cnt;
  logic [      1:0]                   hash_cnt;
  logic flag_ad_eot, flag_ad_pad, flag_msg_pad, flag_eoi, auth_intern;
  e_mode mode_r;

  // FSM states
  typedef enum logic [4:0] {
    IDLE     = 'd1,
    LD_KEY   = 'd2,
    LD_NPUB  = 'd3,
    INIT     = 'd4,
    KADD_2   = 'd5,
    ABS_AD   = 'd6,
    PAD_AD   = 'd7,
    PRO_AD   = 'd8,
    DOM_SEP  = 'd9,
    ABS_MSG  = 'd10,
    PAD_MSG  = 'd11,
    PRO_MSG  = 'd12,
    KADD_3   = 'd13,
    FINAL    = 'd14,
    KADD_4   = 'd15,
    SQZ_TAG  = 'd16,
    SQZ_HASH = 'd17,
    VER_TAG  = 'd18
  } fsms_t;
  fsms_t fsm;  // Current state
  fsms_t fsm_nx;  // Next state

  // Event signals
  logic last_abs_blk;
  logic add_ad_pad, add_msg_pad;

  logic mode_enc_dec, mode_hash_xof;
  assign mode_enc_dec  = (mode_r == M_ENC) || (mode_r == M_DEC);
  assign mode_hash_xof = (mode_r == M_HASH) || (mode_r == M_XOF) || (mode_r == M_CXOF);

  logic idle_done, ld_key, ld_key_done, ld_npub, ld_npub_done, init, init_done, kadd_2_done;
  assign idle_done    = (fsm == IDLE) && (mode > 'd0);
  assign ld_key       = (fsm == LD_KEY) && key_valid && key_ready;
  assign ld_key_done  = ld_key && (word_cnt == (W128 - 1));
  assign ld_npub      = (fsm == LD_NPUB) && (bdi_type == D_NONCE) && (bdi_valid > 'd0) && bdi_ready;
  assign ld_npub_done = ld_npub && (word_cnt == (W128 - 1));
  assign init         = (fsm == INIT);
  assign init_done    = init && (round_cnt == UROL);
  assign kadd_2_done  = (fsm == KADD_2) && (flag_eoi || (bdi_valid > 'd0));

  logic abs_ad, abs_ad_done, pro_ad, pro_ad_done;
  assign abs_ad      = (fsm == ABS_AD) && (bdi_type == D_AD) && (bdi_valid > 'd0) && bdi_ready;
  assign abs_ad_done = abs_ad && (last_abs_blk || bdi_eot);
  assign pro_ad      = (fsm == PRO_AD);
  assign pro_ad_done = pro_ad && (round_cnt == UROL);

  logic dom_sep_done;
  assign dom_sep_done = (fsm == DOM_SEP);

  logic abs_msg_part, abs_msg, abs_msg_done, pro_msg, pro_msg_done;
  assign abs_msg_part = (fsm == ABS_MSG) && (bdi_type == D_MSG) && (bdi_valid != 'd0) && bdi_ready;
  assign abs_msg      = abs_msg_part && ((bdo_valid && bdo_ready) || !mode_enc_dec);
  assign abs_msg_done = abs_msg && (last_abs_blk || bdi_eot);
  assign pro_msg      = (fsm == PRO_MSG);
  assign pro_msg_done = (round_cnt == UROL) && pro_msg;

  logic kadd_3_done, fin, fin_done, kadd_4_done;
  assign kadd_3_done = (fsm == KADD_3);
  assign fin         = (fsm == FINAL);
  assign fin_done    = (round_cnt == UROL) && fin;
  assign kadd_4_done = (fsm == KADD_4);

  logic sqz_hash, sqz_hash_done1, sqz_hash_done2, sqz_tag, sqz_tag_done, ver_tag, ver_tag_done;
  assign sqz_hash       = (fsm == SQZ_HASH) && bdo_valid && bdo_ready;
  assign sqz_hash_done1 = (word_cnt == (W64 - 1)) && sqz_hash;
  assign sqz_hash_done2 = ((hash_cnt == 'd3) && sqz_hash_done1) || (sqz_hash && bdo_eoo);
  assign sqz_tag        = (fsm == SQZ_TAG) && bdo_valid && bdo_ready;
  assign sqz_tag_done   = (word_cnt == (W128 - 1)) && sqz_tag;
  assign ver_tag        = (fsm == VER_TAG) && (bdi_type == D_TAG) && bdi_ready;
  assign ver_tag_done   = (word_cnt == (W128 - 1)) && ver_tag;

  assign last_abs_blk =
    (abs_ad  && mode_enc_dec     && (word_cnt == (W128 - 1))) ||
    (abs_ad  && (mode_r==M_CXOF) && (word_cnt == ( W64 - 1))) ||
    (abs_msg && mode_enc_dec     && (word_cnt == (W128 - 1))) ||
    (abs_msg && mode_hash_xof    && (word_cnt == ( W64 - 1)));

  assign add_ad_pad = (fsm == PAD_AD) || (abs_ad && (bdi_valid != '1));
  assign add_msg_pad = (fsm == PAD_MSG) || (dom_sep_done && flag_eoi) || (abs_msg && (bdi_valid != '1));

  // Utility signals
  logic [3:0] state_idx, lane_idx, word_idx;
  logic [CCW-1:0] state_nx, state_slice, bdi_pad;

  assign word_idx = (CCW == 64) ? 'd0 : state_idx % 2;
  assign lane_idx = (CCW == 64) ? state_idx : state_idx / 2;
  assign state_slice = state[int'(lane_idx)][int'(word_idx)];

  logic [LANES-1:0][W64-1:0][CCW-1:0] asconp_o;

  // Instantiation of Ascon-p permutation
  asconp asconp_i (
      .round_cnt(round_cnt),
      .x0_i(state[0]),
      .x1_i(state[1]),
      .x2_i(state[2]),
      .x3_i(state[3]),
      .x4_i(state[4]),
      .x0_o(asconp_o[0]),
      .x1_o(asconp_o[1]),
      .x2_o(asconp_o[2]),
      .x3_o(asconp_o[3]),
      .x4_o(asconp_o[4])
  );

  /////////////////////
  // Control Signals //
  /////////////////////

  always_comb begin
    state_nx  = 'd0;
    state_idx = 'd0;
    key_ready = 'd0;
    bdi_ready = 'd0;
    bdo       = 'd0;
    bdo_valid = 'd0;
    bdo_type  = D_NULL;
    bdo_eot   = 'd0;
    bdi_pad   = 'd0;
    unique case (fsm)
      LD_KEY:  key_ready = 'd1;
      LD_NPUB: begin
        state_idx = word_cnt + W192;
        bdi_ready = 'd1;
        state_nx  = bdi;
      end
      ABS_AD: begin
        state_idx = word_cnt;
        bdi_ready = 'd1;
        bdi_pad   = pad(bdi, bdi_valid);
        state_nx  = state_slice ^ bdi_pad;
      end
      PAD_AD, PAD_MSG: begin
        state_idx = word_cnt;
      end
      ABS_MSG: begin
        state_idx = word_cnt;
        if (mode_r == M_ENC || mode_hash_xof) begin
          bdi_pad = pad(bdi, bdi_valid);
          state_nx = state_slice ^ bdi_pad;
          bdo = state_nx;
        end else if (mode_r == M_DEC) begin
          bdi_pad = pad2(bdi, state_slice, bdi_valid);
          state_nx = bdi_pad;
          bdo = state_slice ^ state_nx;
        end
        bdi_ready = 'd1;
        bdo_valid = mode_enc_dec ? 'd1 : 'd0;
        bdo_type  = mode_enc_dec ? D_MSG : D_NULL;
        bdo_eot   = mode_enc_dec ? bdi_eot : 'd0;
        if (mode_r == M_HASH) bdo = 'd0;
      end
      SQZ_TAG: begin
        state_idx = word_cnt + W192;
        bdo       = swap(state_slice);
        bdo_valid = 'd1;
        bdo_type  = D_TAG;
        bdo_eot   = word_cnt == (W128 - 1);
      end
      SQZ_HASH: begin
        state_idx = word_cnt;
        bdo       = swap(state_slice);
        bdo_valid = 'd1;
        bdo_type  = D_HASH;
        bdo_eot   = (hash_cnt == 'd3) && (word_cnt == (W64 - 1));
      end
      VER_TAG: begin
        state_idx = word_cnt + W192;
        bdi_ready = 'd1;
      end
      default: ;
    endcase
  end

  //////////////////////////
  // FSM Next State Logic //
  //////////////////////////

  always_comb begin
    fsm_nx = fsm;
    // Initialize:
    if (idle_done) begin
      if (mode == M_ENC || mode == M_DEC) fsm_nx = key_valid ? LD_KEY : LD_NPUB;
      if (mode == M_HASH || mode == M_XOF || mode == M_CXOF) fsm_nx = INIT;
    end
    if (ld_key_done) fsm_nx = LD_NPUB;
    if (ld_npub_done) fsm_nx = INIT;
    if (init_done) begin
      if (mode_enc_dec) fsm_nx = KADD_2;
      if (mode_r == M_HASH || mode_r == M_XOF) fsm_nx = flag_eoi ? PAD_MSG : ABS_MSG;
      if (mode_r == M_CXOF) fsm_nx = ABS_AD;
    end
    if (kadd_2_done) begin
      if (flag_eoi) fsm_nx = DOM_SEP;
      else if (bdi_type == D_AD) fsm_nx = ABS_AD;
      else if (bdi_type == D_MSG) fsm_nx = DOM_SEP;
    end
    // Process:
    // - AEAD: associated data
    // - CXOF: customization string
    if (abs_ad_done) begin
      if (bdi_valid != '1) begin
        fsm_nx = PRO_AD;
      end else begin
        if ((word_cnt != (W128 - 1)) && mode_enc_dec) fsm_nx = PAD_AD;
        else if ((word_cnt != (W64 - 1)) && mode_hash_xof) fsm_nx = PAD_AD;
        else fsm_nx = PRO_AD;
      end
    end
    if (fsm == PAD_AD) fsm_nx = PRO_AD;
    if (pro_ad_done) begin
      begin
        if (flag_ad_eot == 0) begin
          fsm_nx = ABS_AD;
        end else if (flag_ad_pad == 0) begin
          fsm_nx = PAD_AD;
        end else begin
          if (mode_enc_dec) fsm_nx = DOM_SEP;
          else if (mode_r == M_CXOF) begin
            fsm_nx = flag_ad_eot ? (flag_eoi ? PAD_MSG : ABS_MSG) : ABS_MSG;
          end
        end
      end
    end
    if (dom_sep_done) fsm_nx = flag_eoi ? KADD_3 : ABS_MSG;
    // Process:
    // - AEAD           : plaintext or ciphertext
    // - HASH, XOF, CXOF: message
    if (abs_msg_done) begin
      if (bdi_valid != '1) begin
        if (mode_hash_xof) fsm_nx = FINAL;
        else fsm_nx = KADD_3;
      end else begin
        if (mode_enc_dec && (word_cnt != (W128 - 1))) fsm_nx = PAD_MSG;
        else if ((word_cnt != (W64 - 1)) && mode_hash_xof) fsm_nx = PAD_MSG;
        else fsm_nx = PRO_MSG;
      end
    end
    if (fsm == PAD_MSG) begin
      if (mode_hash_xof) fsm_nx = FINAL;
      else fsm_nx = KADD_3;
    end
    if (pro_msg_done) begin
      if (flag_eoi == 0) begin
        fsm_nx = ABS_MSG;
      end else if (flag_msg_pad == 0) begin
        fsm_nx = PAD_MSG;
      end
    end
    if (kadd_3_done) fsm_nx = FINAL;
    if (fin_done) begin
      if (mode_r == M_HASH) fsm_nx = SQZ_HASH;
      else if (mode_r == M_XOF || mode_r == M_CXOF) begin
        fsm_nx = SQZ_HASH;
      end else fsm_nx = KADD_4;
    end
    // Finalize:
    // - AEAD           : Squeeze or verify tag
    // - HASH, XOF, CXOF: Squeeze hash
    if (kadd_4_done) fsm_nx = (mode_r == M_DEC) ? VER_TAG : SQZ_TAG;
    if (sqz_hash_done1) fsm_nx = FINAL;
    if (sqz_hash_done2) fsm_nx = IDLE;
    if (sqz_tag_done) fsm_nx = IDLE;
    if (ver_tag_done) fsm_nx = IDLE;
  end

  //////////////////////
  // FSM State Update //
  //////////////////////

  always_ff @(posedge clk) begin
    if (rst) begin
      fsm <= IDLE;
    end else begin
      fsm <= fsm_nx;
    end
  end

  /////////////////////////
  // Ascon State Updates //
  /////////////////////////

  always_ff @(posedge clk) begin
    if (rst == 0) begin
      // Absorb padded input
      if (ld_npub || abs_ad || abs_msg) begin
        state[int'(lane_idx)][int'(word_idx)] <= state_nx;
      end
      // Absorb padding word
      if (fsm == PAD_AD || fsm == PAD_MSG) begin
        state[int'(lane_idx)][int'(word_idx)] <= state_slice ^ 'd1;
      end
      // State initialization: HASH, XOF, CXOF
      if (idle_done && (mode == M_HASH || mode == M_XOF || mode == M_CXOF)) begin
        state <= '0;
        unique case (mode)
          M_HASH:  state[0] <= IV_HASH[0+:64];
          M_XOF:   state[0] <= IV_XOF[0+:64];
          M_CXOF:  state[0] <= IV_CXOF[0+:64];
          default: ;
        endcase
      end
      // State initialization: AEAD
      // - "npub" is written to state during LOAD_NPUB
      if (ld_npub_done) begin
        state[0] <= IV_AEAD[0+:64];
        state[1] <= ascon_key[0+:W64];
        state[2] <= ascon_key[W64+:W64];
      end
      // Perform Ascon-p permutation
      if (init || pro_ad || pro_msg || fin) begin
        state <= asconp_o;
      end
      // Key addition 2/4
      if (kadd_2_done || kadd_4_done) begin
        state[3] <= state[3] ^ ascon_key[0+:W64];
        state[4] <= state[4] ^ ascon_key[W64+:W64];
      end
      // Domain separation
      if (dom_sep_done) begin
        state[4] <= state[4] ^ 64'h8000000000000000;
        if (flag_eoi) state[0] <= state[0] ^ 'd1;  // Pad empty message
      end
      // Key addition 3
      if (kadd_3_done) begin
        state[2] <= state[2] ^ ascon_key[0+:W64];
        state[3] <= state[3] ^ ascon_key[W64+:W64];
      end
      // Store key
      if (ld_key) begin
        ascon_key[word_cnt[(64/CCW)-1:0]] <= key;
      end
    end
  end

  /////////////////////
  // Counter Updates //
  /////////////////////

  always_ff @(posedge clk) begin
    if (rst) begin
      word_cnt <= 'd0;
    end else begin
      // Setting word counter
      if (ld_key || ld_npub || abs_ad || abs_msg || sqz_tag || sqz_hash || ver_tag) begin
        word_cnt <= word_cnt + 'd1;
      end
      if (ld_key_done || ld_npub_done || sqz_tag_done || sqz_hash_done1 || ver_tag_done) begin
        word_cnt <= 'd0;
      end
      if (abs_ad_done || abs_msg_done) begin
        if ((fsm_nx == PAD_AD) || (fsm_nx == PAD_MSG)) begin
          word_cnt <= word_cnt + 'd1;
        end else begin
          word_cnt <= 'd0;
        end
      end
      if (fsm == PAD_AD) word_cnt <= 'd0;
      if (fsm == PAD_MSG) word_cnt <= 'd0;
      // Setting hash block counter
      if (mode_r == M_HASH) begin
        if (sqz_hash_done1) hash_cnt <= hash_cnt + 'd1;
        if (abs_ad_done && bdi_eoi) hash_cnt <= 'd0;
      end
      // Setting round counter
      unique case (fsm_nx)
        INIT:    round_cnt <= ROUNDS_A;
        PRO_AD:  round_cnt <= (mode_r==M_CXOF) ? ROUNDS_A : ROUNDS_B;
        PRO_MSG: round_cnt <= mode_hash_xof ? ROUNDS_A : ROUNDS_B;
        FINAL:   round_cnt <= ROUNDS_A;
        default:;
      endcase
      if (init || pro_ad || pro_msg || fin) round_cnt <= round_cnt - UROL;
    end
  end

  //////////////////
  // Flag Updates //
  //////////////////

  always_ff @(posedge clk) begin
    if (rst) begin
      done <= 'd0;
    end else begin
      if (idle_done) begin
        auth         <= 'd0;
        auth_intern  <= 'd0;
        auth_valid   <= 'd0;
        flag_ad_eot  <= 'd0;
        flag_ad_pad  <= 'd0;
        flag_eoi     <= bdi_eoi;
        flag_msg_pad <= 'd0;
        done         <= 'd0;
        mode_r       <= mode;
      end
      if (ld_npub_done) begin
        if (bdi_eoi) flag_eoi <= 'd1;
      end
      if (abs_ad_done) begin
        if (bdi_eot) flag_ad_eot <= 'd1;
        if (bdi_eoi) flag_eoi <= 'd1;
      end
      if (add_ad_pad) flag_ad_pad <= 'd1;
      if (abs_msg_done && bdi_eoi) flag_eoi <= 'd1;
      if (add_msg_pad) flag_ad_pad <= 'd1;
      if (kadd_4_done && (mode_r == M_DEC)) auth_intern <= 'd1;
      if (ver_tag) auth_intern <= auth_intern && (bdi == state_slice);
      if (ver_tag_done) begin
        auth_valid <= 'd1;
        auth <= auth_intern;
      end
      if ((fsm != IDLE) && (fsm_nx == IDLE)) done <= 'd1;
    end
  end

  //////////////////////////////////////////////////
  // Debug Signals (can be removed for synthesis) //
  //////////////////////////////////////////////////

  logic [63:0] x0, x1, x2, x3, x4;
  assign x0 = state[0];
  assign x1 = state[1];
  assign x2 = state[2];
  assign x3 = state[3];
  assign x4 = state[4];

endmodule

`endif  // INCL_ASCON_CORE
