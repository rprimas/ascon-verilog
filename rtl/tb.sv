// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Test bench for controlling the Ascon core.

`timescale 1s / 100ms
`include "rtl/config.sv"

module tb;

  // Test bench config
  int               SIM_CYCLES = 300;
  string            VCD_FILE = "tb.vcd";
  string            TV_FILE = "tv/tv.txt";

  // Test bench signals
  logic  [    23:0] tb_word_cnt = 0;
  logic  [    31:0] data;
  logic  [     3:0] op;
  logic  [     3:0] flags;
  string            hdr = "INS";
  int               fd;

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
  logic             auth;
  logic             auth_valid;
  logic             auth_ready;

  // Instatiate Ascon core
  ascon_core ascon_core_i (
      .clk(clk),
      .rst(rst),
      .key(key),
      .key_valid(key_valid),
      .key_ready(key_ready),
      .bdi(bdi),
      .bdi_valid(bdi_valid),
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
      .auth_ready(auth_ready)
  );

  // Read one line of test vector file per cycle
  always @(posedge clk) begin
    if (!$feof(fd)) begin
      if ((hdr != "DAT") | ((hdr == "DAT") & ((key_ready | bdi_ready)))) begin
        void'($fscanf(fd, "%s\n", hdr));
        if (hdr == "INS") begin
          void'($fscanf(fd, "%h", data));
          op <= data[31:28];
          flags <= data[27:24];
          tb_word_cnt <= (data[23:0] + 3) / 4 + 1;
        end else if (hdr == "DAT") begin
          void'($fscanf(fd, "%h", data));
          tb_word_cnt <= tb_word_cnt - (tb_word_cnt > 0);
        end
      end
    end
  end

  // Set persitent signals according to current line of test vector file
  always @(posedge clk) begin
    if (rst) begin
      decrypt <= 0;
      hash <= 0;
    end else begin
      if (op == OP_DO_ENC) begin
        decrypt <= 0;
        hash <= 0;
      end else if (op == OP_DO_DEC) begin
        decrypt <= 1;
        hash <= 0;
      end else if (op == OP_DO_HASH) begin
        decrypt <= 0;
        hash <= 1;
      end
    end
  end

  // Set interface signals according to current line of test vector file
  always @(*) begin
    key = 0;
    key_valid = 0;
    bdi = 0;
    bdi_valid = 0;
    bdi_type = D_NULL;
    bdi_eot = 0;
    bdi_eoi = 0;
    bdo_ready = 0;
    auth_ready = 0;

    if (hdr == "DAT") begin
      if (op == OP_LD_KEY) begin
        key = data;
        key_valid = 1;
      end
      if (op == OP_LD_NONCE | op == OP_LD_AD | op == OP_LD_PT | op == OP_LD_CT | op == OP_LD_TAG) begin
        bdi = data;
        bdi_valid = 1;
        if (op == OP_LD_NONCE) bdi_type = D_NONCE;
        if (op == OP_LD_AD) bdi_type = D_AD;
        if (op == OP_LD_PT) begin
          bdi_type  = D_PTCT;
          bdo_ready = 1;
        end
        if (op == OP_LD_CT) begin
          bdi_type  = D_PTCT;
          bdo_ready = 1;
        end
        if (op == OP_LD_TAG) begin
          bdi_type = D_TAG;
          auth_ready = 1;
        end
        if (tb_word_cnt == 0) bdi_type = D_NULL;
        if (tb_word_cnt == 1) begin
          bdi_eot = 1;
          bdi_eoi = flags[0:0];
        end
      end
    end
  end

  // Signal readyness to receive tag from Ascon core
  always @(*) begin
    if ((bdo_type == D_TAG) & bdo_valid) begin
      bdo_ready = 1;
    end
    if ((bdo_type == D_HASH) & bdo_valid) begin
      bdo_ready = 1;
    end
  end

  // Print message output from Ascon core
  always @(posedge clk) begin
    if (bdo_valid) begin
      if (bdo_type == D_PTCT) begin
        if (decrypt) $display("p => %h", bdo);
        else $display("c => %h", bdo);
      end
      if (bdo_type == D_TAG) $display("t => %h", bdo);
      if (bdo_type == D_HASH) $display("h => %h", bdo);
    end
  end

  // Print tag verification output from Ascon core
  always @(posedge auth_valid) begin
    $display("v => %h", auth);
  end

  // Generate clock signal
  always #5 clk = !clk;

  // Open test vector file
  initial begin
    fd = $fopen(TV_FILE, "r");
  end

  // Specify debug variables and set simulation start/finish
  initial begin
    $dumpfile(VCD_FILE);
    $dumpvars(0, clk, rst, op, data, tb_word_cnt, key, key_valid, key_ready, bdi, bdi_valid,
              bdi_ready, bdi_type, bdi_eot, bdi_eoi, decrypt, hash, bdo, bdo_valid, bdo_ready,
              bdo_type, bdo_eot, auth_valid, auth_ready, auth);
    #1;
    rst = 1;
    #10;
    rst = 0;
    #(SIM_CYCLES * 10);
    $fclose(fd);
    $finish;
  end

endmodule  // tb
