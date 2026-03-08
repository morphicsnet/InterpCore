// SPDX-License-Identifier: Apache-2.0
// File: pta_scheduler.sv
// Purpose: PTA round-robin scheduler stub
// Clock/Reset Domain: fabric or dedicated PTA domain, active-low rst_n
// TODO:
// - Implement RR over contexts and dispatch to PEs
// - Connect GMF request queue

import axi4s_pkg::*;

module pta_scheduler #(
  parameter int NUM_PES          = 4,
  parameter int CONTEXTS_PER_PE  = 8,
  parameter int TDATA_W          = 256
) (
  input  logic                 clk,
  input  logic                 rst_n,

  // PE control
  output logic [NUM_PES-1:0]   pe_start,
  input  logic [NUM_PES-1:0]   pe_idle,

  // GMF request/response
  axi4s_if.master              m_axis_gmf_req,
  axi4s_if.slave               s_axis_gmf_rsp
);
  
  // Round-robin pointer over PEs
  localparam int IDX_W = (NUM_PES <= 1) ? 1 : $clog2(NUM_PES);
  logic [IDX_W-1:0] rr_ptr_q, rr_ptr_d;

  always_comb begin
    // Default outputs
    pe_start              = '0;
    m_axis_gmf_req.TVALID = 1'b0;
    m_axis_gmf_req.TDATA  = '0;
    m_axis_gmf_req.TKEEP  = '1;   // full-beat keep
    m_axis_gmf_req.TLAST  = 1'b1; // single-beat request
    s_axis_gmf_rsp.TREADY = 1'b1;

    // Find next idle PE starting from rr_ptr_q
    bit found;
    int found_idx;
    found     = 1'b0;
    found_idx = 0;

    for (int i = 0; i < NUM_PES; i++) begin
      int idx;
      idx = (rr_ptr_q + i) % NUM_PES;
      if (pe_idle[idx] && !found) begin
        found     = 1'b1;
        found_idx = idx;
      end
    end

    // Build a minimal request payload encoding the selected PE index
    logic [TDATA_W-1:0] req_data;
    req_data = '0;
    req_data[7:0]   = found_idx[7:0];
    req_data[15:8]  = 8'hC0;

    // Drive request when a PE is available; pulse start only on handshake
    if (found) begin
      m_axis_gmf_req.TVALID = 1'b1;
      m_axis_gmf_req.TDATA  = req_data;
      pe_start[found_idx]   = m_axis_gmf_req.TREADY;
    end

    // Next rr pointer: advance only on issued handshake
    rr_ptr_d = rr_ptr_q;
    if (found && m_axis_gmf_req.TREADY) rr_ptr_d = (found_idx + 1) % NUM_PES;
  end

  // Update RR pointer
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr_ptr_q <= '0;
    end else begin
      rr_ptr_q <= rr_ptr_d;
    end
  end

endmodule : pta_scheduler
