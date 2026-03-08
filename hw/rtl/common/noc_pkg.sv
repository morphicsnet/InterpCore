// SPDX-License-Identifier: Apache-2.0
// File: noc_pkg.sv
// Purpose: Common NoC header, VC enums, widths
// Clock/Reset Domain: fabric domain (varies by instance), active-low rst_n
// TODO:
// - Define packet types and payload formats
// - Route computation policy (XY/OBLIVIOUS/ADAPTIVE)

package noc_pkg;

  typedef struct packed {
    logic [7:0] src;
    logic [7:0] dst;
    logic [1:0] vc;
    logic [3:0] pkt_type;
    logic [7:0] len;      // in flits (including header)
  } noc_hdr_t;

  // Packet types used by bridges and blocks
  typedef enum logic [3:0] {
    PKT_AXIL_WR_REQ  = 4'd1,
    PKT_AXIL_WR_RESP = 4'd2,
    PKT_AXIL_RD_REQ  = 4'd3,
    PKT_AXIL_RD_RESP = 4'd4,
    PKT_AXIS_BEAT    = 4'd8
  } pkt_type_e;

  localparam logic [1:0] VC0_CTRL     = 2'd0;
  localparam logic [1:0] VC1_GSE      = 2'd1;
  localparam logic [1:0] VC2_PTA      = 2'd2;
  localparam logic [1:0] VC3_GMF_RET  = 2'd3;

  localparam int NOC_VC_NUM       = 4;
  localparam int NOC_FLIT_W       = 128; // header+payload flit width
  localparam int NOC_CREDIT_DEPTH = 8;

  // Convenience width of serialized header
  localparam int NOC_HDR_W        = $bits(noc_hdr_t);

  typedef logic [NOC_FLIT_W-1:0] flit_t;

endpackage : noc_pkg
