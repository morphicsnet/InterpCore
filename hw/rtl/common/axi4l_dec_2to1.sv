// SPDX-License-Identifier: Apache-2.0
// File: axi4l_dec_2to1.sv
// Purpose: Simple AXI4-Lite 1x2 address decoder (one master -> two slaves)
// Notes:
// - Decodes AW/AR on ADDR_SEL_BIT to select slave 0 or 1
// - Latches write/read selection until BRESP/RRESP completes
// - Assumes AW arrives before W (typical for AXI4-Lite); if W arrives first,
//   WREADY will wait until AW has selected a target slave
//
// Clock/Reset Domain: clk / rst_n (active-low)

`timescale 1ns/1ps
import axi4l_pkg::*;

module axi4l_dec_2to1 #(
  parameter int ADDR_SEL_BIT = 12
) (
  input  logic      clk,
  input  logic      rst_n,

  // Single upstream master (as seen by decoder)
  axi4l_if.slave    s_axi,

  // Downstream slaves (decoder drives as master)
  axi4l_if.master   m_axi0,
  axi4l_if.master   m_axi1
);

  // ----------------------------
  // Write address/data path
  // ----------------------------

  // Latch which slave a write targets until BRESP handshake completes
  logic wr_sel_q;         // 0 -> m_axi0, 1 -> m_axi1
  logic wr_active_q;      // a write transaction is outstanding

  // Decode selection from AWADDR
  wire  aw_sel = s_axi.AWADDR[ADDR_SEL_BIT];

  // Default: deassert all downstreams
  always_comb begin
    // Default downstream AW/W
    m_axi0.AWADDR  = '0;
    m_axi0.AWPROT  = '0;
    m_axi0.AWVALID = 1'b0;

    m_axi0.WDATA   = '0;
    m_axi0.WSTRB   = '0;
    m_axi0.WVALID  = 1'b0;

    m_axi1.AWADDR  = '0;
    m_axi1.AWPROT  = '0;
    m_axi1.AWVALID = 1'b0;

    m_axi1.WDATA   = '0;
    m_axi1.WSTRB   = '0;
    m_axi1.WVALID  = 1'b0;

    // Upstream ready defaults
    s_axi.AWREADY  = 1'b0;
    s_axi.WREADY   = 1'b0;

    // Drive selected slave when address is presented (AWVALID)
    if (s_axi.AWVALID) begin
      if (aw_sel == 1'b0) begin
        m_axi0.AWADDR  = s_axi.AWADDR;
        m_axi0.AWPROT  = s_axi.AWPROT;
        m_axi0.AWVALID = 1'b1;
        s_axi.AWREADY  = m_axi0.AWREADY;
      end else begin
        m_axi1.AWADDR  = s_axi.AWADDR;
        m_axi1.AWPROT  = s_axi.AWPROT;
        m_axi1.AWVALID = 1'b1;
        s_axi.AWREADY  = m_axi1.AWREADY;
      end
    end

    // Route W to the currently latched write selection (once AW accepted)
    if (wr_active_q && s_axi.WVALID) begin
      if (wr_sel_q == 1'b0) begin
        m_axi0.WDATA   = s_axi.WDATA;
        m_axi0.WSTRB   = s_axi.WSTRB;
        m_axi0.WVALID  = 1'b1;
        s_axi.WREADY   = m_axi0.WREADY;
      end else begin
        m_axi1.WDATA   = s_axi.WDATA;
        m_axi1.WSTRB   = s_axi.WSTRB;
        m_axi1.WVALID  = 1'b1;
        s_axi.WREADY   = m_axi1.WREADY;
      end
    end
  end

  // ----------------------------
  // Write response mux
  // ----------------------------
  always_comb begin
    // Default upstream B response
    s_axi.BVALID = 1'b0;
    s_axi.BRESP  = 2'b00;

    // Downstream BREADY from upstream
    m_axi0.BREADY = 1'b0;
    m_axi1.BREADY = 1'b0;

    if (wr_active_q) begin
      if (wr_sel_q == 1'b0) begin
        s_axi.BVALID = m_axi0.BVALID;
        s_axi.BRESP  = m_axi0.BRESP;
        m_axi0.BREADY = s_axi.BREADY;
      end else begin
        s_axi.BVALID = m_axi1.BVALID;
        s_axi.BRESP  = m_axi1.BRESP;
        m_axi1.BREADY = s_axi.BREADY;
      end
    end
  end

  // ----------------------------
  // Read address/data path
  // ----------------------------
  logic rd_sel_q;     // 0 -> m_axi0, 1 -> m_axi1
  logic rd_active_q;

  wire  ar_sel = s_axi.ARADDR[ADDR_SEL_BIT];

  // AR demux
  always_comb begin
    // Default downstream AR
    m_axi0.ARADDR  = '0;
    m_axi0.ARPROT  = '0;
    m_axi0.ARVALID = 1'b0;

    m_axi1.ARADDR  = '0;
    m_axi1.ARPROT  = '0;
    m_axi1.ARVALID = 1'b0;

    // Default upstream ready
    s_axi.ARREADY  = 1'b0;

    if (s_axi.ARVALID) begin
      if (ar_sel == 1'b0) begin
        m_axi0.ARADDR  = s_axi.ARADDR;
        m_axi0.ARPROT  = s_axi.ARPROT;
        m_axi0.ARVALID = 1'b1;
        s_axi.ARREADY  = m_axi0.ARREADY;
      end else begin
        m_axi1.ARADDR  = s_axi.ARADDR;
        m_axi1.ARPROT  = s_axi.ARPROT;
        m_axi1.ARVALID = 1'b1;
        s_axi.ARREADY  = m_axi1.ARREADY;
      end
    end
  end

  // R mux
  always_comb begin
    // Defaults
    s_axi.RVALID = 1'b0;
    s_axi.RDATA  = '0;
    s_axi.RRESP  = 2'b00;

    m_axi0.RREADY = 1'b0;
    m_axi1.RREADY = 1'b0;

    if (rd_active_q) begin
      if (rd_sel_q == 1'b0) begin
        s_axi.RVALID = m_axi0.RVALID;
        s_axi.RDATA  = m_axi0.RDATA;
        s_axi.RRESP  = m_axi0.RRESP;
        m_axi0.RREADY = s_axi.RREADY;
      end else begin
        s_axi.RVALID = m_axi1.RVALID;
        s_axi.RDATA  = m_axi1.RDATA;
        s_axi.RRESP  = m_axi1.RRESP;
        m_axi1.RREADY = s_axi.RREADY;
      end
    end
  end

  // ----------------------------
  // Sequential state
  // ----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_sel_q     <= 1'b0;
      wr_active_q  <= 1'b0;
      rd_sel_q     <= 1'b0;
      rd_active_q  <= 1'b0;
    end else begin
      // Latch write selection when AW handshake happens
      if (s_axi.AWVALID && s_axi.AWREADY) begin
        wr_sel_q    <= aw_sel;
        wr_active_q <= 1'b1;
      end
      // Clear write active on B handshake
      if (s_axi.BVALID && s_axi.BREADY) begin
        wr_active_q <= 1'b0;
      end

      // Latch read selection when AR handshake happens
      if (s_axi.ARVALID && s_axi.ARREADY) begin
        rd_sel_q    <= ar_sel;
        rd_active_q <= 1'b1;
      end
      // Clear read active on R handshake
      if (s_axi.RVALID && s_axi.RREADY) begin
        rd_active_q <= 1'b0;
      end
    end
  end

endmodule : axi4l_dec_2to1