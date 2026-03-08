// SPDX-License-Identifier: Apache-2.0
// File: top_versax.sv
// Purpose: Versal/VERSA-X FPGA wrapper for NSI-CP top (stub)
// Clock/Reset: uses refclk and button reset
// TODO:
// - Map board IOs, LEDs, DDR, PCIe pins
// - Replace clkgen with vendor PLLs

`timescale 1ns/1ps
import axi4l_pkg::*;

module top_versax (
  input  logic       refclk,
  input  logic       rst_btn_n,
  output logic [3:0] led
);

  // Clocks
  logic clk_fsm_1g, clk_fab_700m, clk_host, clk_mc;

  // Reset syncs
  logic rstn_host, rstn_fsm_1g, rstn_fab_700m, rstn_mc;

  // Generate clocks
  clkgen u_clkgen (
    .refclk       (refclk),
    .rstn         (rst_btn_n),
    .clk_fsm_1g   (clk_fsm_1g),
    .clk_fab_700m (clk_fab_700m),
    .clk_host     (clk_host),
    .clk_mc       (clk_mc)
  );

  // Sync resets (simple tie for stub)
  assign rstn_host     = rst_btn_n;
  assign rstn_fsm_1g   = rst_btn_n;
  assign rstn_fab_700m = rst_btn_n;
  assign rstn_mc       = rst_btn_n;

  // AXI-Lite CSR interface
  axi4l_if #(.ADDR_W(32), .DATA_W(32)) csr_if (.ACLK(clk_host), .ARESETn(rstn_host));

  nsi_cp_top u_top (
    .clk_fsm_1g     (clk_fsm_1g),
    .clk_fab_700m   (clk_fab_700m),
    .clk_host       (clk_host),
    .clk_mc         (clk_mc),
    .rstn_fsm_1g    (rstn_fsm_1g),
    .rstn_fab_700m  (rstn_fab_700m),
    .rstn_host      (rstn_host),
    .rstn_mc        (rstn_mc),
    .s_axi_csr      (csr_if)
  );

  // TODO: Drive LEDs from STATUS CSR bits when mapped
  assign led = 4'h0;

endmodule : top_versax
