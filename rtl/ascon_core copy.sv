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
    input  logic            auth_ready
);

  // Core registers
  logic [LANE_BITS/2-1:0] state     [      LANES] [2];
  logic [LANE_BITS/2-1:0] ascon_key [KEY_BITS/32];
  logic [            3:0] round_cnt;
  logic [            3:0] word_cnt;
  logic [            1:0] hash_cnt;
  logic flag_ad_eot, flag_dec, flag_eoi, flag_hash, auth_intern;

  localparam logic [3:0] RateWords = (RATE_AEAD_BITS/32);

  // Utility signals
  logic op_ld_key_req, op_aead_req, op_hash_req;
  assign op_ld_key_req = key_valid;
  assign op_aead_req = (bdi_type == D_NONCE) & bdi_valid;
  assign op_hash_req = (bdi_type == D_AD) & bdi_valid & hash;

  logic idle_done, ld_key_do, ld_key_done, ld_nonce_do, ld_nonce_done, init_do, init_done, key_add_2_done;
  assign idle_done = (fsm == IDLE) & (op_ld_key_req | op_aead_req | op_hash_req);
  assign ld_key_do = (fsm == LOAD_KEY) & key_valid & key_ready;
  assign ld_key_done = (word_cnt == 3) & ld_key_do;
  assign ld_nonce_do = (fsm == LOAD_NONCE) & (bdi_type == D_NONCE) & bdi_valid & bdi_ready;
  assign ld_nonce_done = (word_cnt == 3) & ld_nonce_do;
  assign init_do = (fsm == INIT);
  assign init_done = (round_cnt == UROL) & init_do;
  assign key_add_2_done = (fsm == KEY_ADD_2) & (flag_eoi | bdi_valid);

  logic abs_ad_do, abs_ad_done, pro_ad_do, pro_ad_done;
  assign abs_ad_do = (fsm == ABS_AD) & (bdi_type == D_AD) & bdi_valid & bdi_ready;
  assign abs_ad_done = ((word_cnt == RateWords-1) | bdi_eot) & abs_ad_do;
  assign pro_ad_do = (fsm == PRO_AD);
  assign pro_ad_done = (round_cnt == UROL) & pro_ad_do;

  logic abs_ptct_do, abs_ptct_done, pro_ptct_do, pro_ptct_done;
  assign abs_ptct_do = (fsm == ABS_PTCT) & (bdi_type == D_PTCT) & bdi_valid & bdi_ready & bdo_ready;
  assign abs_ptct_done = ((word_cnt == RateWords-1) | bdi_eot) & abs_ptct_do;
  assign pro_ptct_do = (fsm == PRO_PTCT);
  assign pro_ptct_done = (round_cnt == UROL) & pro_ptct_do;

  logic final_do, final_done;
  assign final_do = (fsm == FINAL);
  assign final_done = (round_cnt == UROL) & final_do;

  logic sqz_hash_do, sqz_hash_done1, sqz_hash_done2, sqz_tag_do, sqz_tag_done, ver_tag_do, ver_tag_done;
  assign sqz_hash_do = (fsm == SQUEEZE_HASH) & bdo_ready;
  assign sqz_hash_done1 = (word_cnt == 1) & sqz_hash_do;
  assign sqz_hash_done2 = (hash_cnt == 3) & sqz_hash_done1;
  assign sqz_tag_do = (fsm == SQUEEZE_TAG) & bdo_ready;
  assign sqz_tag_done = (word_cnt == 3) & sqz_tag_do;
  assign ver_tag_do = (fsm == VERIF_TAG) & (bdi_type == D_TAG) & bdi_valid & bdi_ready;
  assign ver_tag_done = (word_cnt == 3) & ver_tag_do;

  logic [            3:0] state_idx;
  logic [LANE_BITS/2-1:0] asconp_o    [LANES][2];
  logic [        CCW-1:0] state_i;
  logic [        CCW-1:0] state_slice;

  assign state_slice = state[state_idx/2][state_idx%2];  // Dynamic slicing

  // Finate state machine
  typedef enum bit [63:0] {
    IDLE         = "IDLE",
    LOAD_KEY     = "LD_KEY",
    LOAD_NONCE   = "LD_NONCE",
    INIT         = "INIT",
    KEY_ADD_2    = "KEY_ADD2",
    ABS_AD       = "ABS_AD",
    PRO_AD       = "PRO_AD",
    DOM_SEP      = "DOM_SEP",
    ABS_PTCT     = "ABS_PTCT",
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
        state_i   = state_slice ^ bdi;
      end
      ABS_PTCT: begin
        state_idx = word_cnt;
        if (flag_dec) begin
          state_i = bdi;
          bdo = state_slice ^ state_i;
        end else begin
          state_i = state_slice ^ bdi;
          bdo = state_i;
        end
        bdi_ready = 1;
        bdo_valid = bdi_valid;
        bdo_type  = D_PTCT;
        bdo_eot   = bdi_eot;
      end
      SQUEEZE_TAG: begin
        state_idx = word_cnt + 6;
        bdo       = state_slice;
        bdo_valid = 1;
        bdo_type  = D_TAG;
        bdo_eot   = word_cnt == 3;
      end
      SQUEEZE_HASH: begin
        state_idx = word_cnt;
        bdo       = state_slice;
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
    if (init_done) fsm_nx = flag_hash === 1 ? ABS_AD : KEY_ADD_2;
    if (key_add_2_done) begin
      if (flag_eoi) fsm_nx = DOM_SEP;
      else if (bdi_type == D_AD) fsm_nx = ABS_AD;
      else if (bdi_type == D_PTCT) fsm_nx = DOM_SEP;
    end
    if (abs_ad_done) fsm_nx = PRO_AD;
    if (pro_ad_done) begin
      if (flag_hash) fsm_nx = flag_ad_eot === 1 ? SQUEEZE_HASH : ABS_AD;
      else fsm_nx = flag_ad_eot === 1 ? DOM_SEP : ABS_AD;
    end
    if (fsm == DOM_SEP) fsm_nx = flag_eoi === 1 ? KEY_ADD_3 : ABS_PTCT;
    if (abs_ptct_done) fsm_nx = bdi_eot === 1 ? KEY_ADD_3 : PRO_PTCT;
    if (pro_ptct_done) fsm_nx = flag_eoi === 1 ? KEY_ADD_3 : ABS_PTCT;
    if (fsm == KEY_ADD_3) fsm_nx = FINAL;
    if (final_done) fsm_nx = KEY_ADD_4;
    if (fsm == KEY_ADD_4) fsm_nx = flag_dec === 1 ? VERIF_TAG : SQUEEZE_TAG;
    if (sqz_hash_done1) fsm_nx = PRO_AD;
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
      if (ld_nonce_do || abs_ad_do || abs_ptct_do) begin
        state[state_idx/2][state_idx%2] <= state_i;  // Dynamic slicing
      end
      // State initialization, hashing
      if (idle_done & op_hash_req) begin
        state[0][0] <= IV_HASH[31:0];
        state[0][1] <= IV_HASH[63:32];
        for (int i = 2; i < 10; i++) state[i/2][i%2] <= 0;
      end
      // State initialization, key addition 1
      if (ld_nonce_done) begin
        state[0][0] <= IV_AEAD[31:0];
        state[0][1] <= IV_AEAD[63:32];
        for (int i = 0; i < 4; i++) state[1+i/2][i%2] <= ascon_key[i];
      end
      // Compute Ascon-p
      if (init_do || pro_ad_do || pro_ptct_do || final_do) begin
        for (int i = 0; i < 10; i++) state[i/2][i%2] <= asconp_o[i/2][i%2];
      end
      // Key addition 2/4
      if (key_add_2_done | fsm == KEY_ADD_4) begin
        for (int i = 0; i < 4; i++) state[3+i/2][i%2] <= state[3+i/2][i%2] ^ ascon_key[i];
      end
      // Domain separation
      if (fsm == DOM_SEP) begin
        state[4][1] <= state[4][1] ^ 32'h00000001;
        if (flag_eoi) state[0][0] <= state[0][0] ^ 32'h80000000;  // Padding of empty message
      end
      // Key addition 3
      if (fsm == KEY_ADD_3) begin
        for (int i = 0; i < 4; i++) state[1+i/2][i%2] <= state[1+i/2][i%2] ^ ascon_key[i];
      end
      // Store key
      if (ld_key_do) begin
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
      if (ld_key_do | ld_nonce_do | abs_ad_do | abs_ptct_do | sqz_tag_do | sqz_hash_do | ver_tag_do) begin
        word_cnt <= word_cnt + 1;
      end
      if (ld_key_done|ld_nonce_done|abs_ad_done|abs_ptct_done|sqz_tag_done|sqz_hash_done1|ver_tag_done) begin
        word_cnt <= 0;
      end
      if (sqz_hash_done1) hash_cnt <= hash_cnt + 1;
      if (flag_hash & abs_ad_done & bdi_eoi) hash_cnt <= 0;
      // Setting round counter
      if ((idle_done & op_hash_req) | ld_nonce_done | fsm == KEY_ADD_3) round_cnt <= ROUNDS_A;
      if (((abs_ad_done & flag_hash) | sqz_hash_done1) & !sqz_hash_done2) round_cnt <= ROUNDS_A;
      if ((abs_ad_done & !flag_hash) | (abs_ptct_done & !bdi_eot)) round_cnt <= ROUNDS_B;
      if (init_do | pro_ad_do | pro_ptct_do | final_do) round_cnt <= round_cnt - UROL;
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
        auth <= 0;
        auth_intern <= 0;
        auth_valid <= 0;
      end
      if (idle_done & op_hash_req) flag_hash <= 1;
      if (ld_nonce_done) begin
        if (bdi_eoi) flag_eoi <= 1;
        flag_dec <= decrypt;
      end
      if (abs_ad_done) begin
        if (bdi_eot == 1) flag_ad_eot <= 1;
        if (bdi_eoi == 1) flag_eoi <= 1;
      end
      if (abs_ptct_done) if (bdi_eoi == 1) flag_eoi <= 1;
      if ((fsm == KEY_ADD_4) & flag_dec) auth_intern <= 1;
      if (ver_tag_do) auth_intern <= auth_intern & (bdi == state_slice);
      if (ver_tag_done) begin
        auth_valid <= 1;
        auth <= auth_intern;
      end
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
    $dumpvars(0, fsm, flag_ad_eot, flag_dec, flag_eoi, flag_hash, word_cnt, round_cnt, hash_cnt,
              x0, x1, x2, x3, x4);
  end

endmodule  // ascon_core
