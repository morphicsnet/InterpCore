 // SPDX-License-Identifier: Apache-2.0
 // File: noc_bridge_axi4s.sv
 // Purpose: AXI4-Stream to/from NoC VC packetizer/depacketizer (minimal functional)
 // Clock/Reset Domain: stream/fabric domains, active-low rst_n
 // Notes:
 // - 1-beat => 1-flit mapping (header + truncated payload)
 // - RX flit => 1-beat with TLAST=1, TKEEP all ones
 
 import axi4s_pkg::*;
 import noc_pkg::*;
 
 module noc_bridge_axi4s #(
   parameter int          FLIT_W = noc_pkg::NOC_FLIT_W,
   parameter logic [7:0]  SRC_ID = 8'd10,
   parameter logic [7:0]  DST_ID = 8'd20,
   parameter logic [1:0]  VC_SEL = noc_pkg::VC1_GSE,
   parameter int          AXIS_TDATA_W = 256
 ) (
   input  logic     clk,
   input  logic     rst_n,
 
   // Stream in (to NoC)
   axi4s_if.slave   s_axis,
 
   // Stream out (from NoC)
   axi4s_if.master  m_axis,
 
   // NoC injection/ejection
   output logic [FLIT_W-1:0] noc_tx_flit,
   output logic              noc_tx_valid,
   input  logic              noc_tx_ready,
 
   input  logic [FLIT_W-1:0] noc_rx_flit,
   input  logic              noc_rx_valid,
   output logic              noc_rx_ready
 );
 
   localparam int HDR_W = noc_pkg::NOC_HDR_W;
   localparam int PAY_W = FLIT_W - HDR_W;
   // Reintroduce packed payload fields for TLAST/TKEEP/DATA
   localparam int TKEEP_W     = (AXIS_TDATA_W+7)/8;
   localparam int DATA_PAY_W  = (PAY_W > (1+TKEEP_W)) ? (PAY_W - 1 - TKEEP_W) : 0;
 
   // TX path: one beat -> one flit
   always_comb begin
     noc_tx_flit  = '0;
     noc_tx_valid = 1'b0;
 
     // Backpressure ties
     s_axis.TREADY = noc_tx_ready;
 
     if (s_axis.TVALID && s_axis.TREADY) begin
       noc_pkg::noc_hdr_t hdr;
       logic [HDR_W-1:0]  hdr_bits;
       hdr.src      = SRC_ID;
       hdr.dst      = DST_ID;
       hdr.vc       = VC_SEL;
       hdr.pkt_type = noc_pkg::PKT_AXIS_BEAT;
       hdr.len      = 8'd1;
       hdr_bits     = hdr;
 
       noc_tx_flit[FLIT_W-1 -: HDR_W] = hdr_bits;
       // Pack payload: [TLAST | TKEEP | DATA]
       noc_tx_flit[PAY_W-1] = s_axis.TLAST;
       if (TKEEP_W > 0) begin
         noc_tx_flit[PAY_W-2 -: TKEEP_W] = s_axis.TKEEP[TKEEP_W-1:0];
       end
       if (DATA_PAY_W > 0) begin
         noc_tx_flit[DATA_PAY_W-1:0] = s_axis.TDATA[DATA_PAY_W-1:0];
       end
       noc_tx_valid           = 1'b1;
     end
   end
 
   // RX path: one flit -> one beat
   always_comb begin
     noc_rx_ready = m_axis.TREADY;
 
     m_axis.TVALID = noc_rx_valid;
     m_axis.TDATA  = '0;
     m_axis.TKEEP  = '0;
     m_axis.TLAST  = noc_rx_flit[PAY_W-1];
     if (TKEEP_W > 0) begin
       m_axis.TKEEP[TKEEP_W-1:0] = noc_rx_flit[PAY_W-2 -: TKEEP_W];
     end else begin
       m_axis.TKEEP = '1;
     end
     if (DATA_PAY_W > 0) begin
       m_axis.TDATA[DATA_PAY_W-1:0] = noc_rx_flit[DATA_PAY_W-1:0];
     end
   end
 
 endmodule : noc_bridge_axi4s
