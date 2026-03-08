 // SPDX-License-Identifier: Apache-2.0
 // File: pta_maskgen.sv
 // Purpose: PTA subset mask generator with replication and optional early-stop
 // Clock/Reset Domain: PTA domain
 
 import axi4s_pkg::*;
 
 module pta_maskgen #(
   parameter int MODE           = 0,    // 0: OPENAI (XOR), 1: ANTHROPIC (AND-not)
   parameter int TDATA_W        = 256,
   // Number of replicate masks per input beat (>=1)
   parameter int REPS           = 4,
   // Optional early-stop enable: when asserted and stop_in=1, terminates current replicate sequence early
   parameter bit EARLY_STOP_EN  = 1'b0
 ) (
   input  logic     clk,
   input  logic     rst_n,
 
   // Input beat to replicate across multiple masked outputs
   axi4s_if.slave   s_axis,
   // Replicated masked beats out
   axi4s_if.master  m_axis,
 
   // Optional CI early-stop indicator (externally computed)
   input  logic     stop_in
 );
 
   // ----------------------------
   // LFSR and mask construction
   // ----------------------------
   localparam int CHUNK_W = 32;
   logic [31:0]         lfsr_q;
   logic [TDATA_W-1:0]  mask_w;
 
   function automatic [31:0] lfsr_next(input [31:0] x);
     // x^32 + x^22 + x^2 + x^1 + 1 (maximal-length tap set)
     lfsr_next = {x[30:0], x[31] ^ x[21] ^ x[1] ^ x[0]};
   endfunction
 
   always_comb begin
     mask_w = '0;
     for (int b = 0; b < TDATA_W; b++) begin
       mask_w[b] = lfsr_q[b % CHUNK_W];
     end
   end
 
   // ----------------------------
   // Replication control
   // ----------------------------
   logic                 busy_q;
   logic [15:0]          rep_cnt_q;
   logic [TDATA_W-1:0]   data_q;
   logic [(TDATA_W+7)/8-1:0] tkeep_q;
   logic                 last_q;
 
   // Combinational output
   always_comb begin
     // Default outputs
     m_axis.TVALID = 1'b0;
     m_axis.TDATA  = '0;
     m_axis.TKEEP  = '0;
     // TLAST asserted on the final replicate, or early-stop when enabled
     m_axis.TLAST  = 1'b0;
 
     // Backpressure to input: accept only when not busy (store-and-forward model)
     s_axis.TREADY = ~busy_q;
 
     if (busy_q) begin
       m_axis.TVALID = 1'b1;
       // Apply transform per MODE
       if (MODE == 0) begin
         m_axis.TDATA = data_q ^ mask_w;
       end else begin
         m_axis.TDATA = data_q & ~mask_w;
       end
       m_axis.TKEEP = tkeep_q;
       // Finalize on last replicate or early-stop request
       m_axis.TLAST = last_q & ( (rep_cnt_q == 16'd1) | (EARLY_STOP_EN & stop_in) );
     end
   end
 
   // Sequential control
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       busy_q    <= 1'b0;
       rep_cnt_q <= '0;
       data_q    <= '0;
       tkeep_q   <= '0;
       last_q    <= 1'b0;
       lfsr_q    <= 32'h1ACE_1234; // deterministic seed for repeatability
     end else begin
       // Accept a new input beat when not busy
       if (!busy_q && s_axis.TVALID && s_axis.TREADY) begin
         data_q    <= s_axis.TDATA;
         tkeep_q   <= s_axis.TKEEP;
         last_q    <= s_axis.TLAST;
         rep_cnt_q <= (REPS > 0) ? REPS[15:0] : 16'd1;
         busy_q    <= 1'b1;
       end
 
       // Produce replicate output on handshake
       if (busy_q && m_axis.TVALID && m_axis.TREADY) begin
         // Advance mask generator per emitted replicate
         lfsr_q <= lfsr_next(lfsr_q);
 
         // Determine if this was the final replicate
         logic will_stop;
         will_stop = (rep_cnt_q == 16'd1) | (EARLY_STOP_EN & stop_in);
 
         if (will_stop) begin
           // Done with current input
           rep_cnt_q <= 16'd0;
           busy_q    <= 1'b0;
         end else begin
           // Continue with next replicate
           rep_cnt_q <= rep_cnt_q - 16'd1;
         end
       end
     end
   end
 
 endmodule : pta_maskgen
