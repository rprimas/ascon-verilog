// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Implementation of the Ascon core.

module ascon_core (
    input  logic            clk,
    input  logic            rst,
    input  logic [CCSW-1:0] key,
    input  logic            key_valid,
    output logic            key_ready,
    input  logic [ CCW-1:0] bdi,
    input  logic            bdi_valid,
    input  logic [     3:0] bdi_valid_bytes,
    output logic            bdi_ready,
    input  logic [     3:0] bdi_type,
    input  logic            bdi_eot,
    input  logic            bdi_eoi,
    input  logic            decrypt,
    input  logic            hash,
    output logic [ CCW-1:0] bdo,
    output logic            bdo_valid,
    input  logic            bdo_ready,
    output logic [     3:0] bdo_type,
    output logic            bdo_eot,
    output logic            auth,
    output logic            auth_valid,
    output logic            done
);

  // Core registers
  logic [LANE_BITS/2-1:0] state     [      LANES] [2];
  logic [LANE_BITS/2-1:0] ascon_key [KEY_BITS/32];
  logic [            3:0] round_cnt;
  logic [            3:0] word_cnt;
  logic [            1:0] hash_cnt;
  logic flag_ad_eot, flag_ad_pad, flag_ptct_pad, flag_dec, flag_eoi, flag_hash, auth_intern;

  // Utility signals
  logic op_ld_key_req, op_aead_req, op_hash_req;
  assign op_ld_key_req = key_valid;
  assign op_aead_req   = (bdi_type == D_NONCE) & bdi_valid;
  assign op_hash_req   = (bdi_type == D_MSG) & hash & bdi_valid;

  logic idle_done, ld_key, ld_key_done, ld_nonce, ld_nonce_done, init, init_done, key_add_2_done;
  assign idle_done = (fsm == IDLE) & (op_ld_key_req | op_aead_req | op_hash_req);
  assign ld_key = (fsm == LOAD_KEY) & key_valid & key_ready;
  assign ld_key_done = (word_cnt == 3) & ld_key;
  assign ld_nonce = (fsm == LOAD_NONCE) & (bdi_type == D_NONCE) & bdi_valid & bdi_ready;
  assign ld_nonce_done = (word_cnt == 3) & ld_nonce;
  assign init = (fsm == INIT);
  assign init_done = (round_cnt == UROL) & init;
  assign key_add_2_done = (fsm == KEY_ADD_2) & (flag_eoi | bdi_valid);

  logic abs_ad, abs_ad_done, pro_ad, pro_ad_done;
  assign abs_ad = (fsm == ABS_AD) & (bdi_type == D_AD) & bdi_valid & bdi_ready;
  assign abs_ad_done = ((word_cnt == 4) | bdi_eot) & abs_ad;
  assign pro_ad = (fsm == PRO_AD);
  assign pro_ad_done = (round_cnt == UROL) & pro_ad;

  logic abs_ptct, abs_ptct_done, pro_ptct, pro_ptct_done;
  assign abs_ptct = (fsm == ABS_PTCT) & (bdi_type == D_PTCT) & bdi_valid & bdi_ready & (flag_hash == 0 ? bdo_ready : 1);
  assign abs_ptct_done = ((word_cnt == (flag_hash == 0 ? 3 : 1)) | bdi_eot) & abs_ptct;
  assign pro_ptct = (fsm == PRO_PTCT);
  assign pro_ptct_done = (round_cnt == UROL) & pro_ptct;

  logic fin, fin_done;
  assign fin = (fsm == FINAL);
  assign fin_done = (round_cnt == UROL) & fin;

  logic sqz_hash, sqz_hash_done1, sqz_hash_done2, sqz_tag, sqz_tag_done, ver_tag, ver_tag_done;
  assign sqz_hash = (fsm == SQUEEZE_HASH) & bdo_ready;
  assign sqz_hash_done1 = (word_cnt == 1) & sqz_hash;
  assign sqz_hash_done2 = (hash_cnt == 3) & sqz_hash_done1;
  assign sqz_tag = (fsm == SQUEEZE_TAG) & bdo_ready;
  assign sqz_tag_done = (word_cnt == 3) & sqz_tag;
  assign ver_tag = (fsm == VERIF_TAG) & (bdi_type == D_TAG) & bdi_valid & bdi_ready;
  assign ver_tag_done = (word_cnt == 3) & ver_tag;

  logic [            3:0] state_idx;
  logic [LANE_BITS/2-1:0] asconp_o    [LANES][2];
  logic [        CCW-1:0] state_i;
  logic [        CCW-1:0] state_slice;

  assign state_slice = state[state_idx/2][state_idx%2];  // Dynamic slicing

  // Finate state machine
  typedef enum logic [63:0] {
    IDLE         = "IDLE",
    LOAD_KEY     = "LD_KEY",
    LOAD_NONCE   = "LD_NONCE",
    INIT         = "INIT",
    KEY_ADD_2    = "KEY_ADD2",
    ABS_AD       = "ABS_AD",
    PAD_AD       = "PAD_AD",
    PRO_AD       = "PRO_AD",
    DOM_SEP      = "DOM_SEP",
    ABS_PTCT     = "ABS_PTCT",
    PAD_PTCT     = "PAD_PTCT",
    PRO_PTCT     = "PRO_PTCT",
    KEY_ADD_3    = "KEY_ADD3",
    FINAL        = "FINAL",
    KEY_ADD_4    = "KEY_ADD4",
    SQUEEZE_TAG  = "SQZ_TAG",
    SQUEEZE_HASH = "SQZ_HASH",
    VERIF_TAG    = "VER_TAG"
  } fsms_t;
  fsms_t fsm;  // Current state
  fsms_t fsm_nx;  // Next state

  // Instantiation of Ascon-p permutation
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

  /////////////////////
  // Control Signals //
  /////////////////////

  always_comb begin
    state_i = 32'h0;
    state_idx = 0;
    key_ready = 0;
    bdi_ready = 0;
    bdo = 0;
    bdo_valid = 0;
    bdo_type = D_NULL;
    bdo_eot = 0;
    case (fsm)
      LOAD_KEY: key_ready = 1;
      LOAD_NONCE: begin
        state_idx = word_cnt + 6;
        bdi_ready = 1;
        state_i   = bdi;
      end
      ABS_AD: begin
        state_idx = word_cnt;
        bdi_ready = 1;
        state_i   = state_slice ^ {
          (bdi[31:24] & {8{bdi_valid_bytes[3]}}) | (8'h01&{8{~bdi_valid_bytes[3]&(bdi_valid_bytes[2])}}),
          (bdi[23:16] & {8{bdi_valid_bytes[2]}}) | (8'h01&{8{~bdi_valid_bytes[2]&(bdi_valid_bytes[1])}}),
          (bdi[15: 8] & {8{bdi_valid_bytes[1]}}) | (8'h01&{8{~bdi_valid_bytes[1]&(bdi_valid_bytes[0])}}),
          (bdi[ 7: 0] & {8{bdi_valid_bytes[0]}})
        };
      end
      PAD_AD, PAD_PTCT: begin
        state_idx = word_cnt;
      end
      ABS_PTCT: begin
        state_idx = word_cnt;
        if (flag_dec) begin
          state_i = {
            bdi_valid_bytes[3] ? bdi[31:24] : (bdi_valid_bytes[2] ? (8'h01 ^ (state_slice[31:24])) : (state_slice[31:24])),
            bdi_valid_bytes[2] ? bdi[23:16] : (bdi_valid_bytes[1] ? (8'h01 ^ (state_slice[23:16])) : (state_slice[23:16])),
            bdi_valid_bytes[1] ? bdi[15: 8] : (bdi_valid_bytes[0] ? (8'h01 ^ (state_slice[15: 8])) : (state_slice[15: 8])),
            bdi_valid_bytes[0] ? bdi[7:0] : (state_slice[7:0])
          };
          bdo = state_slice ^ state_i;
        end else begin
          state_i   = state_slice ^ {
            (bdi[31:24] & {8{bdi_valid_bytes[3]}}) | (8'h01&{8{~bdi_valid_bytes[3]&(bdi_valid_bytes[2])}}),
            (bdi[23:16] & {8{bdi_valid_bytes[2]}}) | (8'h01&{8{~bdi_valid_bytes[2]&(bdi_valid_bytes[1])}}),
            (bdi[15: 8] & {8{bdi_valid_bytes[1]}}) | (8'h01&{8{~bdi_valid_bytes[1]&(bdi_valid_bytes[0])}}),
            (bdi[ 7: 0] & {8{bdi_valid_bytes[0]}})
          };
          bdo = state_i;
        end
        bdi_ready = 1;
        bdo_valid = bdi_valid;
        bdo_type  = D_PTCT;
        bdo_eot   = bdi_eot;
        if (flag_hash) begin
          bdo = 'd0;
          bdo_valid = 'd0;
          bdo_type = D_NULL;
          bdo_eot = 'd0;
        end
      end
      SQUEEZE_TAG: begin
        state_idx = word_cnt + 6;
        bdo       = {state_slice[7:0], state_slice[15:8], state_slice[23:16], state_slice[31:24]};
        bdo_valid = 1;
        bdo_type  = D_TAG;
        bdo_eot   = word_cnt == 3;
      end
      SQUEEZE_HASH: begin
        state_idx = word_cnt;
        bdo       = {state_slice[7:0], state_slice[15:8], state_slice[23:16], state_slice[31:24]};
        bdo_valid = 1;
        bdo_type  = D_HASH;
        bdo_eot   = (hash_cnt == 3) & (word_cnt == 1);
      end
      VERIF_TAG: begin
        state_idx = word_cnt + 6;
        bdi_ready = 1;
      end
      default:  ;
    endcase
  end

  //////////////////////////
  // FSM Next State Logic //
  //////////////////////////

  always_comb begin
    fsm_nx = fsm;
    if (idle_done) begin
      if (op_ld_key_req) fsm_nx = LOAD_KEY;
      else if (op_aead_req) fsm_nx = LOAD_NONCE;
      else if (op_hash_req) fsm_nx = INIT;
    end
    if (ld_key_done) fsm_nx = LOAD_NONCE;
    if (ld_nonce_done) fsm_nx = INIT;
    if (init_done) fsm_nx = flag_hash ? (flag_eoi ? PAD_PTCT : ABS_PTCT) : KEY_ADD_2;
    if (key_add_2_done) begin
      if (flag_eoi) fsm_nx = DOM_SEP;
      else if (bdi_type == D_AD) fsm_nx = ABS_AD;
      else if (bdi_type == D_PTCT) fsm_nx = DOM_SEP;
    end
    if (abs_ad_done) begin
      if (bdi_valid_bytes != 4'b1111) begin
        fsm_nx = PRO_AD;
      end else begin
        if (word_cnt < 3) fsm_nx = PAD_AD;
        else fsm_nx = PRO_AD;
      end
    end
    if (fsm == PAD_AD) fsm_nx = PRO_AD;
    if (pro_ad_done) begin
      // if (flag_hash) fsm_nx = flag_eoi ? SQUEEZE_HASH : ABS_AD;
      // else
      begin
        if (flag_ad_eot == 0) begin
          fsm_nx = ABS_AD;
        end else if (flag_ad_pad == 0) begin
          fsm_nx = PAD_AD;
        end else begin
          fsm_nx = DOM_SEP;
        end
      end
    end
    if (fsm == DOM_SEP) fsm_nx = flag_eoi === 1 ? KEY_ADD_3 : ABS_PTCT;
    if (abs_ptct_done) begin
      if (bdi_valid_bytes != 4'b1111) begin
        if (flag_hash) fsm_nx = FINAL;
        else fsm_nx = KEY_ADD_3;
      end else begin
        if ((word_cnt < 3) && (flag_hash == 'd0)) fsm_nx = PAD_PTCT;
        else if ((word_cnt < 1) && (flag_hash == 'd1)) fsm_nx = PAD_PTCT;
        else fsm_nx = PRO_PTCT;
      end
    end
    if (fsm == PAD_PTCT) begin
      if (flag_hash) fsm_nx = FINAL;
      else fsm_nx = KEY_ADD_3;
    end
    if (pro_ptct_done) begin
      if (flag_eoi == 0) begin
        fsm_nx = ABS_PTCT;
      end else if (flag_ptct_pad == 0) begin
        fsm_nx = PAD_PTCT;
      end
    end
    if (fsm == KEY_ADD_3) fsm_nx = FINAL;
    if (fin_done) begin
      if (flag_hash) fsm_nx = SQUEEZE_HASH;
      else fsm_nx = KEY_ADD_4;
    end
    if (fsm == KEY_ADD_4) fsm_nx = flag_dec === 1 ? VERIF_TAG : SQUEEZE_TAG;
    if (sqz_hash_done1) fsm_nx = FINAL;
    if (sqz_hash_done2) fsm_nx = IDLE;
    if (sqz_tag_done) fsm_nx = IDLE;
    if (ver_tag_done) fsm_nx = IDLE;
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

  /////////////////////////
  // Ascon State Updates //
  /////////////////////////

  always @(posedge clk) begin
    if (rst == 0) begin
      if (ld_nonce || abs_ad || abs_ptct) begin
        state[state_idx/2][state_idx%2] <= state_i;
      end
      if (fsm inside {PAD_AD}) begin
        state[state_idx/2][state_idx%2] ^= 32'h00000001;
        flag_ad_pad <= 'd1;
      end
      if (fsm inside {PAD_PTCT}) begin
        state[state_idx/2][state_idx%2] ^= 32'h00000001;
        flag_ptct_pad <= 'd1;
      end
      // State initialization, hashing
      if (idle_done & op_hash_req) begin
        state[0][0] <= IV_HASH[31:0];
        state[0][1] <= IV_HASH[63:32];
        for (int i = 2; i < 10; i++) state[i/2][i%2] <= 0;
        if (bdi_eoi) flag_eoi <= 1;
      end
      // State initialization, key addition 1
      if (ld_nonce_done) begin
        state[0][0] <= IV_AEAD[31:0];
        state[0][1] <= IV_AEAD[63:32];
        for (int i = 0; i < 4; i++) state[1+i/2][i%2] <= ascon_key[i];
      end
      // Compute Ascon-p
      if (init || pro_ad || pro_ptct || fin) begin
        for (int i = 0; i < 10; i++) state[i/2][i%2] <= asconp_o[i/2][i%2];
      end
      // Key addition 2/4
      if (key_add_2_done | fsm == KEY_ADD_4) begin
        for (int i = 0; i < 4; i++) state[3+i/2][i%2] <= state[3+i/2][i%2] ^ ascon_key[i];
      end
      // Domain separation
      if (fsm == DOM_SEP) begin
        state[4][1] <= state[4][1] ^ 32'h80000000;
        if (flag_eoi) state[0][0] <= state[0][0] ^ 32'h00000001;  // Padding of empty message
      end
      // Key addition 3
      if (fsm == KEY_ADD_3) begin
        for (int i = 0; i < 4; i++) state[2+i/2][i%2] <= state[2+i/2][i%2] ^ ascon_key[i];
      end
      // Store key
      if (ld_key) begin
        ascon_key[word_cnt[1:0]] <= key;
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
      if (ld_key | ld_nonce | abs_ad | abs_ptct | sqz_tag | sqz_hash | ver_tag) begin
        word_cnt <= word_cnt + 1;
      end
      if (ld_key_done | ld_nonce_done || sqz_tag_done | sqz_hash_done1 | ver_tag_done) begin
        word_cnt <= 0;
      end
      if (abs_ad_done) begin
        if (fsm_nx == PAD_AD) begin
          word_cnt <= word_cnt + 1;
        end else begin
          word_cnt <= 0;
        end
      end
      if (abs_ptct_done) begin
        if (fsm_nx == PAD_PTCT) begin
          word_cnt <= word_cnt + 1;
        end else begin
          word_cnt <= 0;
        end
      end
      if (fsm == PAD_AD) word_cnt <= 0;
      if (fsm == PAD_PTCT) word_cnt <= 0;
      if (sqz_hash_done1) hash_cnt <= hash_cnt + 1;
      if (flag_hash & abs_ad_done & bdi_eoi) hash_cnt <= 0;
      // Setting round counter
      if ((idle_done & op_hash_req) | ld_nonce_done | fsm == KEY_ADD_3) round_cnt <= ROUNDS_A;
      if (((abs_ptct_done & flag_hash) | sqz_hash_done1) & !sqz_hash_done2) round_cnt <= ROUNDS_A;
      // if ((abs_ad_done & !flag_hash) | (abs_ptct_done & (fsm_nx == PRO_PTCT))) round_cnt <= ROUNDS_B; // todo!flaghash?
      if (abs_ad_done & !flag_hash) round_cnt <= ROUNDS_B;  // todo!flaghash?
      if ((abs_ptct_done & (fsm_nx == PRO_PTCT))) round_cnt <= ROUNDS_B;  // todo!flaghash?
      if ((abs_ptct_done & flag_hash & (fsm_nx == PRO_PTCT)))
        round_cnt <= ROUNDS_A;  // todo!flaghash?



      if (fsm == PAD_AD) round_cnt <= flag_hash ? ROUNDS_A : ROUNDS_B;
      if (init | pro_ad | pro_ptct | fin) round_cnt <= round_cnt - UROL;
      if ((fsm == PAD_PTCT) && (fsm_nx == FINAL)) round_cnt <= ROUNDS_A;
    end
  end

  //////////////////
  // Flag Updates //
  //////////////////

  always @(posedge clk) begin
    if (rst == 0) begin
      if (idle_done) begin
        flag_ad_eot <= 0;
        flag_dec <= 0;
        flag_eoi <= 0;
        flag_hash <= 0;
        flag_ad_pad <= 0;
        flag_ptct_pad <= 0;
        auth <= 0;
        auth_intern <= 0;
        auth_valid <= 0;
        done <= 0;
      end
      if (idle_done & op_hash_req) flag_hash <= 1;
      if (idle_done & bdi_eoi) flag_eoi <= 1;
      if (ld_nonce_done) begin
        if (bdi_eoi) flag_eoi <= 1;
        flag_dec <= decrypt;
      end
      if (abs_ad_done) begin
        if (bdi_eot == 1) flag_ad_eot <= 1;
        if (bdi_eoi == 1) flag_eoi <= 1;
        if ((bdi_eot == 1) && (bdi_valid_bytes != 4'b1111)) flag_ad_pad <= 1;
      end
      if (fsm == PAD_AD) flag_ad_pad <= 1;
      if (abs_ptct_done) begin
        if (bdi_eoi == 1) flag_eoi <= 1;
        if ((bdi_eot == 1) && (bdi_valid_bytes != 4'b1111)) flag_ptct_pad <= 1;
      end
      if (fsm == PAD_PTCT) flag_ad_pad <= 1;
      if ((fsm == KEY_ADD_4) & flag_dec) auth_intern <= 1;
      if (ver_tag) auth_intern <= auth_intern & (bdi[31:0] == state_slice);
      if (ver_tag_done) begin
        auth_valid <= 1;
        auth <= auth_intern;
      end
      if ((fsm != IDLE) && (fsm_nx == IDLE)) done <= 'd1;
    end
  end

  //////////////////////////////////////////////////
  // Debug Signals (can be removed for synthesis) //
  //////////////////////////////////////////////////

  logic [63:0] x0, x1, x2, x3, x4;
  assign x0 = {state[0][1], state[0][0]};
  assign x1 = {state[1][1], state[1][0]};
  assign x2 = {state[2][1], state[2][0]};
  assign x3 = {state[3][1], state[3][0]};
  assign x4 = {state[4][1], state[4][0]};

  // initial begin
  //   $dumpfile("tb.vcd");
  //   $dumpvars(0, fsm, flag_ad_eot, flag_dec, flag_eoi, flag_hash, word_cnt, round_cnt, hash_cnt,
  //             x0, x1, x2, x3, x4);
  // end

endmodule  // ascon_core
