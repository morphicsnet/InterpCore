// SPDX-License-Identifier: Apache-2.0
// File: dma_engine.sv
// Purpose: DMA stub with AXI4-Stream ingress/egress and AXI4-Lite control
// Clock/Reset Domain: clk_host / rstn_host (active-low)
// TODO:
// - Implement descriptor fetch/consume
// - Add completion/status tracking
// - Connect to NoC bridges for memory interface

import axi4l_pkg::*;
import axi4s_pkg::*;

module dma_engine #(
  parameter int TDATA_W = 256
) (
  input  logic      clk_host,
  input  logic      rstn_host,

  // Control/CSR
  axi4l_if.slave    s_axi_ctl,

  // Ingress stream (to fabric or GSE)
  axi4s_if.master   m_axis_ingress,

  // Egress stream (from fabric or GMF)
  axi4s_if.slave    s_axis_egress,

  // Descriptor ring placeholders
  input  logic [63:0] desc_ring_base,
  input  logic [15:0] desc_ring_size,
  output logic        desc_fetch_req
);

  // Minimal AXI-Lite CSR handling and stream tie-offs
  logic bvalid_q, rvalid_q, desc_req_q;
  // Simple traffic generator for ingress stream on CONTROL write
  logic              gen_active_q;
  logic [15:0]       gen_cnt_q;
  localparam int     GEN_BEATS = 16;

  always_comb begin
    // AXI-Lite ready/valids
    s_axi_ctl.AWREADY = rstn_host & ~bvalid_q;
    s_axi_ctl.WREADY  = rstn_host & ~bvalid_q;
    s_axi_ctl.ARREADY = rstn_host & ~rvalid_q;

    s_axi_ctl.BRESP   = 2'b00; // OKAY
    s_axi_ctl.BVALID  = bvalid_q;
    s_axi_ctl.RDATA   = '0;
    s_axi_ctl.RRESP   = 2'b00; // OKAY
    s_axi_ctl.RVALID  = rvalid_q;

    // Streams: drive from generator when active; otherwise idle
    m_axis_ingress.TVALID = 1'b0;
    m_axis_ingress.TDATA  = '0;
    m_axis_ingress.TKEEP  = '0;
    m_axis_ingress.TLAST  = 1'b0;

    // Build a simple patterned payload using remaining beat count
    logic [TDATA_W-1:0] gen_bus;
    gen_bus = '0;
    for (int w = 0; w < TDATA_W; w += 32) begin
      gen_bus[w +: 32] = {16'hC0DE, gen_cnt_q};
    end

    if (gen_active_q) begin
      m_axis_ingress.TVALID = 1'b1;
      m_axis_ingress.TDATA  = gen_bus;
      m_axis_ingress.TKEEP  = '1;                 // full keep
      m_axis_ingress.TLAST  = (gen_cnt_q == 16'd1);
    end

    // Egress sink always ready
    s_axis_egress.TREADY  = 1'b1;

    // One-cycle pulse on CONTROL write (bit0)
    desc_fetch_req = desc_req_q;
  end

  always_ff @(posedge clk_host or negedge rstn_host) begin
    if (!rstn_host) begin
      bvalid_q     <= 1'b0;
      rvalid_q     <= 1'b0;
      desc_req_q   <= 1'b0;
      gen_active_q <= 1'b0;
      gen_cnt_q    <= '0;
    end else begin
      // Default clear of desc request pulse
      desc_req_q <= 1'b0;

      // Write commit when both address and data are accepted
      if (s_axi_ctl.AWVALID && s_axi_ctl.AWREADY &&
          s_axi_ctl.WVALID  && s_axi_ctl.WREADY  &&
          !bvalid_q) begin
        bvalid_q   <= 1'b1;
        // Pulse desc request if CONTROL bit0 is set
        if (s_axi_ctl.WDATA[0]) desc_req_q <= 1'b1;
      end
      // Complete write response
      if (s_axi_ctl.BVALID && s_axi_ctl.BREADY) begin
        bvalid_q <= 1'b0;
      end

      // Read commit
      if (s_axi_ctl.ARVALID && s_axi_ctl.ARREADY && !rvalid_q) begin
        rvalid_q <= 1'b1;
      end
      // Complete read
      if (s_axi_ctl.RVALID && s_axi_ctl.RREADY) begin
        rvalid_q <= 1'b0;
      end

      // Start generator on control pulse if idle
      if (desc_req_q && !gen_active_q) begin
        gen_active_q <= 1'b1;
        gen_cnt_q    <= GEN_BEATS[15:0];
      end

      // Advance generator on successful stream beat
      if (gen_active_q && m_axis_ingress.TVALID && m_axis_ingress.TREADY) begin
        if (gen_cnt_q > 16'd1) begin
          gen_cnt_q <= gen_cnt_q - 16'd1;
        end else begin
          // Last beat consumed
          gen_cnt_q    <= 16'd0;
          gen_active_q <= 1'b0;
        end
      end
    end
  end

endmodule : dma_engine
