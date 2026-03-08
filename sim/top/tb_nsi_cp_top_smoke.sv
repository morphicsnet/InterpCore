// SPDX-License-Identifier: Apache-2.0
// File: tb_nsi_cp_top_smoke.sv
// Purpose: Top-level smoke test for nsi_cp_top — triggers DMA CONTROL to generate
//          ingress traffic, flows through GSE decode -> islands -> GMF cluster,
//          and observes GMF responses. Host CSR bus is instantiated but idle.
//
// Notes:
// - Drives all top-level clocks with the same 100 MHz clock for bring-up.
// - Uses hierarchical access to uut.dma_ctl_if (AXI4-Lite) to issue CONTROL write.
// - Observes uut.if_gmf_rsp for responses from GMF cluster.

`timescale 1ns/1ps

import axi4l_pkg::*;
import axi4s_pkg::*;

module tb_nsi_cp_top_smoke;

  // Clocking
  localparam int CLK_PER_NS = 10; // 100 MHz

  logic clk;
  initial clk = 1'b0;
  always #(CLK_PER_NS/2) clk = ~clk;

  // Resets (active-low)
  logic rstn_host, rstn_fab_700m, rstn_fsm_1g, rstn_mc;

  // Drive reset sequence
  initial begin
    rstn_host     = 1'b0;
    rstn_fab_700m = 1'b0;
    rstn_fsm_1g   = 1'b0;
    rstn_mc       = 1'b0;
    repeat (8) @(posedge clk);
    rstn_host     = 1'b1;
    rstn_fab_700m = 1'b1;
    rstn_fsm_1g   = 1'b1;
    rstn_mc       = 1'b1;
  end

  // Top-level clocks: for bring-up tie all to same clock
  wire clk_host     = clk;
  wire clk_fab_700m = clk;
  wire clk_fsm_1g   = clk;
  wire clk_mc       = clk;

  // Host CSR AXI-Lite interface (idle master)
  axi4l_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) s_axi_csr_if (.clk(clk_host), .rst_n(rstn_host));

  // Tie-off CSR master outputs (keep idle)
  initial begin
    s_axi_csr_if.AWADDR  = '0;
    s_axi_csr_if.AWPROT  = 3'b000;
    s_axi_csr_if.AWVALID = 1'b0;

    s_axi_csr_if.WDATA   = '0;
    s_axi_csr_if.WSTRB   = '0;
    s_axi_csr_if.WVALID  = 1'b0;

    s_axi_csr_if.BREADY  = 1'b1; // always ready

    s_axi_csr_if.ARADDR  = '0;
    s_axi_csr_if.ARPROT  = 3'b000;
    s_axi_csr_if.ARVALID = 1'b0;

    s_axi_csr_if.RREADY  = 1'b1; // always ready
  end

  // DUT
  nsi_cp_top uut (
    .clk_fsm_1g   (clk_fsm_1g),
    .clk_fab_700m (clk_fab_700m),
    .clk_host     (clk_host),
    .clk_mc       (clk_mc),

    .rstn_fsm_1g   (rstn_fsm_1g),
    .rstn_fab_700m (rstn_fab_700m),
    .rstn_host     (rstn_host),
    .rstn_mc       (rstn_mc),

    .s_axi_csr     (s_axi_csr_if)
  );

  // AXI4-Lite CSR write helper on external CSR bus
  task automatic csr_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      s_axi_csr_if.AWADDR  = addr;
      s_axi_csr_if.AWPROT  = 3'b000;
      s_axi_csr_if.AWVALID = 1'b1;

      s_axi_csr_if.WDATA   = data;
      s_axi_csr_if.WSTRB   = 4'hF;
      s_axi_csr_if.WVALID  = 1'b1;

      // Handshake AW
      @(posedge clk_host);
      while (!(s_axi_csr_if.AWVALID && s_axi_csr_if.AWREADY)) @(posedge clk_host);
      s_axi_csr_if.AWVALID = 1'b0;

      // Handshake W
      while (!(s_axi_csr_if.WVALID && s_axi_csr_if.WREADY)) @(posedge clk_host);
      s_axi_csr_if.WVALID = 1'b0;

      // B channel
      while (!s_axi_csr_if.BVALID) @(posedge clk_host);
      // BRESP should be OKAY
      if (s_axi_csr_if.BRESP !== axi4l_pkg::RESP_OKAY)
        $error("CSR write BRESP != OKAY");
      @(posedge clk_host);
    end
  endtask

  // Pulse DMA CONTROL via CSR window: address bit[12]==1 selects DMA slot
  task automatic dma_control_pulse();
    begin
      csr_write(32'h0000_1000, 32'h0000_0001); // DMA CONTROL@0x1000: bit0=1
    end
  endtask

  // Response monitor for GMF path
  int rsp_count;
  initial rsp_count = 0;

  // Observe internal GMF response stream from GSE path
  always @(posedge clk_host) begin
    if (rstn_host && uut.if_gmf_rsp.TVALID && uut.if_gmf_rsp.TREADY) begin
      rsp_count++;
      if (uut.if_gmf_rsp.TLAST !== 1'b1) begin
        $error("GMF response without TLAST");
      end
    end
  end

  // Stimulus
  initial begin : run
    // Wait until resets deasserted
    @(posedge rstn_host);
    repeat (4) @(posedge clk_host);

    // Pulse DMA CONTROL to generate a 16-beat pattern
    dma_control_pulse();

    // Wait for traffic to flow through pipeline (decoder -> islands -> GMF)
    repeat (200) @(posedge clk_host);

    // Expect at least some GMF responses
    if (rsp_count == 0) begin
      $fatal(1, "No GMF responses observed from nsi_cp_top GMF cluster (rsp_count=%0d)", rsp_count);
    end

    $display("tb_nsi_cp_top_smoke: PASS (GMF rsp_count=%0d)", rsp_count);
    $finish;
  end

  // Optional waves
  initial begin
    // $dumpfile("tb_nsi_cp_top_smoke.fst");
    // $dumpvars(0, tb_nsi_cp_top_smoke);
  end

endmodule : tb_nsi_cp_top_smoke