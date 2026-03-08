 // SPDX-License-Identifier: Apache-2.0
 // File: noc_bridge_axi4l.sv
 // Purpose: AXI4-Lite to NoC VC0 packet bridge (minimal functional)
 // Clock/Reset Domain: clk_host/clk_fab (varies), active-low rst_n
 // Notes:
 // - Single-flit requests for WR and RD (header + addr/data in payload)
 // - BVALID asserted after WR flit is issued (no response wait)
 // - RVALID asserted when a response flit is received on RX path
 
 import axi4l_pkg::*;
 import noc_pkg::*;
 
 module noc_bridge_axi4l #(
   parameter int          FLIT_W = noc_pkg::NOC_FLIT_W,
   parameter logic [7:0]  SRC_ID = 8'd1,
   parameter logic [7:0]  DST_ID = 8'd0,
   parameter int          TIMEOUT_CYCLES = 4096,
   parameter bit          WAIT_WR_RESP   = 1'b0
 ) (
   input  logic   clk,
   input  logic   rst_n,
 
   // AXI-Lite slave side (from master upstream)
   axi4l_if.slave s_axi,
 
   // NoC injection (VC0 control)
   output logic [FLIT_W-1:0] noc_tx_flit,
   output logic              noc_tx_valid,
   input  logic              noc_tx_ready,
 
   // NoC ejection (VC0 control)
   input  logic [FLIT_W-1:0] noc_rx_flit,
   input  logic              noc_rx_valid,
   output logic              noc_rx_ready
 );
 
   localparam int HDR_W   = noc_pkg::NOC_HDR_W;
   localparam int PAY_W   = FLIT_W - HDR_W;
   localparam int AXIL_AW = 32;
   localparam int AXIL_DW = 32;
 
   // Channel capture
   logic                 aw_captured, w_captured, ar_captured;
   logic [AXIL_AW-1:0]   awaddr_q, araddr_q;
   logic [AXIL_DW-1:0]   wdata_q, rdata_q;
   logic                 bvalid_q, rvalid_q;
   logic [1:0]           bresp_q, rresp_q;
   localparam int        TIME_W = $clog2(TIMEOUT_CYCLES + 1);
   logic [TIME_W-1:0]    rd_timer;
 
   typedef enum logic [2:0] {S_IDLE, S_SEND_WR, S_SEND_RD, S_RD_WAIT} state_e;
   state_e state_q, state_d;
 
   // Default combinational
   always_comb begin
     // Defaults
     noc_tx_flit   = '0;
     noc_tx_valid  = 1'b0;
     noc_rx_ready  = ((state_q == S_RD_WAIT) & ~rvalid_q) | (WAIT_WR_RESP & ~bvalid_q);
 
     s_axi.AWREADY = rst_n & ~aw_captured & (state_q == S_IDLE);
     s_axi.WREADY  = rst_n & ~w_captured  & (state_q == S_IDLE);
     s_axi.ARREADY = rst_n & ~ar_captured & (state_q == S_IDLE);
 
     s_axi.BRESP   = bresp_q;
     s_axi.RRESP   = rresp_q;
     s_axi.BVALID  = bvalid_q;
     s_axi.RVALID  = rvalid_q;
     s_axi.RDATA   = rdata_q;

     state_d       = state_q;

     // Idle transitions based on captured channels
     if (state_q == S_IDLE) begin
       if (aw_captured && w_captured) begin
         state_d = S_SEND_WR;
       end else if (ar_captured) begin
         state_d = S_SEND_RD;
       end
     end



     // Local variables for packetization
     noc_pkg::noc_hdr_t hdr;
     logic [HDR_W-1:0]  hdr_bits;
 
     // Encode write request flit (single flit with addr+data payload)
     if (state_q == S_SEND_WR) begin
       hdr.src      = SRC_ID;
       hdr.dst      = DST_ID;
       hdr.vc       = noc_pkg::VC0_CTRL;
       hdr.pkt_type = noc_pkg::PKT_AXIL_WR_REQ;
       hdr.len      = 8'd1;
       hdr_bits     = hdr;
 
       noc_tx_flit                         = '0;
       noc_tx_flit[FLIT_W-1 -: HDR_W]     = hdr_bits;
       // Payload: {reserved, data, addr}
       if (PAY_W >= 64) begin
         noc_tx_flit[31:0]                 = awaddr_q;
         noc_tx_flit[63:32]                = wdata_q;
       end else begin
         // Truncate if PAY_W < 64 (unlikely with default FLIT_W=128)
         noc_tx_flit[PAY_W-1:0]            = {wdata_q[PAY_W-33:0], awaddr_q[31:0]};
       end
       noc_tx_valid = 1'b1;
       if (noc_tx_valid && noc_tx_ready) begin
         state_d = S_IDLE;
       end
     end
 
     // Encode read request flit (single flit with addr payload)
     if (state_q == S_SEND_RD) begin
       hdr.src      = SRC_ID;
       hdr.dst      = DST_ID;
       hdr.vc       = noc_pkg::VC0_CTRL;
       hdr.pkt_type = noc_pkg::PKT_AXIL_RD_REQ;
       hdr.len      = 8'd1;
       hdr_bits     = hdr;
 
       noc_tx_flit                         = '0;
       noc_tx_flit[FLIT_W-1 -: HDR_W]     = hdr_bits;
       noc_tx_flit[31:0]                   = araddr_q;
       noc_tx_valid                        = 1'b1;
       if (noc_tx_valid && noc_tx_ready) begin
         state_d = S_RD_WAIT;
       end
     end
   end
 
   // Sequential: captures and status
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       aw_captured <= 1'b0;
       w_captured  <= 1'b0;
       ar_captured <= 1'b0;
       awaddr_q    <= '0;
       araddr_q    <= '0;
       wdata_q     <= '0;
       rdata_q     <= '0;
       bvalid_q    <= 1'b0;
       rvalid_q    <= 1'b0;
       bresp_q     <= 2'b00;
       rresp_q     <= 2'b00;
       state_q     <= S_IDLE;
     end else begin
       state_q <= state_d;
 
       // Capture AW
       if (!aw_captured && s_axi.AWVALID && s_axi.AWREADY) begin
         awaddr_q    <= s_axi.AWADDR[AXIL_AW-1:0];
         aw_captured <= 1'b1;
       end
       // Capture W
       if (!w_captured && s_axi.WVALID && s_axi.WREADY) begin
         wdata_q     <= s_axi.WDATA[AXIL_DW-1:0];
         w_captured  <= 1'b1;
       end
       // Start write when both captured and idle
       if (state_q == S_IDLE && aw_captured && w_captured) begin
         // Move to send, BVALID will be asserted after flit handshake
         // state_d handled in comb
       end
       // After WR flit is issued, complete write response
       if (state_q == S_SEND_WR && noc_tx_valid && noc_tx_ready) begin
         aw_captured <= 1'b0;
         w_captured  <= 1'b0;
         if (!WAIT_WR_RESP) begin
           bvalid_q <= 1'b1;
           bresp_q  <= 2'b00; // OKAY
         end
       end
       // Complete B channel
       if (s_axi.BVALID && s_axi.BREADY) begin
         bvalid_q <= 1'b0;
       end


 
       // Capture AR
       if (!ar_captured && s_axi.ARVALID && s_axi.ARREADY) begin
         araddr_q    <= s_axi.ARADDR[AXIL_AW-1:0];
         ar_captured <= 1'b1;
       end
       // On send of RD flit, clear AR capture and arm timeout
       if (state_q == S_SEND_RD && noc_tx_valid && noc_tx_ready) begin
         ar_captured <= 1'b0;
         rd_timer    <= TIMEOUT_CYCLES[TIME_W-1:0];
       end
       // Receive NoC responses
       if (noc_rx_valid && noc_rx_ready) begin
         noc_pkg::noc_hdr_t rx_hdr;
         rx_hdr = noc_rx_flit[FLIT_W-1 -: HDR_W];
         if (rx_hdr.pkt_type == noc_pkg::PKT_AXIL_RD_RESP &&
             rx_hdr.dst == SRC_ID && rx_hdr.vc == noc_pkg::VC0_CTRL) begin
           rdata_q  <= noc_rx_flit[31:0];
           rresp_q  <= 2'b00; // OKAY
           rvalid_q <= 1'b1;
         end else if (rx_hdr.pkt_type == noc_pkg::PKT_AXIL_WR_RESP &&
                      WAIT_WR_RESP &&
                      rx_hdr.dst == SRC_ID && rx_hdr.vc == noc_pkg::VC0_CTRL) begin
           bresp_q  <= 2'b00; // OKAY
           bvalid_q <= 1'b1;
         end else begin
           // Unexpected packet: if waiting on read, signal error
           if (state_q == S_RD_WAIT && !rvalid_q) begin
             rresp_q  <= 2'b10; // SLVERR
             rvalid_q <= 1'b1;
           end
         end
       end
       // Complete R channel
       if (s_axi.RVALID && s_axi.RREADY) begin
         rvalid_q <= 1'b0;
       end
 
       // State transitions handled in always_comb via state_d
     end
   end
 
 endmodule : noc_bridge_axi4l
