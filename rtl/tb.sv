// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Testbench for controlling the Ascon core.

`timescale 1s / 100ms
`include "rtl/config.sv"

module tb;

  // Testbench config
  int               SIM_CYCLES = 200;
  string            VCD_FILE = "tb.vcd";
  string            KAT_FILE = "KAT/KAT_tmp.txt";

  // Testbench signals
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
  logic             decrypt_in;
  logic             hash_in;
  logic  [ CCW-1:0] bdo;
  logic             bdo_valid;
  logic             bdo_ready;
  logic  [     3:0] bdo_type;
  logic             bdo_eot;
  logic             msg_auth;
  logic             msg_auth_valid;
  logic             msg_auth_ready;

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
      .decrypt_in(decrypt_in),
      .hash_in(hash_in),
      .bdo(bdo),
      .bdo_valid(bdo_valid),
      .bdo_ready(bdo_ready),
      .bdo_type(bdo_type),
      .bdo_eot(bdo_eot),
      .msg_auth(msg_auth),
      .msg_auth_valid(msg_auth_valid),
      .msg_auth_ready(msg_auth_ready)
  );

  // Read one line of KAT file per cycle
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

  // Set persitent signals according to current line of KAT file
  always @(posedge clk) begin
    if (rst) begin
      decrypt_in <= 0;
      hash_in <= 0;
    end else begin
      if (op == OP_ENC) begin
        decrypt_in <= 0;
        hash_in <= 0;
      end else if (op == OP_DEC) begin
        decrypt_in <= 1;
        hash_in <= 0;
      end else if (op == OP_HASH) begin
        decrypt_in <= 0;
        hash_in <= 1;
      end
    end
  end

  // Set interface signals according to current line of KAT file
  always @(*) begin
    key = 0;
    key_valid = 0;
    bdi = 0;
    bdi_valid = 0;
    bdi_type = D_NULL;
    bdi_eot = 0;
    bdi_eoi = 0;
    bdo_ready = 0;
    msg_auth_ready = 0;

    if (hdr == "DAT") begin
      if (op == OP_LD_KEY) begin
        key = data;
        key_valid = 1;
      end
      if (op == OP_LD_NONCE | op == OP_LD_AD | op == OP_LD_MSG | op == OP_LD_TAG) begin
        bdi = data;
        bdi_valid = 1;
        if (op == OP_LD_NONCE) bdi_type = D_NONCE;
        if (op == OP_LD_AD) bdi_type = D_AD;
        if (op == OP_LD_MSG) begin
          bdi_type  = D_MSG;
          bdo_ready = 1;  // fix: handle output stall?
        end
        if (op == OP_LD_TAG) begin
          bdi_type = D_TAG;
          msg_auth_ready = 1;
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
  end

  // Print message output from Ascon core
  always @(posedge clk) begin
    if (bdo_valid) begin
      if (bdo_type == D_MSG) $display("msg => %h", bdo);
      if (bdo_type == D_TAG) $display("tag => %h", bdo);
    end
  end

  // Print tag verification output from Ascon core
  always @(posedge msg_auth_valid) begin
      $display("ver => %h", msg_auth);
  end

  // Generate clock signal
  always #5 clk = !clk;

  // Open KAT file
  initial begin
    fd = $fopen(KAT_FILE, "r");
  end

  // Specify debug variables and set simulation start/finish
  initial begin
    $dumpfile(VCD_FILE);
    $dumpvars(0, clk, rst, op, data, tb_word_cnt, key, key_valid, key_ready, bdi, bdi_valid,
              bdi_ready, bdi_type, bdi_eot, bdi_eoi, decrypt_in, hash_in, bdo, bdo_valid,
              bdo_ready, bdo_type, bdo_eot, msg_auth_valid, msg_auth_ready, msg_auth);
    #1;
    rst = 1;
    #10;
    rst = 0;
    #(SIM_CYCLES * 10);
    $fclose(fd);
    $finish;
  end

endmodule  // tb
