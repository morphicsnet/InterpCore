// SPDX-License-Identifier: Apache-2.0
// File: axi4s_pkg.sv
// Purpose: AXI4-Stream parameters and interface (master/slave modports)
// Clock/Reset Domain: stream domain via ACLK/ARESETn, active-low reset
// TODO:
// - Parameterize optional USER sideband: TUSER width and semantics
// - Add TLAST/TKEEP presence masks for synthesis optimization

package axi4s_pkg;
  parameter int AXI4S_TDATA_W   = 256;
  parameter bit AXI4S_HAS_TKEEP = 1;
  parameter bit AXI4S_HAS_TLAST = 1;
endpackage : axi4s_pkg

interface axi4s_if #(
  parameter int TDATA_W   = axi4s_pkg::AXI4S_TDATA_W,
  parameter bit HAS_TKEEP = axi4s_pkg::AXI4S_HAS_TKEEP,
  parameter bit HAS_TLAST = axi4s_pkg::AXI4S_HAS_TLAST
) (input logic ACLK, input logic ARESETn);

  import axi4s_pkg::*;

  localparam int TKEEP_W = (TDATA_W+7)/8;

  logic              TVALID;
  logic              TREADY;
  logic [TDATA_W-1:0] TDATA;
  logic [TKEEP_W-1:0] TKEEP; // valid if HAS_TKEEP==1
  logic               TLAST; // valid if HAS_TLAST==1
  // NOTE: Future: logic [TUSER_W-1:0] TUSER;

  modport master (
    input  ACLK, ARESETn,
    output TVALID, TDATA, TKEEP, TLAST,
    input  TREADY
  );

  modport slave (
    input  ACLK, ARESETn,
    input  TVALID, TDATA, TKEEP, TLAST,
    output TREADY
  );

endinterface : axi4s_if
