 // SPDX-License-Identifier: Apache-2.0
 // File: gse_ingress_dma.sv
 // Purpose: Ingress DMA (AXI-MM reader -> AXI4-Stream) with simple FIFO and watermarks
 // Clock/Reset Domain: clk_host / rstn_host (active-low)
 
 import axi4s_pkg::*;
 
 module gse_ingress_dma #(
   parameter int TDATA_W     = 256,
   // Simple burst reader configuration
   parameter int READ_BURST  = 8,                // beats per AR (>=1)
   parameter int FIFO_DEPTH  = 16,               // stream FIFO depth in beats
   parameter logic [63:0] ARADDR_BASE = 64'h0    // base address
 ) (
   input  logic      clk_host,
   input  logic      rstn_host,
 
   // AXI-MM Read channel (minimal subset)
   output logic [63:0] araddr,
   output logic [7:0]  arlen,
   output logic        arvalid,
   input  logic        arready,
 
   input  logic [TDATA_W-1:0] rdata,
   input  logic               rlast,
   input  logic               rvalid,
   output logic               rready,
 
   // Stream out to decoder
   axi4s_if.master    m_axis,
 
   // FIFO level counters
   output logic [15:0] fifo_level,
   output logic [15:0] fifo_level_max
 );
 
   // ----------------------------
   // Parameters/locals
   // ----------------------------
   localparam int DATA_BYTES = (TDATA_W+7)/8;
   localparam int ADDR_INCR  = READ_BURST * DATA_BYTES;
   localparam int PTR_W      = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);
 
   // ----------------------------
   // FIFO state
   // ----------------------------
   logic [TDATA_W-1:0] fifo_data [0:FIFO_DEPTH-1];
   logic               fifo_last [0:FIFO_DEPTH-1];
   logic [PTR_W-1:0]   wr_ptr_q, rd_ptr_q;
   logic [PTR_W:0]     cnt_q; // can represent 0..FIFO_DEPTH
   logic [15:0]        lvl_max_q;
 
   // ----------------------------
   // Reader state
   // ----------------------------
   logic [63:0] araddr_q;
   logic        arvalid_q;
   logic        ar_inflight_q; // true between AR handshake and RLAST
   // rready when FIFO has space
   wire         fifo_has_space = (cnt_q < FIFO_DEPTH[PTR_W:0]);
 
   // ----------------------------
   // Combinational outputs
   // ----------------------------
   always_comb begin
     // AXI-MM AR channel
     araddr  = araddr_q;
     arlen   = (READ_BURST > 0) ? (READ_BURST[7:0] - 8'd1) : 8'd0;
     arvalid = arvalid_q;
 
     // R channel backpressure from FIFO
     rready = fifo_has_space;
 
     // Stream out from FIFO
     m_axis.TVALID = (cnt_q != '0);
     m_axis.TDATA  = fifo_data[rd_ptr_q];
     m_axis.TKEEP  = '1;
     m_axis.TLAST  = fifo_last[rd_ptr_q];
 
     // Telemetry
     fifo_level     = { { (16-$bits(cnt_q)){1'b0} }, cnt_q };
     fifo_level_max = lvl_max_q;
   end
 
   // ----------------------------
   // Sequential logic
   // ----------------------------
   always_ff @(posedge clk_host or negedge rstn_host) begin
     if (!rstn_host) begin
       // FIFO reset
       wr_ptr_q   <= '0;
       rd_ptr_q   <= '0;
       cnt_q      <= '0;
       lvl_max_q  <= '0;
       // Reader reset
       araddr_q     <= ARADDR_BASE;
       arvalid_q    <= 1'b0;
       ar_inflight_q<= 1'b0;
     end else begin
       // Issue AR when no inflight burst, not already asserting ARVALID,
       // and enough FIFO space exists to hold full burst.
       if (!ar_inflight_q && !arvalid_q && (FIFO_DEPTH - cnt_q) >= READ_BURST) begin
         arvalid_q <= 1'b1;
       end
       // AR handshake
       if (arvalid_q && arready) begin
         arvalid_q     <= 1'b0;
         ar_inflight_q <= 1'b1;
       end
 
       // Accept R beats into FIFO
       if (rvalid && rready) begin
         fifo_data[wr_ptr_q] <= rdata;
         fifo_last[wr_ptr_q] <= rlast;
         wr_ptr_q            <= (wr_ptr_q + {{(PTR_W-1){1'b0}},1'b1});
         cnt_q               <= cnt_q + {{($bits(cnt_q)-1){1'b0}},1'b1};
         // Track max occupancy
         if (cnt_q + {{($bits(cnt_q)-1){1'b0}},1'b1} > lvl_max_q)
           lvl_max_q <= cnt_q + {{($bits(cnt_q)-1){1'b0}},1'b1};
       end
 
       // End of burst, free to issue next AR on space condition
       if (rvalid && rready && rlast) begin
         ar_inflight_q <= 1'b0;
         araddr_q      <= araddr_q + ADDR_INCR[63:0];
       end
 
       // Pop to AXI-Stream
       if (m_axis.TVALID && m_axis.TREADY) begin
         rd_ptr_q <= (rd_ptr_q + {{(PTR_W-1){1'b0}},1'b1});
         cnt_q    <= cnt_q - {{($bits(cnt_q)-1){1'b0}},1'b1};
       end
     end
   end
 
 endmodule : gse_ingress_dma
