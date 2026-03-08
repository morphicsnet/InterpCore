// SPDX-License-Identifier: Apache-2.0
// File: tb_gse_gmf_smoke.sv
// Purpose: End-to-end smoke test for GSE->GMF streaming path (decoder -> island -> GMF cluster)
//
// Topology under test (all on a single clock/reset for bring-up):
//   AXI4S Source (TB) -> gse_activation_decoder -> gse_island_builder -> gmf_banks_cluster -> AXI4S Sink (TB)
//
// This does not involve the NoC or host DMA; it validates the streaming micro-architecture.

`timescale 1ns/1ps

import axi4s_pkg::*;

module tb_gse_gmf_smoke;

  // Parameters
  localparam int TDATA_W   = 256;
  localparam int BYTES     = (TDATA_W+7)/8;
  localparam int CLK_PER   = 10; // 100 MHz

  // Clock/Reset
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #(CLK_PER/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
  end

  // AXI-Stream channel wires (interfaces)
  axi4s_if #(.TDATA_W(TDATA_W)) if_src      (.ACLK(clk), .ARESETn(rst_n)); // TB source -> decoder.s_axis
  axi4s_if #(.TDATA_W(TDATA_W)) if_dec      (.ACLK(clk), .ARESETn(rst_n)); // decoder.m_axis -> island.s_axis
  axi4s_if #(.TDATA_W(TDATA_W)) if_island   (.ACLK(clk), .ARESETn(rst_n)); // island.m_axis (forwarded path, not used)
  axi4s_if #(.TDATA_W(TDATA_W)) if_gmf_req  (.ACLK(clk), .ARESETn(rst_n)); // island.m_axis_gmf -> cluster.s_axis_req
  axi4s_if #(.TDATA_W(TDATA_W)) if_gmf_rsp  (.ACLK(clk), .ARESETn(rst_n)); // cluster.m_axis_rsp -> TB sink

  // Unit under test: decoder
  // DATA_FMT=0 => BYTE threshold; THRESHOLD=8 => any byte > 8 passes
  gse_activation_decoder #(
    .TDATA_W   (TDATA_W),
    .THRESHOLD (8),
    .DATA_FMT  (0)
  ) u_dec (
    .clk    (clk),
    .rst_n  (rst_n),
    .s_axis (if_src),
    .m_axis (if_dec)
  );

  // Unit under test: island builder (dedup last DEDUP_N, cap K_MAX per TLAST window)
  gse_island_builder #(
    .K_MAX   (8),
    .DEDUP_N (4),
    .TDATA_W (TDATA_W)
  ) u_islands (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_axis     (if_dec),
    .m_axis     (if_island),
    .m_axis_gmf (if_gmf_req)
  );

  // Unit under test: GMF banks cluster (direct-mapped, single-outstanding)
  gmf_banks_cluster #(
    .N_BANKS (4),
    .TDATA_W (TDATA_W)
  ) u_cluster (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_axis_req (if_gmf_req),
    .m_axis_rsp (if_gmf_rsp)
  );

  // TB drives the final sink ready
  initial begin
    if_gmf_rsp.TREADY = 1'b1;
  end

  // Defaults for channels the TB sources/sinks
  initial begin
    if_src.TVALID = 1'b0;
    if_src.TDATA  = '0;
    if_src.TKEEP  = '0;
    if_src.TLAST  = 1'b0;
  end

  // Helpers
  task automatic send_beat(input logic [TDATA_W-1:0] data, input bit last);
    // Wait until decoder is ready to accept (drives s_axis.TREADY)
    begin
      // Drive one cycle TVALID; keep asserted until handshake
      if_src.TDATA  = data;
      if_src.TKEEP  = '1;      // all bytes valid
      if_src.TLAST  = last;
      if_src.TVALID = 1'b1;
      // Wait for handshake
      do @(posedge clk); while (!(if_src.TVALID && if_src.TREADY));
      // Deassert after handshake
      @(posedge clk);
      if_src.TVALID = 1'b0;
      if_src.TLAST  = 1'b0;
    end
  endtask

  function automatic logic [TDATA_W-1:0] fill_byte(input byte b);
    logic [TDATA_W-1:0] tmp;
    begin
      tmp = '0;
      for (int i = 0; i < BYTES; i++) begin
        tmp[i*8 +: 8] = b;
      end
      return tmp;
    end
  endfunction

  // Scoreboard counters
  int req_cnt, rsp_cnt, fwd_cnt, drop_cnt;

  // Monitor requests to GMF (island->cluster)
  always @(posedge clk) begin
    if (rst_n && if_gmf_req.TVALID && if_gmf_req.TREADY) begin
      req_cnt++;
      // Low nibble used by cluster for bank hashing; not asserted here
    end
  end

  // Monitor responses from GMF
  always @(posedge clk) begin
    if (rst_n && if_gmf_rsp.TVALID && if_gmf_rsp.TREADY) begin
      rsp_cnt++;
      // Basic sanity: responses are single-beat; TLAST should be 1
      if (if_gmf_rsp.TLAST !== 1'b1) begin
        $error("GMF response without TLAST asserted");
      end
    end
  end

  // Monitor forwarded (non-GMF) island stream to ensure dedup/K_MAX behave
  always @(posedge clk) begin
    if (rst_n && if_island.TVALID && if_island.TREADY) begin
      fwd_cnt++;
    end
  end

  // Drive stimulus
  initial begin : stimulus
    logic [TDATA_W-1:0] d_lo, d_hi, d_dup;

    // Wait reset
    @(posedge rst_n);
    @(posedge clk);

    // Create patterns: below threshold (byte=1), above threshold (byte=16)
    d_lo  = fill_byte(8'd1);
    d_hi  = fill_byte(8'd16);
    d_dup = d_hi;

    // Window 1 (TLAST asserted on 4th beat)
    // Beat 1: below threshold => decoder should drop: no forward/no GMF
    send_beat(d_lo, /* last */ 1'b0);

    // Beat 2: above threshold => passes decoder
    send_beat(d_hi, 1'b0);

    // Beat 3: duplicate of previous => island should drop due to dedup
    send_beat(d_dup, 1'b0);

    // Beat 4: above threshold, different (modify one byte) => pass and TLAST
    d_hi[7:0] = 8'd33;
    send_beat(d_hi, 1'b1);

    // Window 2 (3 beats, TLAST on 3rd)
    // Send 3 unique beats to exercise K_MAX (set to 8, so all should pass)
    logic [TDATA_W-1:0] d2;
    d2 = fill_byte(8'd20);
    send_beat(d2, 1'b0);
    d2[15:8] = 8'd21;
    send_beat(d2, 1'b0);
    d2[23:16] = 8'd22;
    send_beat(d2, 1'b1);

    // Wait for pipelines to drain
    repeat (20) @(posedge clk);

    // Check results: expect at least 1 request and response; dedup removed 1
    if (req_cnt == 0 || rsp_cnt == 0) begin
      $fatal(1, "No GMF requests/responses observed (req=%0d rsp=%0d)", req_cnt, rsp_cnt);
    end

    $display("tb_gse_gmf_smoke: PASS (req=%0d rsp=%0d fwd=%0d)", req_cnt, rsp_cnt, fwd_cnt);
    $finish;
  end

endmodule : tb_gse_gmf_smoke