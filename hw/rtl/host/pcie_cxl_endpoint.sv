// SPDX-License-Identifier: Apache-2.0
// File: pcie_cxl_endpoint.sv
// Purpose: Host PCIe/CXL endpoint stub (no vendor IP) with BARs/MSI-X and AXI-MM master shell
// Clock/Reset Domain: clk_host / rstn_host (active-low)
// TODO:
// - Replace with actual endpoint integration
// - Hook BAR decode to CSR window
// - Connect AXI-MM to DMA engine

module pcie_cxl_endpoint #(
  parameter int AXI_ADDR_W = 64,
  parameter int AXI_DATA_W = 256,
  parameter int AXI_STRB_W = AXI_DATA_W/8,
  parameter int MSI_VEC_W  = 16
) (
  input  logic clk_host,
  input  logic rstn_host,

  // BAR window bases (signals only)
  input  logic [AXI_ADDR_W-1:0] bar0_base,
  input  logic [AXI_ADDR_W-1:0] bar1_base,

  // MSI-X vectors out
  output logic [MSI_VEC_W-1:0]  msix_vec,

  // AXI-MM master outbound to DMA/memory system (placeholders)
  output logic [AXI_ADDR_W-1:0] m_axi_awaddr,
  output logic [7:0]            m_axi_awlen,
  output logic [2:0]            m_axi_awsize,
  output logic [1:0]            m_axi_awburst,
  output logic                  m_axi_awvalid,
  input  logic                  m_axi_awready,

  output logic [AXI_DATA_W-1:0] m_axi_wdata,
  output logic [AXI_STRB_W-1:0] m_axi_wstrb,
  output logic                  m_axi_wlast,
  output logic                  m_axi_wvalid,
  input  logic                  m_axi_wready,

  input  logic [1:0]            m_axi_bresp,
  input  logic                  m_axi_bvalid,
  output logic                  m_axi_bready,

  output logic [AXI_ADDR_W-1:0] m_axi_araddr,
  output logic [7:0]            m_axi_arlen,
  output logic [2:0]            m_axi_arsize,
  output logic [1:0]            m_axi_arburst,
  output logic                  m_axi_arvalid,
  input  logic                  m_axi_arready,

  input  logic [AXI_DATA_W-1:0] m_axi_rdata,
  input  logic [1:0]            m_axi_rresp,
  input  logic                  m_axi_rlast,
  input  logic                  m_axi_rvalid,
  output logic                  m_axi_rready,

  // CSR master towards SoC over AXI-Lite via bridge
  axi4l_if.master               m_axi_csr
);
  // Minimal AXI-Lite CSR master one-shot write to offset 0x0 after reset
  // Write data: 0x0000_0000 (placeholder)
  logic awvalid_q, wvalid_q, wr_done_q;

  // Static defaults for non-CSR AXI-MM (remain idle)
  always_comb begin
    msix_vec      = '0;

    m_axi_awaddr  = '0;
    m_axi_awlen   = '0;
    m_axi_awsize  = '0;
    m_axi_awburst = '0;
    m_axi_awvalid = 1'b0;

    m_axi_wdata   = '0;
    m_axi_wstrb   = '0;
    m_axi_wlast   = 1'b0;
    m_axi_wvalid  = 1'b0;

    m_axi_bready  = 1'b1;

    m_axi_araddr  = '0;
    m_axi_arlen   = '0;
    m_axi_arsize  = '0;
    m_axi_arburst = '0;
    m_axi_arvalid = 1'b0;

    m_axi_rready  = 1'b1;

    // AXI-Lite CSR master: one-shot write
    m_axi_csr.AWADDR  = 32'h0000_0000;
    m_axi_csr.AWPROT  = 3'b000;
    m_axi_csr.AWVALID = awvalid_q & ~wr_done_q;

    m_axi_csr.WDATA   = 32'h0000_0000;
    m_axi_csr.WSTRB   = 4'hF;
    m_axi_csr.WVALID  = wvalid_q & ~wr_done_q;

    m_axi_csr.BREADY  = 1'b1;

    // No reads issued
    m_axi_csr.ARADDR  = '0;
    m_axi_csr.ARPROT  = 3'b000;
    m_axi_csr.ARVALID = 1'b0;

    m_axi_csr.RREADY  = 1'b1;
  end

  // Simple CSR write FSM via registered valids
  always_ff @(posedge clk_host or negedge rstn_host) begin
    if (!rstn_host) begin
      awvalid_q <= 1'b1;
      wvalid_q  <= 1'b1;
      wr_done_q <= 1'b0;
    end else begin
      // Address handshake
      if (m_axi_csr.AWVALID && m_axi_csr.AWREADY) begin
        awvalid_q <= 1'b0;
      end
      // Data handshake
      if (m_axi_csr.WVALID && m_axi_csr.WREADY) begin
        wvalid_q <= 1'b0;
      end
      // Completion on write response
      if (m_axi_csr.BREADY && m_axi_csr.BVALID) begin
        wr_done_q <= 1'b1;
      end
    end
  end

endmodule : pcie_cxl_endpoint
