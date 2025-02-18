// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Implementation of the Ascon core.

module ascon_core (
    input  logic             clk,
    input  logic             rst,
    input  logic [  CCW-1:0] key,
    input  logic             key_valid,
    output logic             key_ready,
    input  logic [  CCW-1:0] bdi,
    input  logic [CCWD8-1:0] bdi_valid,
    output logic             bdi_ready,
    input  logic [      3:0] bdi_type,
    input  logic             bdi_eot,
    input  logic             bdi_eoi,
    input  logic [      3:0] mode,
    output logic [  CCW-1:0] bdo,
    output logic             bdo_valid,
    input  logic             bdo_ready,
    output logic [      3:0] bdo_type,
    output logic             bdo_eot,
    input  logic             bdo_eoo,
    output logic             auth,
    output logic             auth_valid,
    output logic             done
);

  // Swap byte order of bit vector:
  // in:   [0x00, 0x01, 0x02, 0x03]
  // =>
  // swap: [0x03, 0x02, 0x01, 0x00]
  function static logic [CCW-1:0] swap(logic [CCW-1:0] in);
    begin
      for (int i = 0; i < CCWD8; i += 1) begin
        swap[(i*8)+:8] = in[((CCWD8-i-1)*8)+:8];
      end
    end
  endfunction

  // Pad input during ABS_AD, ABS_MSG (encryption):
  // in:  [0x00, 0x00, 0x11, 0x22]
  // val: [   0,    0,    1,    1]
  // =>
  // pad: [0x00, 0x01, 0x11, 0x22]
  function static logic [CCW-1:0] pad(logic [CCW-1:0] in, logic [CCWD8-1:0] val);
    begin
      pad[7:0] = val[0] ? in[7:0] : 'd0;
      for (int i = 1; i < CCWD8; i += 1) begin
        pad[i*8+:8] = val[i] ? in[i*8+:8] : val[i-1] ? 'd1 : 'd0;
      end
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
    begin
      pad2[7:0] = val[0] ? in1[7:0] : in2[7:0];
      for (int i = 1; i < CCWD8; i += 1) begin
        pad2[i*8+:8] = val[i] ? in1[i*8+:8] : (val[i-1] ? 'd1 ^ in2[i*8+:8] : in2[i*8+:8]);
      end
    end
  endfunction

  function static int lanny(logic [7:0] word_idx);
    begin
      lanny = (CCW == 32) ? int'(word_idx) : int'(word_idx) / 2;
    end
  endfunction

  function static int wordy(logic [7:0] word_idx);
    begin
      wordy = (CCW == 32) ? int'(word_idx) % 2 : 0;
    end
  endfunction

  typedef logic [63:0] log64_t;

  // Core registers
  logic [CCW-1:0] state     [LANES] [W64];
  logic [CCW-1:0] ascon_key [ W128];
  logic [    3:0] round_cnt;
  logic [    7:0] word_cnt;
  logic [    1:0] hash_cnt;
  logic flag_ad_eot, flag_ad_pad, flag_msg_pad, flag_eoi, flag_eoo, auth_intern;
  logic [3:0] mode_r;

  // Utility signals
  logic idle_done, ld_key, ld_key_done, ld_npub, ld_npub_done, init, init_done, kadd_2_done;
  assign idle_done    = (fsm == IDLE) & (mode > 'd0);
  assign ld_key       = (fsm == LD_KEY) & key_valid & key_ready;
  assign ld_key_done  = (word_cnt == (W128 - 1)) & ld_key;
  assign ld_npub      = (fsm == LD_NPUB) & (bdi_type == D_NONCE) & (bdi_valid > 'd0) & bdi_ready;
  assign ld_npub_done = (word_cnt == (W128 - 1)) & ld_npub;
  assign init         = (fsm == INIT);
  assign init_done    = (round_cnt == UROL) & init;
  assign kadd_2_done  = (fsm == KADD_2) & (flag_eoi | (bdi_valid > 'd0));  // todo

  logic abs_ad, abs_ad_done, pro_ad, pro_ad_done;
  assign abs_ad = (fsm == ABS_AD) & (bdi_type == D_AD) & (bdi_valid > 'd0) & bdi_ready;
  assign abs_ad_done = ((word_cnt == ((mode_r inside {M_ENC, M_DEC}) ? (W128 - 1) : (W64 - 1))) | bdi_eot) & abs_ad;
  // assign abs_ad_done = ((word_cnt == (W128 - 1)) | bdi_eot) & abs_ad;
  assign pro_ad = (fsm == PRO_AD);
  assign pro_ad_done = (round_cnt == UROL) & pro_ad;

  logic abs_msg, abs_msg_done, pro_msg, pro_msg_done;
  assign abs_msg      = (fsm == ABS_MSG) & (bdi_type == D_MSG) & (bdi_valid>'d0) & bdi_ready & ((mode_r inside {M_ENC, M_DEC}) ? bdo_ready : 1);
  assign abs_msg_done = ((word_cnt == ((mode_r inside {M_ENC, M_DEC}) ? (W128 - 1) : (W64 - 1))) | bdi_eot) & abs_msg;
  assign pro_msg = (fsm == PRO_MSG);
  assign pro_msg_done = (round_cnt == UROL) & pro_msg;

  logic fin, fin_done;
  assign fin      = (fsm == FINAL);
  assign fin_done = (round_cnt == UROL) & fin;

  logic sqz_hash, sqz_hash_done1, sqz_hash_done2, sqz_tag, sqz_tag_done, ver_tag, ver_tag_done;
  assign sqz_hash = (fsm == SQZ_HASH) & bdo_ready;
  assign sqz_hash_done1 = (word_cnt == (W64 - 1)) & sqz_hash;
  assign sqz_hash_done2 = (mode_r == M_HASH) ? ((hash_cnt == 'd3) & sqz_hash_done1) : sqz_hash & bdo_eoo;
  assign sqz_tag = (fsm == SQZ_TAG) & bdo_ready;
  assign sqz_tag_done = (word_cnt == (W128 - 1)) & sqz_tag;
  assign ver_tag = (fsm == VER_TAG) & (bdi_type == D_TAG) & (bdi_valid > 'd0) & bdi_ready;
  assign ver_tag_done = (word_cnt == (W128 - 1)) & ver_tag;

  logic [    7:0] state_idx;
  logic [CCW-1:0] asconp_o    [LANES][W64];
  logic [CCW-1:0] state_i;
  logic [CCW-1:0] state_slice;

  logic [7:0] lane_idx, word_idx;
  assign lane_idx = (CCW == 64) ? state_idx : state_idx / 2;
  assign word_idx = (CCW == 64) ? 'd0 : state_idx % 2;

  // Padded bdi data
  logic [CCW-1:0] paddy;

  // Dynamic slicing
  assign state_slice = state[int'(lane_idx)][int'(word_idx)];

  // Finite state machine
  typedef enum logic [63:0] {
    IDLE     = "IDLE",
    LD_KEY   = "LD_KEY",
    LD_NPUB  = "LD_NPUB",
    INIT     = "INIT",
    KADD_2   = "KADD_2",
    ABS_AD   = "ABS_AD",
    PAD_AD   = "PAD_AD",
    PRO_AD   = "PRO_AD",
    DOM_SEP  = "DOM_SEP",
    ABS_MSG  = "ABS_MSG",
    PAD_MSG  = "PAD_MSG",
    PRO_MSG  = "PRO_MSG",
    KADD_3   = "KADD_3",
    FINAL    = "FINAL",
    KADD_4   = "KADD_4",
    SQZ_TAG  = "SQZ_TAG",
    SQZ_HASH = "SQZ_HASH",
    VER_TAG  = "VER_TAG"
  } fsms_t;
  fsms_t fsm;  // Current state
  fsms_t fsm_nx;  // Next state

  // Instantiation of Ascon-p permutation
  generate
    if (CCW == 32) begin : g_asconp_32
      asconp asconp_i (
          .round_cnt(round_cnt),
          .x0_i({state[0][1], state[0][0]}),
          .x1_i({state[1][1], state[1][0]}),
          .x2_i({state[2][1], state[2][0]}),
          .x3_i({state[3][1], state[3][0]}),
          .x4_i({state[4][1], state[4][0]}),
          .x0_o({asconp_o[0][1], asconp_o[0][0]}),
          .x1_o({asconp_o[1][1], asconp_o[1][0]}),
          .x2_o({asconp_o[2][1], asconp_o[2][0]}),
          .x3_o({asconp_o[3][1], asconp_o[3][0]}),
          .x4_o({asconp_o[4][1], asconp_o[4][0]})
      );
    end
    if (CCW == 64) begin : g_asconp_64
      asconp asconp_i (
          .round_cnt(round_cnt),
          .x0_i(state[0][0]),
          .x1_i(state[1][0]),
          .x2_i(state[2][0]),
          .x3_i(state[3][0]),
          .x4_i(state[4][0]),
          .x0_o(asconp_o[0][0]),
          .x1_o(asconp_o[1][0]),
          .x2_o(asconp_o[2][0]),
          .x3_o(asconp_o[3][0]),
          .x4_o(asconp_o[4][0])
      );
    end
  endgenerate

  /////////////////////
  // Control Signals //
  /////////////////////

  always_comb begin
    state_i   = 'd0;
    state_idx = 'd0;
    key_ready = 'd0;
    bdi_ready = 'd0;
    bdo       = 'd0;
    bdo_valid = 'd0;
    bdo_type  = D_NULL;
    bdo_eot   = 'd0;
    paddy     = 'd0;
    case (fsm)
      LD_KEY:  key_ready = 'd1;
      LD_NPUB: begin
        state_idx = word_cnt + W192;
        bdi_ready = 'd1;
        state_i   = bdi;
      end
      ABS_AD: begin
        state_idx = word_cnt;
        bdi_ready = 'd1;
        paddy = pad(bdi, bdi_valid);
        state_i = state_slice ^ paddy;
      end
      PAD_AD, PAD_MSG: begin
        state_idx = word_cnt;
      end
      ABS_MSG: begin
        state_idx = word_cnt;
        if (mode_r inside {M_ENC, M_HASH, M_XOF, M_CXOF}) begin
          paddy = pad(bdi, bdi_valid);
          state_i = state_slice ^ paddy;
          bdo = state_i;
        end else if (mode_r inside {M_DEC}) begin
          paddy = pad2(bdi, state_slice, bdi_valid);
          state_i = paddy;
          bdo = state_slice ^ state_i;
        end
        bdi_ready = 'd1;
        bdo_valid = (mode_r inside {M_ENC, M_DEC}) ? 'd1 : 'd0;
        bdo_type  = (mode_r inside {M_ENC, M_DEC}) ? D_MSG : D_NULL;
        bdo_eot   = (mode_r inside {M_ENC, M_DEC}) ? bdi_eot : 'd0;
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
        bdo_eot   = (hash_cnt == 'd3) & (word_cnt == (W64 - 1));
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
    if (idle_done) begin
      if (mode inside {M_ENC, M_DEC}) fsm_nx = key_valid ? LD_KEY : LD_NPUB;
      if (mode inside {M_HASH, M_XOF, M_CXOF}) fsm_nx = INIT;
    end
    if (ld_key_done) fsm_nx = LD_NPUB;
    if (ld_npub_done) fsm_nx = INIT;
    if (init_done) begin
      if (mode_r inside {M_ENC, M_DEC}) fsm_nx = KADD_2;
      if (mode_r inside {M_HASH, M_XOF}) fsm_nx = flag_eoi ? PAD_MSG : ABS_MSG;
      if (mode_r inside {M_CXOF}) fsm_nx = ABS_AD;
      // fsm_nx = (mode_r inside {M_HASH, M_XOF}) ? (flag_eoi ? PAD_MSG : ABS_MSG) : KADD_2;
    end
    if (kadd_2_done) begin
      if (flag_eoi) fsm_nx = DOM_SEP;
      else if (bdi_type == D_AD) fsm_nx = ABS_AD;
      else if (bdi_type == D_MSG) fsm_nx = DOM_SEP;
    end
    if (abs_ad_done) begin
      if (bdi_valid != '1) begin
        fsm_nx = PRO_AD;
      end else begin
        // if (word_cnt < (W128 - 1)) fsm_nx = PAD_AD;
        if ((word_cnt != (W128 - 1)) && (mode_r inside {M_ENC, M_DEC})) fsm_nx = PAD_AD;
        else if ((word_cnt != (W64 - 1)) && (mode_r inside {M_HASH, M_XOF, M_CXOF})) fsm_nx = PAD_AD;
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
          if (mode_r inside {M_ENC, M_DEC}) fsm_nx = DOM_SEP;
          else if (mode_r == M_CXOF) begin
            fsm_nx = flag_ad_eot ? (flag_eoi ? PAD_MSG : ABS_MSG) : ABS_MSG;
          end
        end
      end
    end
    if (fsm == DOM_SEP) fsm_nx = flag_eoi ? KADD_3 : ABS_MSG;
    if (abs_msg_done) begin
      if (bdi_valid != '1) begin
        if (mode_r inside {M_HASH, M_XOF, M_CXOF}) fsm_nx = FINAL;
        else fsm_nx = KADD_3;
      end else begin
        if ((word_cnt != (W128 - 1)) && (mode_r inside {M_ENC, M_DEC})) fsm_nx = PAD_MSG;
        else if ((word_cnt != (W64 - 1)) && (mode_r inside {M_HASH, M_XOF, M_CXOF})) fsm_nx = PAD_MSG;
        else fsm_nx = PRO_MSG;
      end
    end
    if (fsm == PAD_MSG) begin
      if (mode_r inside {M_HASH, M_XOF, M_CXOF}) fsm_nx = FINAL;
      else fsm_nx = KADD_3;
    end
    if (pro_msg_done) begin
      if (flag_eoi == 0) begin
        fsm_nx = ABS_MSG;
      end else if (flag_msg_pad == 0) begin
        fsm_nx = PAD_MSG;
      end
    end
    if (fsm == KADD_3) fsm_nx = FINAL;
    if (fin_done) begin
      if (mode_r == M_HASH) fsm_nx = SQZ_HASH;
      else if (mode_r inside {M_XOF, M_CXOF}) begin
        if (bdo_ready) fsm_nx = SQZ_HASH;
        else fsm_nx = IDLE; // todo
      end else fsm_nx = KADD_4;
    end
    if (fsm == KADD_4) fsm_nx = (mode_r inside {M_DEC}) ? VER_TAG : SQZ_TAG;
    if (sqz_hash_done1) fsm_nx = FINAL;
    if (sqz_hash_done2) fsm_nx = IDLE;
    if (sqz_tag_done) fsm_nx = IDLE;
    if (ver_tag_done) fsm_nx = IDLE;
  end

  //////////////////////
  // FSM State Update //
  //////////////////////

  always @(posedge clk) begin
    if (rst) begin
      fsm <= IDLE;
    end else begin
      fsm <= fsm_nx;
    end
  end

  /////////////////////////
  // Ascon State Updates //
  /////////////////////////

  always @(posedge clk) begin
    if (rst == 0) begin
      // Absorb padded input
      if (ld_npub || abs_ad || abs_msg) begin
        state[int'(lane_idx)][int'(word_idx)] <= state_i;
      end
      // Add 32-bit block of padding
      if (fsm inside {PAD_AD, PAD_MSG}) begin
        state[int'(lane_idx)][int'(word_idx)] ^= 'd1;
        flag_ad_pad  <= fsm == PAD_AD;
        flag_msg_pad <= fsm == PAD_MSG;
      end
      // State initialization, hashing
      if (idle_done & (mode inside {M_HASH, M_XOF, M_CXOF})) begin
        for (int i = 1; i < 5; i++) state[i] <= '{default: '0};
        if (mode == M_HASH) begin
          state[0][lanny(0)] <= IV_HASH[0+:CCW];
          if (CCW == 32) state[0][lanny(1)] <= IV_HASH[lanny(1)*CCW+:CCW];
        end else if (mode == M_XOF) begin
          state[0][lanny(0)] <= IV_XOF[0+:CCW];
          if (CCW == 32) state[0][lanny(1)] <= IV_XOF[lanny(1)*CCW+:CCW];
        end else if (mode == M_CXOF) begin
          state[0][lanny(0)] <= IV_CXOF[0+:CCW];
          if (CCW == 32) state[0][lanny(1)] <= IV_CXOF[lanny(1)*CCW+:CCW];
        end
        if (bdi_eoi) flag_eoi <= 'd1;
      end
      // State initialization, key addition 1
      if (ld_npub_done) begin
        state[0][lanny(0)] <= IV_AEAD[0+:CCW];
        if (CCW == 32) state[0][lanny(1)] <= IV_AEAD[lanny(1)*CCW+:CCW];
        state[1][wordy(0)] <= ascon_key[lanny(0)];
        state[2][wordy(2)] <= ascon_key[lanny(2)];
        if (CCW == 32) state[1][wordy(1)] <= ascon_key[lanny(1)];
        if (CCW == 32) state[2][wordy(3)] <= ascon_key[lanny(3)];
      end
      // Compute Ascon-p
      if (init || pro_ad || pro_msg || fin) begin
        for (int i = 0; i < 10; i++) state[i/2][i%2] <= asconp_o[i/2][i%2];
      end
      // Key addition 2/4
      if (kadd_2_done | fsm == KADD_4) begin
        state[3][wordy(0)] <= state[3][wordy(0)] ^ ascon_key[lanny(0)];
        state[4][wordy(2)] <= state[4][wordy(2)] ^ ascon_key[lanny(2)];
        if (CCW == 32) state[3][wordy(1)] <= state[3][wordy(1)] ^ ascon_key[lanny(1)];
        if (CCW == 32) state[4][wordy(3)] <= state[4][wordy(3)] ^ ascon_key[lanny(3)];
      end
      // Domain separation
      if (fsm == DOM_SEP) begin
        state[4][wordy(1)] <= state[4][wordy(1)] ^ ('d1 << (CCW - 1));
        if (flag_eoi) state[0][0] <= state[0][0] ^ 'd1;  // Padding of empty message
      end
      // Key addition 3
      if (fsm == KADD_3) begin
        state[2][wordy(0)] <= state[2][wordy(0)] ^ ascon_key[lanny(0)];
        state[3][wordy(2)] <= state[3][wordy(2)] ^ ascon_key[lanny(2)];
        if (CCW == 32) state[2][wordy(1)] <= state[2][wordy(1)] ^ ascon_key[lanny(1)];
        if (CCW == 32) state[3][wordy(3)] <= state[3][wordy(3)] ^ ascon_key[lanny(3)];
      end
      // Store key
      if (ld_key) begin
        ascon_key[word_cnt[(64/CCW)-1:0]] <= key;
        // ascon_key[lanny(word_cnt)] <= key; todo
      end
    end
  end

  /////////////////////
  // Counter Updates //
  /////////////////////

  always @(posedge clk) begin
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
      if (abs_ad_done | abs_msg_done) begin
        if (fsm_nx inside {PAD_AD, PAD_MSG}) begin
          word_cnt <= word_cnt + 'd1;
        end else begin
          word_cnt <= 'd0;
        end
      end
      if (fsm == PAD_AD) word_cnt <= 'd0;
      if (fsm == PAD_MSG) word_cnt <= 'd0;
      if (mode_r inside {M_HASH}) begin
        if (sqz_hash_done1) hash_cnt <= hash_cnt + 'd1;
        if (abs_ad_done & bdi_eoi) hash_cnt <= 'd0;
      end
      // Setting round counter
      case (fsm_nx)
        INIT: round_cnt <= ROUNDS_A;
        PRO_AD: round_cnt <= (mode_r inside {M_CXOF}) ? ROUNDS_A : ROUNDS_B;
        PRO_MSG: round_cnt <= (mode_r inside {M_HASH, M_XOF, M_CXOF}) ? ROUNDS_A : ROUNDS_B;
        FINAL: round_cnt <= ROUNDS_A;
      endcase
      if (init | pro_ad | pro_msg | fin) round_cnt <= round_cnt - UROL;
    end
  end

  //////////////////
  // Flag Updates //
  //////////////////

  always @(posedge clk) begin
    if (rst == 0) begin
      if (idle_done) begin
        flag_ad_eot  <= 'd0;
        flag_eoi     <= 'd0;
        flag_ad_pad  <= 'd0;
        flag_msg_pad <= 'd0;
        auth         <= 'd0;
        auth_intern  <= 'd0;
        auth_valid   <= 'd0;
        done         <= 'd0;
      end
      if (idle_done) begin
        mode_r   <= mode;
        flag_eoi <= bdi_eoi;
      end
      if (ld_npub_done) begin
        if (bdi_eoi) flag_eoi <= 'd1;
      end
      if (abs_ad_done) begin
        if (bdi_eot) flag_ad_eot <= 'd1;
        if (bdi_eoi) flag_eoi <= 'd1;
        if ((bdi_eot) && (bdi_valid != '1)) flag_ad_pad <= 'd1;
      end
      if (fsm == PAD_AD) flag_ad_pad <= 'd1;
      if (abs_msg_done) begin
        if (bdi_eoi) flag_eoi <= 'd1;
        if ((bdi_eot) && (bdi_valid != '1)) flag_msg_pad <= 'd1;
      end
      if (fsm == PAD_MSG) flag_ad_pad <= 'd1;
      if ((fsm == KADD_4) & (mode_r inside {M_DEC})) auth_intern <= 'd1;
      if (ver_tag) auth_intern <= auth_intern & (bdi == state_slice);
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
  generate
    if (CCW == 32) begin : g_ascon_debug_32
      assign x0 = {state[0][1], state[0][0]};
      assign x1 = {state[1][1], state[1][0]};
      assign x2 = {state[2][1], state[2][0]};
      assign x3 = {state[3][1], state[3][0]};
      assign x4 = {state[4][1], state[4][0]};
    end
    if (CCW == 64) begin : g_ascon_debug_64
      assign x0 = {state[0][0]};
      assign x1 = {state[1][0]};
      assign x2 = {state[2][0]};
      assign x3 = {state[3][0]};
      assign x4 = {state[4][0]};
    end
  endgenerate

endmodule  // ascon_core
