// SPDX-License-Identifier: Apache-2.0
// File: gmf_banks_cluster.sv
// Purpose: Cluster of GMF banks (stub instantiation), static hashing TODO
// Clock/Reset Domain: stream domain
// TODO:
// - Implement request hashing and response merge

import axi4s_pkg::*;

module gmf_banks_cluster #(
  parameter int N_BANKS = 4,
  parameter int TDATA_W = 256
) (
  input  logic    clk,
  input  logic    rst_n,

  // Aggregate request/response (to be demux/mux'ed internally later)
  axi4s_if.slave  s_axis_req,
  axi4s_if.master m_axis_rsp
);

  // Internal stubs for banks
  genvar i;
  generate
    for (i = 0; i < N_BANKS; i++) begin : gen_banks
      axi4s_if #(.TDATA_W(TDATA_W)) req_if (.ACLK(clk), .ARESETn(rst_n));
      axi4s_if #(.TDATA_W(TDATA_W)) rsp_if (.ACLK(clk), .ARESETn(rst_n));

      gmf_bank #(.TDATA_W(TDATA_W)) u_bank (
        .clk        (clk),
        .rst_n      (rst_n),
        .s_axis_req (req_if),
        .m_axis_rsp (rsp_if),
        .busy       (/* unused */),
        .version_counter(/* unused */)
      );

      // Driven by cluster-level demux/mux logic below
    end
  endgenerate

  // Cluster aggregate demux/mux (single-beat, single-outstanding)
  localparam int BANK_IDX_W = (N_BANKS <= 1) ? 1 : $clog2(N_BANKS);

  // Single-outstanding tracker for ordered request/response pairing
  logic                    inflight_q;
  logic [BANK_IDX_W-1:0]   sel_idx_q;

  always_comb begin
    // Defaults for aggregate
    s_axis_req.TREADY = 1'b0;
    m_axis_rsp.TVALID = 1'b0;
    m_axis_rsp.TDATA  = '0;
    m_axis_rsp.TKEEP  = '0;
    m_axis_rsp.TLAST  = 1'b0;

    // Defaults for all banks
    for (int bi = 0; bi < N_BANKS; bi++) begin
      // Drive all req_if low by default
      gen_banks[bi].req_if.TVALID = 1'b0;
      gen_banks[bi].req_if.TDATA  = '0;
      gen_banks[bi].req_if.TKEEP  = '0;
      gen_banks[bi].req_if.TLAST  = 1'b0;
      // Responses not ready by default
      gen_banks[bi].rsp_if.TREADY = 1'b0;
    end

    // Hash/select target bank from low bits of payload
    logic [BANK_IDX_W-1:0] sel_idx;
    sel_idx = s_axis_req.TDATA[BANK_IDX_W-1:0];

    // Demux request to selected bank only when no inflight txn
    if (s_axis_req.TVALID && !inflight_q) begin
      gen_banks[sel_idx].req_if.TVALID = 1'b1;
      gen_banks[sel_idx].req_if.TDATA  = s_axis_req.TDATA;
      gen_banks[sel_idx].req_if.TKEEP  = s_axis_req.TKEEP;
      gen_banks[sel_idx].req_if.TLAST  = s_axis_req.TLAST;
      s_axis_req.TREADY                = gen_banks[sel_idx].req_if.TREADY;
    end

    // Mux response from the bank that accepted the request
    if (inflight_q) begin
      m_axis_rsp.TVALID = gen_banks[sel_idx_q].rsp_if.TVALID;
      m_axis_rsp.TDATA  = gen_banks[sel_idx_q].rsp_if.TDATA;
      m_axis_rsp.TKEEP  = gen_banks[sel_idx_q].rsp_if.TKEEP;
      m_axis_rsp.TLAST  = gen_banks[sel_idx_q].rsp_if.TLAST;
      gen_banks[sel_idx_q].rsp_if.TREADY = m_axis_rsp.TREADY;
    end
  end

  // Sequential: track inflight transaction and selected bank index
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      inflight_q <= 1'b0;
      sel_idx_q  <= '0;
    end else begin
      // Latch selection on accepted request
      if (s_axis_req.TVALID && s_axis_req.TREADY) begin
        inflight_q <= 1'b1;
        sel_idx_q  <= s_axis_req.TDATA[BANK_IDX_W-1:0];
      end
      // Clear inflight on response handshake (single beat)
      if (m_axis_rsp.TVALID && m_axis_rsp.TREADY) begin
        inflight_q <= 1'b0;
      end
    end
  end

endmodule : gmf_banks_cluster
