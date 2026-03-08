 // SPDX-License-Identifier: Apache-2.0
 // File: fsm_pattern_counter.sv
 // Purpose: Pattern counter with simple direct-mapped hash table and promotion IRQ
 // Clock/Reset Domain: clk_fsm_1g / rst_n
 
 module fsm_pattern_counter #(
   parameter int KEY_W         = 64,
   parameter int NUM_COUNTER   = 1024,
   parameter int PROMO_THRESH  = 64,
   parameter int CNT_W         = 16
 ) (
   input  logic             clk,
   input  logic             rst_n,
   input  logic [KEY_W-1:0] key_in,
   output logic             promotion_irq
 );
 
   localparam int IDX_W = (NUM_COUNTER <= 1) ? 1 : $clog2(NUM_COUNTER);
 
   // Direct mapped table
   logic [KEY_W-1:0] key_mem   [0:NUM_COUNTER-1];
   logic [CNT_W-1:0] cnt_mem   [0:NUM_COUNTER-1];
   logic             valid_mem [0:NUM_COUNTER-1];
 
   // Hash: fold key into IDX_W bits via XOR
   function automatic [IDX_W-1:0] hash(input logic [KEY_W-1:0] k);
     logic [IDX_W-1:0] h;
     begin
       h = '0;
       for (int i = 0; i < KEY_W; i += IDX_W) begin
         h ^= k[i +: IDX_W];
       end
       return h;
     end
   endfunction
 
   logic [IDX_W-1:0] idx;
   always_comb idx = hash(key_in);
 
   // One-cycle pulse on threshold crossing
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       promotion_irq <= 1'b0;
       for (int i = 0; i < NUM_COUNTER; i++) begin
         valid_mem[i] <= 1'b0;
         key_mem[i]   <= '0;
         cnt_mem[i]   <= '0;
       end
     end else begin
       promotion_irq <= 1'b0;
 
       if (!valid_mem[idx]) begin
         // Allocate new entry
         valid_mem[idx] <= 1'b1;
         key_mem[idx]   <= key_in;
         cnt_mem[idx]   <= {{(CNT_W-1){1'b0}},1'b1};
         if (PROMO_THRESH == 1) promotion_irq <= 1'b1;
       end else if (key_mem[idx] == key_in) begin
         // Hit: increment with saturation
         if (cnt_mem[idx] != {CNT_W{1'b1}}) begin
           logic [CNT_W-1:0] next_cnt;
           next_cnt = cnt_mem[idx] + {{(CNT_W-1){1'b0}},1'b1};
           cnt_mem[idx] <= next_cnt;
           if (next_cnt == PROMO_THRESH[CNT_W-1:0]) promotion_irq <= 1'b1;
         end
       end else begin
         // Replace on conflict (direct mapped)
         key_mem[idx] <= key_in;
         cnt_mem[idx] <= {{(CNT_W-1){1'b0}},1'b1};
         // Replacement does not trigger promotion on first insert
       end
     end
   end
 
 endmodule : fsm_pattern_counter
