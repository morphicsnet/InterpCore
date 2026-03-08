 // SPDX-License-Identifier: Apache-2.0
 // File: gse_island_builder.sv
 // Purpose: Build islands from events (dedup, K-max) and emit GMF update stream
 // Clock/Reset Domain: stream domain
 
 import axi4s_pkg::*;
 
 module gse_island_builder #(
   parameter int K_MAX   = 16,
   parameter int DEDUP_N = 4,
   parameter int TDATA_W = 256
 ) (
   input  logic     clk,
   input  logic     rst_n,
 
   axi4s_if.slave   s_axis,
   // Forwarded stream to next GSE stage
   axi4s_if.master  m_axis,
   // Emitted stream destined for GMF update path (e.g., via NoC bridge)
   axi4s_if.master  m_axis_gmf
 );
 
   // Recent-history deduplication of last DEDUP_N beats; drop duplicates
   logic [TDATA_W-1:0] recent [0:DEDUP_N-1];
   logic               dup_hit;
   // Per-window cap of K_MAX beats (window framed by TLAST)
   logic [$clog2(K_MAX+1)-1:0] kcnt_q;
 
   // Forward predicate
   logic allow_w, fwd;
   assign allow_w = (kcnt_q < K_MAX);
   assign fwd     = ~dup_hit & allow_w;
 
   always_comb begin
     // Dup detection
     dup_hit = 1'b0;
     for (int j = 0; j < DEDUP_N; j++) begin
       if (s_axis.TVALID && (s_axis.TDATA == recent[j])) dup_hit = 1'b1;
     end
 
     // Outputs default
     m_axis.TVALID     = s_axis.TVALID & fwd;
     m_axis.TDATA      = s_axis.TDATA;
     m_axis.TKEEP      = s_axis.TKEEP;
     m_axis.TLAST      = s_axis.TLAST;
 
     m_axis_gmf.TVALID = s_axis.TVALID & fwd;
     m_axis_gmf.TDATA  = s_axis.TDATA; // simple payload; future: pack island metadata/header
     m_axis_gmf.TKEEP  = s_axis.TKEEP;
     m_axis_gmf.TLAST  = s_axis.TLAST;
 
     // Consume:
     // - If fwd (kept), require both downstreams ready to avoid duplication or loss
     // - If drop (dup or over-cap), always consume to avoid stalling upstream
     s_axis.TREADY = fwd ? (m_axis.TREADY & m_axis_gmf.TREADY) : 1'b1;
   end
 
   // Update recent window and per-window counter on consumed beats
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       for (int j = 0; j < DEDUP_N; j++) recent[j] <= '0;
       kcnt_q <= '0;
     end else begin
       if (s_axis.TVALID && s_axis.TREADY) begin
         if (fwd) begin
           for (int j = DEDUP_N-1; j > 0; j--) begin
             recent[j] <= recent[j-1];
           end
           recent[0] <= s_axis.TDATA;
           if (kcnt_q < K_MAX[$clog2(K_MAX+1)-1:0]) begin
             kcnt_q <= kcnt_q + 1'b1;
           end
         end
         // End of window resets cap counter
         if (s_axis.TLAST) begin
           kcnt_q <= '0;
         end
       end
     end
   end
 
 endmodule : gse_island_builder
