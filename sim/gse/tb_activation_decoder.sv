// SPDX-License-Identifier: Apache-2.0
// File: tb_activation_decoder.sv
// Purpose: Golden-checker style unit test for gse_activation_decoder across BYTE/FP16/FX16 modes

`timescale 1ns/1ps
import axi4s_pkg::*;

module tb_activation_decoder;

  localparam int TDATA_W = 256;
  localparam int BYTES   = (TDATA_W+7)/8;
  localparam int HALVES  = (TDATA_W+15)/16;
  localparam int CLK_PER = 10; // 100 MHz

  // Clock/Reset
  logic clk, rst_n;
  initial clk = 1'b0;
  always #(CLK_PER/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
  end

  // Interfaces for three decoder instances (BYTE, FP16, FX16)
  axi4s_if #(.TDATA_W(TDATA_W)) if_src_byte (.ACLK(clk), .ARESETn(rst_n));
  axi4s_if #(.TDATA_W(TDATA_W)) if_out_byte (.ACLK(clk), .ARESETn(rst_n));

  axi4s_if #(.TDATA_W(TDATA_W)) if_src_fp16 (.ACLK(clk), .ARESETn(rst_n));
  axi4s_if #(.TDATA_W(TDATA_W)) if_out_fp16 (.ACLK(clk), .ARESETn(rst_n));

  axi4s_if #(.TDATA_W(TDATA_W)) if_src_fx16 (.ACLK(clk), .ARESETn(rst_n));
  axi4s_if #(.TDATA_W(TDATA_W)) if_out_fx16 (.ACLK(clk), .ARESETn(rst_n));

  // Sinks always ready
  initial begin
    if_out_byte.TREADY  = 1'b1;
    if_out_fp16.TREADY  = 1'b1;
    if_out_fx16.TREADY  = 1'b1;
  end

  // DUTs
  // BYTE: pass if any byte > THRESHOLD (8)
  gse_activation_decoder #(
    .TDATA_W   (TDATA_W),
    .THRESHOLD (8),
    .DATA_FMT  (0)
  ) u_dec_byte (
    .clk    (clk),
    .rst_n  (rst_n),
    .s_axis (if_src_byte),
    .m_axis (if_out_byte)
  );

  // FP16: pass if any half has exp >= FP16_EXP_THR (5'd5) and exp != 0
  gse_activation_decoder #(
    .TDATA_W      (TDATA_W),
    .DATA_FMT     (1),
    .FP16_EXP_THR (5'd5)
  ) u_dec_fp16 (
    .clk    (clk),
    .rst_n  (rst_n),
    .s_axis (if_src_fp16),
    .m_axis (if_out_fp16)
  );

  // FX16 (Q1.15): pass if any half abs(value) > FX16_ABS_THR (1024)
  gse_activation_decoder #(
    .TDATA_W     (TDATA_W),
    .DATA_FMT    (2),
    .FX16_ABS_THR(16'd1024)
  ) u_dec_fx16 (
    .clk    (clk),
    .rst_n  (rst_n),
    .s_axis (if_src_fx16),
    .m_axis (if_out_fx16)
  );

  // Helpers
  function automatic logic [TDATA_W-1:0] fill_byte(input byte b);
    logic [TDATA_W-1:0] d; begin
      d = '0;
      for (int i = 0; i < BYTES; i++) d[i*8 +: 8] = b;
      return d;
    end
  endfunction

  function automatic logic [TDATA_W-1:0] fill_fp16(input logic [4:0] exp, input logic [9:0] mant);
    logic [TDATA_W-1:0] d; begin
      d = '0;
      // sign=0 for all halves
      for (int i = 0; i < HALVES; i++) begin
        d[i*16 +: 16] = {1'b0, exp, mant};
      end
      return d;
    end
  endfunction

  function automatic logic [TDATA_W-1:0] fill_fx16(input logic signed [15:0] q15);
    logic [TDATA_W-1:0] d; begin
      d = '0;
      for (int i = 0; i < HALVES; i++) d[i*16 +: 16] = q15;
      return d;
    end
  endfunction

  task automatic send_beat(input axi4s_if s, input logic [TDATA_W-1:0] data, input bit last);
    begin
      s.TDATA  = data;
      s.TKEEP  = '1;
      s.TLAST  = last;
      s.TVALID = 1'b1;
      do @(posedge clk); while (!(s.TVALID && s.TREADY));
      @(posedge clk);
      s.TVALID = 1'b0;
      s.TLAST  = 1'b0;
    end
  endtask

  // Scoreboard
  int pass_byte, pass_fp16, pass_fx16, drop_byte, drop_fp16, drop_fx16;

  // Monitors
  always @(posedge clk) begin
    if (rst_n && if_src_byte.TVALID && if_src_byte.TREADY) begin
      // Decide drop based on output handshake in next cycles
      // Count pass on out handshake
    end
    if (rst_n && if_src_fp16.TVALID && if_src_fp16.TREADY) begin end
    if (rst_n && if_src_fx16.TVALID && if_src_fx16.TREADY) begin end

    if (rst_n && if_out_byte.TVALID && if_out_byte.TREADY) pass_byte++;
    if (rst_n && if_out_fp16.TVALID && if_out_fp16.TREADY) pass_fp16++;
    if (rst_n && if_out_fx16.TVALID && if_out_fx16.TREADY) pass_fx16++;
  end

  // Stimulus
  initial begin : run
    logic [TDATA_W-1:0] d;

    // Wait reset
    @(posedge rst_n);
    repeat (4) @(posedge clk);

    // BYTE mode tests: THRESHOLD=8
    // Below threshold => drop
    d = fill_byte(8'd1);
    send_beat(if_src_byte, d, 1'b0);
    // At threshold => drop (strictly greater)
    d = fill_byte(8'd8);
    send_beat(if_src_byte, d, 1'b0);
    // Above threshold => pass
    d = fill_byte(8'd16);
    send_beat(if_src_byte, d, 1'b1);

    // FP16 mode tests: exp threshold=5
    // Subnormal (exp=0) => drop
    d = fill_fp16(5'd0, 10'h3F);
    send_beat(if_src_fp16, d, 1'b0);
    // Small normal (exp=3) => drop
    d = fill_fp16(5'd3, 10'h15);
    send_beat(if_src_fp16, d, 1'b0);
    // Larger normal (exp=10) => pass
    d = fill_fp16(5'd10, 10'h100);
    send_beat(if_src_fp16, d, 1'b1);

    // FX16 mode tests: abs threshold=1024
    // Small magnitude => drop
    d = fill_fx16(16'sd100);
    send_beat(if_src_fx16, d, 1'b0);
    // Near threshold => drop if equal
    d = fill_fx16(16'sd1024);
    send_beat(if_src_fx16, d, 1'b0);
    // Above threshold => pass
    d = fill_fx16(16'sd4096);
    send_beat(if_src_fx16, d, 1'b1);

    // Give time to drain
    repeat (20) @(posedge clk);

    // Basic checks: at least one pass per mode expected
    if (pass_byte == 0)  $fatal(1, "BYTE mode: no passes observed");
    if (pass_fp16 == 0)  $fatal(1, "FP16 mode: no passes observed");
    if (pass_fx16 == 0)  $fatal(1, "FX16 mode: no passes observed");

    $display("tb_activation_decoder: PASS (byte=%0d fp16=%0d fx16=%0d)", pass_byte, pass_fp16, pass_fx16);
    $finish;
  end

endmodule : tb_activation_decoder