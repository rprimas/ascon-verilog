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
  // Core registers
  logic [ W64-1:0][CCW-1:0] state     [LANES];
  logic [W128-1:0][CCW-1:0] ascon_key;
  logic [     3:0]          round_cnt;
  logic [     7:0]          word_cnt;
  logic [     1:0]          hash_cnt;
  logic flag_ad_eot, flag_ad_pad, flag_msg_pad, flag_eoi, flag_eoo, auth_intern;
  logic [3:0] mode_r;

  // Event signals
  logic idle_done, ld_key, ld_key_done, ld_npub, ld_npub_done, init, init_done, kadd_2_done;
  assign idle_done    = (fsm == IDLE) & (mode > 'd0);
  assign ld_key       = (fsm == LD_KEY) & key_valid & key_ready;
  assign ld_key_done  = ld_key & (word_cnt == (W128 - 1));
  assign ld_npub      = (fsm == LD_NPUB) & (bdi_type == D_NONCE) & (bdi_valid > 'd0) & bdi_ready;
  assign ld_npub_done = ld_npub & (word_cnt == (W128 - 1));
  assign init         = (fsm == INIT);
  assign init_done    = init & (round_cnt == UROL);
  assign kadd_2_done  = (fsm == KADD_2) & (flag_eoi | (bdi_valid > 'd0));  // todo

  logic abs_ad, abs_ad_done, pro_ad, pro_ad_done;
  assign abs_ad      = (fsm == ABS_AD) & (bdi_type == D_AD) & (bdi_valid > 'd0) & bdi_ready;
  assign abs_ad_done = abs_ad & (last_abs_blk_wrd | bdi_eot);
  assign pro_ad      = (fsm == PRO_AD);
  assign pro_ad_done = pro_ad & (round_cnt == UROL);

  logic abs_msg_part, abs_msg, abs_msg_done, pro_msg, pro_msg_done;
  assign abs_msg_part = (fsm == ABS_MSG) & (bdi_type == D_MSG) & (bdi_valid > 'd0) & bdi_ready;
  assign abs_msg      = abs_msg_part & ((bdo_valid & bdo_ready) | !(mode_r inside {M_ENC, M_DEC}));
  assign abs_msg_done = abs_msg & (last_abs_blk_wrd | bdi_eot);
  assign pro_msg      = (fsm == PRO_MSG);
  assign pro_msg_done = (round_cnt == UROL) & pro_msg;

  logic fin, fin_done;
  assign fin      = (fsm == FINAL);
  assign fin_done = (round_cnt == UROL) & fin;

  logic sqz_hash, sqz_hash_done1, sqz_hash_done2, sqz_tag, sqz_tag_done, ver_tag, ver_tag_done;
  assign sqz_hash       = (fsm == SQZ_HASH) & bdo_valid & bdo_ready;
  assign sqz_hash_done1 = (word_cnt == (W64 - 1)) & sqz_hash;
  assign sqz_hash_done2 = ((hash_cnt == 'd3) & sqz_hash_done1) | (sqz_hash & bdo_eoo);
  assign sqz_tag        = (fsm == SQZ_TAG) & bdo_valid & bdo_ready;
  assign sqz_tag_done   = (word_cnt == (W128 - 1)) & sqz_tag;
  assign ver_tag        = (fsm == VER_TAG) & (bdi_type == D_TAG) & bdi_ready;
  assign ver_tag_done   = (word_cnt == (W128 - 1)) & ver_tag;

  // Utility signals
  logic last_abs_blk_wrd;
  assign last_abs_blk_wrd =
    (abs_ad  & (mode_r inside {M_ENC, M_DEC})          & (word_cnt == (W128 - 1))) |
    (abs_ad  & (mode_r inside {M_CXOF})                & (word_cnt == ( W64 - 1))) |
    (abs_msg & (mode_r inside {M_ENC, M_DEC})          & (word_cnt == (W128 - 1))) |
    (abs_msg & (mode_r inside {M_HASH, M_XOF, M_CXOF}) & (word_cnt == ( W64 - 1)));

  logic [    7:0]          state_idx;
  logic [W64-1:0][CCW-1:0] asconp_o    [LANES];
  logic [CCW-1:0]          state_nx;
  logic [CCW-1:0]          state_slice;

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
    paddy     = 'd0;
    case (fsm)
      LD_KEY:  key_ready = 'd1;
      LD_NPUB: begin
        state_idx = word_cnt + W192;
        bdi_ready = 'd1;
        state_nx  = bdi;
      end
      ABS_AD: begin
        state_idx = word_cnt;
        bdi_ready = 'd1;
        paddy = pad(bdi, bdi_valid);
        state_nx = state_slice ^ paddy;
      end
      PAD_AD, PAD_MSG: begin
        state_idx = word_cnt;
      end
      ABS_MSG: begin
        state_idx = word_cnt;
        if (mode_r inside {M_ENC, M_HASH, M_XOF, M_CXOF}) begin
          paddy = pad(bdi, bdi_valid);
          state_nx = state_slice ^ paddy;
          bdo = state_nx;
        end else if (mode_r inside {M_DEC}) begin
          paddy = pad2(bdi, state_slice, bdi_valid);
          state_nx = paddy;
          bdo = state_slice ^ state_nx;
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
        if ((word_cnt != (W128 - 1)) && (mode_r inside {M_ENC, M_DEC})) fsm_nx = PAD_AD;
        else if ((word_cnt != (W64 - 1)) && (mode_r inside {M_HASH, M_XOF, M_CXOF}))
          fsm_nx = PAD_AD;
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
        if ((mode_r inside {M_ENC, M_DEC}) && (word_cnt != (W128 - 1))) fsm_nx = PAD_MSG;
        else if ((word_cnt != (W64 - 1)) && (mode_r inside {M_HASH, M_XOF, M_CXOF}))
          fsm_nx = PAD_MSG;
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
        fsm_nx = SQZ_HASH;
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
      if (ld_npub | abs_ad | abs_msg) begin
        state[int'(lane_idx)][int'(word_idx)] <= state_nx;
      end
      // Absorb padding word
      if (fsm inside {PAD_AD, PAD_MSG}) begin
        state[int'(lane_idx)][int'(word_idx)] ^= 'd1;
        flag_ad_pad  <= fsm == PAD_AD;
        flag_msg_pad <= fsm == PAD_MSG;
      end
      // State initialization: HASH, XOF, CXOF
      if (idle_done & (mode inside {M_HASH, M_XOF, M_CXOF})) begin
        state <= '{default: '0};
        case (mode)
          M_HASH:  state[0] <= IV_HASH[0+:64];
          M_XOF:   state[0] <= IV_XOF[0+:64];
          M_CXOF:  state[0] <= IV_CXOF[0+:64];
          default: ;
        endcase
        if (bdi_eoi) flag_eoi <= 'd1;
      end
      // State initialization: AEAD
      // - "npub" is written to state during LOAD_NPUB
      if (ld_npub_done) begin
        state[0] <= IV_AEAD[0+:64];
        state[1] <= ascon_key[lanny(1):lanny(0)];
        state[2] <= ascon_key[lanny(3):lanny(2)];
      end
      // Perform Ascon-p permutation
      if (init | pro_ad | pro_msg | fin) begin
        state <= asconp_o;
      end
      // Key addition 2/4
      if (kadd_2_done | fsm == KADD_4) begin
        state[3] <= state[3] ^ ascon_key[lanny(1):lanny(0)];
        state[4] <= state[4] ^ ascon_key[lanny(3):lanny(2)];
      end
      // Domain separation
      if (fsm == DOM_SEP) begin
        state[4][wordy(1)] <= state[4][wordy(1)] ^ ('d1 << (CCW - 1));
        if (flag_eoi) state[0][0] <= state[0][0] ^ 'd1;  // Padding of empty message
      end
      // Key addition 3
      if (fsm == KADD_3) begin
        state[2] <= state[2] ^ ascon_key[lanny(1):lanny(0)];
        state[3] <= state[3] ^ ascon_key[lanny(3):lanny(2)];
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

  always @(posedge clk) begin
    if (rst) begin
      word_cnt <= 'd0;
    end else begin
      // Setting word counter
      if (ld_key | ld_npub | abs_ad | abs_msg | sqz_tag | sqz_hash | ver_tag) begin
        word_cnt <= word_cnt + 'd1;
      end
      if (ld_key_done | ld_npub_done | sqz_tag_done | sqz_hash_done1 | ver_tag_done) begin
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
        INIT:    round_cnt <= ROUNDS_A;
        PRO_AD:  round_cnt <= (mode_r inside {M_CXOF}) ? ROUNDS_A : ROUNDS_B;
        PRO_MSG: round_cnt <= (mode_r inside {M_HASH, M_XOF, M_CXOF}) ? ROUNDS_A : ROUNDS_B;
        FINAL:   round_cnt <= ROUNDS_A;
        default:;
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
  assign x0 = state[0];
  assign x1 = state[1];
  assign x2 = state[2];
  assign x3 = state[3];
  assign x4 = state[4];

  logic forcee;

endmodule  // ascon_core
