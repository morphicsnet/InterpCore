// SPDX-License-Identifier: Apache-2.0
// File: pta_pe.sv
// Purpose: PTA processing element stub
// Clock/Reset Domain: PTA domain, active-low rst_n
// TODO:
// - Implement walker context RAM and constraints filters
// - Emit GMF requests and handle responses

import axi4s_pkg::*;

module pta_pe #(
  parameter int CTX_ADDR_W = 10,
  parameter int TDATA_W    = 256
) (
  input  logic               clk,
  input  logic               rst_n,

  // Context RAM ports (simple write-only stub)
  input  logic               ctx_we,
  input  logic [CTX_ADDR_W-1:0] ctx_waddr,
  input  logic [31:0]        ctx_wdata,

  // GMF request/response
  axi4s_if.master            m_axis_gmf_req,
  axi4s_if.slave             s_axis_gmf_rsp,

  // PRNG seed
  input  logic [31:0]        prng_seed
);
  
  // PE internal state and simple PRNG for mask synthesis
  typedef enum logic [1:0] {PE_IDLE, PE_ISSUE, PE_WAIT_RSP} pe_state_e;
  pe_state_e state_q, state_d;

  logic [31:0] lfsr_q;
  logic [TDATA_W-1:0] req_data;

  function automatic [31:0] lfsr_next(input [31:0] x);
    // x^32 + x^22 + x^2 + x^1 + 1
    lfsr_next = {x[30:0], x[31] ^ x[21] ^ x[1] ^ x[0]};
  endfunction

  always_comb begin
    // Defaults
    m_axis_gmf_req.TVALID = 1'b0;
    m_axis_gmf_req.TDATA  = '0;
    m_axis_gmf_req.TKEEP  = '1;
    m_axis_gmf_req.TLAST  = 1'b1;

    s_axis_gmf_rsp.TREADY = 1'b1;

    // Build request payload by repeating (ctx_wdata ^ lfsr_q) across width
    req_data = '0;
    for (int i = 0; i < TDATA_W; i++) begin
      req_data[i] = (ctx_wdata ^ lfsr_q)[i % 32];
    end

    // State machine
    state_d = state_q;
    unique case (state_q)
      PE_IDLE: begin
        if (ctx_we) begin
          state_d = PE_ISSUE;
        end
      end
      PE_ISSUE: begin
        m_axis_gmf_req.TVALID = 1'b1;
        m_axis_gmf_req.TDATA  = req_data;
        // full-beat request; single-beat transaction
        if (m_axis_gmf_req.TVALID && m_axis_gmf_req.TREADY) begin
          state_d = PE_WAIT_RSP;
        end
      end
      PE_WAIT_RSP: begin
        // Wait for a single-beat response
        if (s_axis_gmf_rsp.TVALID && s_axis_gmf_rsp.TREADY) begin
          state_d = PE_IDLE;
        end
      end
      default: state_d = PE_IDLE;
    endcase
  end

  // State register and LFSR advance
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= PE_IDLE;
      lfsr_q  <= prng_seed;
    end else begin
      state_q <= state_d;
      // Advance LFSR when a request is issued (one-beat transaction)
      if (m_axis_gmf_req.TVALID && m_axis_gmf_req.TREADY) begin
        lfsr_q <= lfsr_next(lfsr_q);
      end
    end
  end

endmodule : pta_pe
