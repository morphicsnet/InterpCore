// SPDX-License-Identifier: Apache-2.0
// File: nsi_cp_top.sv
// Purpose: NSI-CP chip-level top: domains, host CSR window, block placeholders
// Clock/Reset Domains:
//   - clk_fsm_1g / rstn_fsm_1g (FSM pipeline)
//   - clk_fab_700m / rstn_fab_700m (NoC/fabric)
//   - clk_host / rstn_host (host/CSR/DMA)
//   - clk_mc / rstn_mc (microcontroller/CSR subsystem)
// TODO:
// - Connect NoC/AXI bridges
// - Instantiate sub-blocks and CDCs (add synthesis attributes on CDC paths)

`timescale 1ns/1ps
import axi4l_pkg::*;
import axi4s_pkg::*;
import noc_pkg::*;
import util_pkg::*;

module nsi_cp_top (
  input  logic clk_fsm_1g,
  input  logic clk_fab_700m,
  input  logic clk_host,
  input  logic clk_mc,

  input  logic rstn_fsm_1g,
  input  logic rstn_fab_700m,
  input  logic rstn_host,
  input  logic rstn_mc,

  // AXI-Lite CSR host window (via bridge later)
  axi4l_if.slave s_axi_csr
);

  // CDC TODO marker example
  (* keep = "true" *) logic cdc_todo_fsm2fab;
  // TODO: connect and synchronize signals crossing between domains

  // Fabric NoC local loopback scaffolding and CSR block
  // Local constants for router wiring
  localparam int VCS    = noc_pkg::NOC_VC_NUM;
  localparam int FLIT_W = noc_pkg::NOC_FLIT_W;
  localparam int P_N = 0;
  localparam int P_S = 1;
  localparam int P_E = 2;
  localparam int P_W = 3;
  localparam int P_L = 4;

  // NoC arrays
  logic                  in_valid [5][VCS];
  logic                  in_ready [5][VCS];
  logic [FLIT_W-1:0]     in_flit  [5][VCS];
  logic                  out_valid[5][VCS];
  logic                  out_ready[5][VCS];
  logic [FLIT_W-1:0]     out_flit [5][VCS];
  logic [7:0]            credit_in [5][VCS];
  logic [7:0]            credit_out[5][VCS];

  // AXI4-Lite master interface from host endpoint to NoC bridge (host domain)
  axi4l_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) csr_ep_if (.clk(clk_host), .rst_n(rstn_host));

  // Host endpoint (stub) — BARs/MSI and AXI-MM are currently unused; tie off locally
  logic [15:0]            ep_msix_vec;
  logic [63:0]            ep_awaddr, ep_araddr;
  logic [7:0]             ep_awlen,  ep_arlen;
  logic [2:0]             ep_awsize, ep_arsize;
  logic [1:0]             ep_awburst, ep_arburst;
  logic                   ep_awvalid, ep_wlast, ep_wvalid, ep_arvalid;
  logic                   ep_awready, ep_wready, ep_arready;
  logic [255:0]           ep_wdata;
  logic [31:0]            ep_wstrb;
  logic [1:0]             ep_bresp, ep_rresp;
  logic                   ep_bvalid, ep_bready;
  logic [255:0]           ep_rdata;
  logic                   ep_rlast, ep_rvalid, ep_rready;

  // Tie-off unused AXI-MM inputs toward endpoint
  assign ep_awready = 1'b0;
  assign ep_wready  = 1'b0;
  assign ep_bresp   = 2'b00;
  assign ep_bvalid  = 1'b0;
  assign ep_arready = 1'b0;
  assign ep_rdata   = '0;
  assign ep_rresp   = 2'b00;
  assign ep_rlast   = 1'b0;
  assign ep_rvalid  = 1'b0;

  pcie_cxl_endpoint #(
    .AXI_ADDR_W(64),
    .AXI_DATA_W(256),
    .AXI_STRB_W(32),
    .MSI_VEC_W (16)
  ) u_host_ep (
    .clk_host     (clk_host),
    .rstn_host    (rstn_host),
    .bar0_base    (64'h0),
    .bar1_base    (64'h0),
    .msix_vec     (ep_msix_vec),
    // AXI-MM master (unused for now)
    .m_axi_awaddr (ep_awaddr),
    .m_axi_awlen  (ep_awlen),
    .m_axi_awsize (ep_awsize),
    .m_axi_awburst(ep_awburst),
    .m_axi_awvalid(ep_awvalid),
    .m_axi_awready(ep_awready),
    .m_axi_wdata  (ep_wdata),
    .m_axi_wstrb  (ep_wstrb),
    .m_axi_wlast  (ep_wlast),
    .m_axi_wvalid (ep_wvalid),
    .m_axi_wready (ep_wready),
    .m_axi_bresp  (ep_bresp),
    .m_axi_bvalid (ep_bvalid),
    .m_axi_bready (ep_bready),
    .m_axi_araddr (ep_araddr),
    .m_axi_arlen  (ep_arlen),
    .m_axi_arsize (ep_arsize),
    .m_axi_arburst(ep_arburst),
    .m_axi_arvalid(ep_arvalid),
    .m_axi_arready(ep_arready),
    .m_axi_rdata  (ep_rdata),
    .m_axi_rresp  (ep_rresp),
    .m_axi_rlast  (ep_rlast),
    .m_axi_rvalid (ep_rvalid),
    .m_axi_rready (ep_rready),
    // AXI-Lite CSR master
    .m_axi_csr    (csr_ep_if)
  );

  // AXI4-Lite → NoC bridge (VC0 control class) in host domain
  logic [FLIT_W-1:0] vc0_tx_flit, vc0_rx_flit;
  logic              vc0_tx_valid, vc0_tx_ready;
  logic              vc0_rx_valid, vc0_rx_ready;

  noc_bridge_axi4l #(
    .FLIT_W       (FLIT_W),
    .SRC_ID       (8'd1),
    .DST_ID       (8'd0),
    .TIMEOUT_CYCLES(4096),
    .WAIT_WR_RESP (1'b0)
  ) u_axil_bridge (
    .clk          (clk_host),
    .rst_n        (rstn_host),
    .s_axi        (csr_ep_if),
    .noc_tx_flit  (vc0_tx_flit),
    .noc_tx_valid (vc0_tx_valid),
    .noc_tx_ready (vc0_tx_ready),
    .noc_rx_flit  (vc0_rx_flit),
    .noc_rx_valid (vc0_rx_valid),
    .noc_rx_ready (vc0_rx_ready)
  );

  // Fabric defaults + local port VC0 override to connect bridge into router
  integer p_i, v_i;
  always_comb begin
    // Defaults
    for (p_i = 0; p_i < 5; p_i++) begin
      for (v_i = 0; v_i < VCS; v_i++) begin
        in_valid[p_i][v_i]  = 1'b0;
        in_flit [p_i][v_i]  = '0;
        out_ready[p_i][v_i] = 1'b1;
        credit_in[p_i][v_i] = '0;
      end
    end
    // Override local port VC0 connections
    in_valid[P_L][noc_pkg::VC0_CTRL]  = vc0_tx_valid;
    in_flit [P_L][noc_pkg::VC0_CTRL]  = vc0_tx_flit;
    vc0_tx_ready                      = in_ready[P_L][noc_pkg::VC0_CTRL];

    out_ready[P_L][noc_pkg::VC0_CTRL] = vc0_rx_ready;
    vc0_rx_valid                      = out_valid[P_L][noc_pkg::VC0_CTRL];
    vc0_rx_flit                       = out_flit [P_L][noc_pkg::VC0_CTRL];
  end

  // Minimal NoC router instance at coordinate (0,0)
  noc_router #(
    .FLIT_W(FLIT_W),
    .VCS   (VCS),
    .CUR_X (0),
    .CUR_Y (0)
  ) u_noc (
    .clk       (clk_fab_700m),
    .rst_n     (rstn_fab_700m),
    .in_valid  (in_valid),
    .in_ready  (in_ready),
    .in_flit   (in_flit),
    .out_valid (out_valid),
    .out_ready (out_ready),
    .out_flit  (out_flit),
    .credit_in (credit_in),
    .credit_out(credit_out)
  );

  // ----------------------------
  // GSE→GMF streaming pipeline (host domain for early bring-up)
  // dma_engine (AXI4L control stub) -> gse_activation_decoder
  // -> gse_island_builder -> gmf_banks_cluster -> dma_engine (egress)
  // ----------------------------

  // AXI4-Stream channels (host clock domain for simplicity)
  axi4s_if #(.TDATA_W(256)) if_gse_ing    (.ACLK(clk_host), .ARESETn(rstn_host));
  axi4s_if #(.TDATA_W(256)) if_gse_dec    (.ACLK(clk_host), .ARESETn(rstn_host));
  axi4s_if #(.TDATA_W(256)) if_gse_island (.ACLK(clk_host), .ARESETn(rstn_host));
  axi4s_if #(.TDATA_W(256)) if_gmf_req    (.ACLK(clk_host), .ARESETn(rstn_host));
  axi4s_if #(.TDATA_W(256)) if_gmf_rsp    (.ACLK(clk_host), .ARESETn(rstn_host));

  // AXI4-Lite control interface stub for DMA (not yet connected to a master)
  // CSR decode: route external CSR window to MC regs (slot 0) and DMA control (slot 1)
  axi4l_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dma_ctl_if (.clk(clk_host), .rst_n(rstn_host));
  axi4l_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) mc_csr_if  (.clk(clk_host), .rst_n(rstn_host));

  // Address decoder: use bit[12] to select 4KB windows
  //  - 0x0000-0x0FFF -> MC registers
  //  - 0x1000-0x1FFF -> DMA control
  axi4l_dec_2to1 #(
    .ADDR_SEL_BIT(12)
  ) u_csr_dec (
    .clk   (clk_host),
    .rst_n (rstn_host),
    .s_axi (s_axi_csr),
    .m_axi0(mc_csr_if),   // slot 0
    .m_axi1(dma_ctl_if)   // slot 1
  );

  // DMA engine: produces ingress stream, consumes GMF response stream
  dma_engine #(
    .TDATA_W(256)
  ) u_dma (
    .clk_host       (clk_host),
    .rstn_host      (rstn_host),
    .s_axi_ctl      (dma_ctl_if),
    .m_axis_ingress (if_gse_ing),
    .s_axis_egress  (if_gmf_rsp),
    .desc_ring_base ('0),
    .desc_ring_size ('0),
    .desc_fetch_req (/* unused */)
  );

  // GSE activation decoder (supports BYTE/FP16/FX16 threshold formats)
  gse_activation_decoder #(
    .TDATA_W   (256),
    .THRESHOLD (8'd0),
    .DATA_FMT  (0)       // 0=BYTE, 1=FP16, 2=FX16
  ) u_gse_dec (
    .clk    (clk_host),
    .rst_n  (rstn_host),
    .s_axis (if_gse_ing),
    .m_axis (if_gse_dec)
  );

  // GSE island builder: forwards filtered stream and emits GMF update stream
  gse_island_builder #(
    .K_MAX   (16),
    .DEDUP_N (4),
    .TDATA_W (256)
  ) u_gse_islands (
    .clk        (clk_host),
    .rst_n      (rstn_host),
    .s_axis     (if_gse_dec),
    .m_axis     (if_gse_island),
    .m_axis_gmf (if_gmf_req)
  );

  // GMF banks cluster (single-outstanding path), consume GSE GMF updates
  gmf_banks_cluster #(
    .N_BANKS (4),
    .TDATA_W (256)
  ) u_gmf_cluster (
    .clk       (clk_host),
    .rst_n     (rstn_host),
    .s_axis_req(if_gmf_req),
    .m_axis_rsp(if_gmf_rsp)
  );

  // Sink the forwarded island stream to keep pipeline progressing
  assign if_gse_island.TREADY = 1'b1;

  // ----------------------------
  // PTA minimal path: scheduler -> GMF cluster (host domain for bring-up)
  // ----------------------------
  axi4s_if #(.TDATA_W(256)) if_pta_req (.ACLK(clk_host), .ARESETn(rstn_host));
  axi4s_if #(.TDATA_W(256)) if_pta_rsp (.ACLK(clk_host), .ARESETn(rstn_host));

  // PTA scheduler: RR over NUM_PES; generates GMF requests directly
  localparam int PTA_NUM_PES = 4;
  logic [PTA_NUM_PES-1:0] pe_start_w;
  logic [PTA_NUM_PES-1:0] pe_idle_w;

  // For bring-up, mark all PEs idle and observe pe_start pulses on handshakes
  assign pe_idle_w = {PTA_NUM_PES{1'b1}};

  pta_scheduler #(
    .NUM_PES         (PTA_NUM_PES),
    .CONTEXTS_PER_PE (8),
    .TDATA_W         (256)
  ) u_pta_sched (
    .clk            (clk_host),
    .rst_n          (rstn_host),
    .pe_start       (pe_start_w),
    .pe_idle        (pe_idle_w),
    .m_axis_gmf_req (if_pta_req),
    .s_axis_gmf_rsp (if_pta_rsp)
  );

  // Dedicated GMF cluster for PTA path (avoids request muxing for bring-up)
  gmf_banks_cluster #(
    .N_BANKS (4),
    .TDATA_W (256)
  ) u_gmf_cluster_pta (
    .clk        (clk_host),
    .rst_n      (rstn_host),
    .s_axis_req (if_pta_req),
    .m_axis_rsp (if_pta_rsp)
  );
  // MC CSR registers remain directly exposed on host AXI-Lite
  mc_axi_regs #(
    .ADDR_W(12),
    .DATA_W(32)
  ) u_mc_regs (
    .ACLK    (mc_csr_if.clk),
    .ARESETn (mc_csr_if.rst_n),
    .s_axi   (mc_csr_if)
  );

endmodule : nsi_cp_top
