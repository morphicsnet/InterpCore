// SPDX-License-Identifier: Apache-2.0
// File: mc_riscv_subsys.sv
// Purpose: Microcontroller subsystem stub (no core)
// Clock/Reset Domain: clk_mc / rstn_mc
// TODO:
// - Integrate RISC-V core and boot ROM
// - Wire interrupts and AXI-Lite master

import axi4l_pkg::*;

module mc_riscv_subsys #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32
) (
  input  logic       clk_mc,
  input  logic       rstn_mc,

  // AXI-Lite master for CSR fabric
  axi4l_if.master    m_axi_csr,

  // Interrupts in
  input  logic [31:0] irq_i
);

  // Idle master
  always_comb begin
    m_axi_csr.AWADDR  = '0;
    m_axi_csr.AWPROT  = '0;
    m_axi_csr.AWVALID = 1'b0;

    m_axi_csr.WDATA   = '0;
    m_axi_csr.WSTRB   = '0;
    m_axi_csr.WVALID  = 1'b0;

    m_axi_csr.BREADY  = 1'b1;

    m_axi_csr.ARADDR  = '0;
    m_axi_csr.ARPROT  = '0;
    m_axi_csr.ARVALID = 1'b0;

    m_axi_csr.RREADY  = 1'b1;
  end

endmodule : mc_riscv_subsys
