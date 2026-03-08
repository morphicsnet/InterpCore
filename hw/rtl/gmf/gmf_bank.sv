 // SPDX-License-Identifier: Apache-2.0
 // File: gmf_bank.sv
 // Purpose: GMF bank: single-beat request/response with simple ops and versioning
 // Clock/Reset Domain: stream domain
 
 import axi4s_pkg::*;
 
 module gmf_bank #(
   parameter int TDATA_W = 256
 ) (
   input  logic     clk,
   input  logic     rst_n,
 
   // Requests in
   axi4s_if.slave   s_axis_req,
 
   // Responses out
   axi4s_if.master  m_axis_rsp,
 
   // Status
   output logic     busy,
   output logic [31:0] version_counter
 );
 
   // Minimal request->response FSM
   logic                  pending_q;
   logic [TDATA_W-1:0]    rsp_data_q;
   logic [31:0]           version_q;
 
   // Op decode
   logic [7:0]            opcode_d;
 
   // Simple KV store (key/value arrays) for GET/PUT/DEL ops
   localparam int KEY_W       = 32;
   localparam int VAL_W       = 32;
   localparam int KV_ENTRIES  = 16;
 
   logic [KEY_W-1:0] kv_key   [0:KV_ENTRIES-1];
   logic [VAL_W-1:0] kv_val   [0:KV_ENTRIES-1];
   logic             kv_valid [0:KV_ENTRIES-1];
 
   // Sliced request fields
   logic [KEY_W-1:0] req_key;
   logic [VAL_W-1:0] req_val;
 
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       pending_q       <= 1'b0;
       rsp_data_q      <= '0;
       version_q       <= 32'd0;
       // Clear KV arrays
       for (int i = 0; i < KV_ENTRIES; i++) begin
         kv_valid[i] <= 1'b0;
         kv_key[i]   <= '0;
         kv_val[i]   <= '0;
       end
     end else begin
       // Accept a single-beat request when idle and downstream is ready
       if (!pending_q && s_axis_req.TVALID && m_axis_rsp.TREADY) begin
         opcode_d = s_axis_req.TDATA[7:0];
         // Slice request fields (if payload wide enough)
         req_key  = s_axis_req.TDATA[39:8];
         req_val  = s_axis_req.TDATA[71:40];
 
         // Default response mirrors request unless overridden
         rsp_data_q <= s_axis_req.TDATA;
 
         unique case (opcode_d)
           8'h00: begin
             // ECHO (already set by default)
             rsp_data_q <= s_axis_req.TDATA;
           end
           8'h01: begin
             // INC32: increment low 32b
             rsp_data_q            <= s_axis_req.TDATA;
             rsp_data_q[31:0]      <= s_axis_req.TDATA[31:0] + 32'd1;
           end
           8'h10: begin
             // VERSION: return next version value in low 32b
             rsp_data_q            <= '0;
             rsp_data_q[31:0]      <= version_q + 32'd1;
           end
 
           // 0x20 GET: find key and return {found_flag, value}
           8'h20: begin
             bit found;
             int found_idx;
             found     = 1'b0;
             found_idx = 0;
             for (int j = 0; j < KV_ENTRIES; j++) begin
               if (!found && kv_valid[j] && kv_key[j] == req_key) begin
                 found     = 1'b1;
                 found_idx = j;
               end
             end
             rsp_data_q       <= '0;
             rsp_data_q[31:0] <= found ? kv_val[found_idx] : '0;
             rsp_data_q[32]   <= found;
           end
 
           // 0x21 PUT: insert or update key/value; success flag in bit[0]
           8'h21: begin
             bit found, empty_found, success;
             int found_idx, empty_idx;
             found       = 1'b0;
             empty_found = 1'b0;
             found_idx   = 0;
             empty_idx   = 0;
             // search for key and first empty slot
             for (int j = 0; j < KV_ENTRIES; j++) begin
               if (!found && kv_valid[j] && kv_key[j] == req_key) begin
                 found     = 1'b1;
                 found_idx = j;
               end
               if (!empty_found && !kv_valid[j]) begin
                 empty_found = 1'b1;
                 empty_idx   = j;
               end
             end
             if (found) begin
               kv_val[found_idx] <= req_val;
               success           <= 1'b1;
             end else if (empty_found) begin
               kv_key[empty_idx]   <= req_key;
               kv_val[empty_idx]   <= req_val;
               kv_valid[empty_idx] <= 1'b1;
               success             <= 1'b1;
             end else begin
               success             <= 1'b0; // table full
             end
             rsp_data_q       <= '0;
             rsp_data_q[0]    <= success;
           end
 
           // 0x22 DEL: delete key; success flag in bit[0]
           8'h22: begin
             bit found, success;
             int found_idx;
             found     = 1'b0;
             success   = 1'b0;
             found_idx = 0;
             for (int j = 0; j < KV_ENTRIES; j++) begin
               if (!found && kv_valid[j] && kv_key[j] == req_key) begin
                 found     = 1'b1;
                 found_idx = j;
               end
             end
             if (found) begin
               kv_valid[found_idx] <= 1'b0;
               kv_key[found_idx]   <= '0;
               kv_val[found_idx]   <= '0;
               success             <= 1'b1;
             end
             rsp_data_q       <= '0;
             rsp_data_q[0]    <= success;
           end
 
           default: begin
             // Unrecognized opcode -> mirror payload
             rsp_data_q <= s_axis_req.TDATA;
           end
         endcase
 
         pending_q  <= 1'b1;
         version_q  <= version_q + 32'd1;
       end
 
       // Complete response on handshake
       if (pending_q && m_axis_rsp.TVALID && m_axis_rsp.TREADY) begin
         pending_q <= 1'b0;
       end
     end
   end
 
   always_comb begin
     s_axis_req.TREADY = (~pending_q) & m_axis_rsp.TREADY;
 
     m_axis_rsp.TVALID = pending_q;
     m_axis_rsp.TDATA  = rsp_data_q;
     m_axis_rsp.TKEEP  = '1;
     m_axis_rsp.TLAST  = 1'b1;
 
     busy            = pending_q;
     version_counter = version_q;
   end
 
 endmodule : gmf_bank
