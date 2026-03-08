// SPDX-License-Identifier: Apache-2.0
// File: fsm_pipeline.sv
// Purpose: FSM pipeline stub with backpressure pass-through
// Clock/Reset Domain: clk_fsm_1g / rst_n
// TODO:
// - Implement pipeline stages: parse, canonicalize, emit

import axi4s_pkg::*;

module fsm_pipeline #(
  parameter int TDATA_W = 256
) (
  input  logic     clk,
  input  logic     rst_n,

  axi4s_if.slave   s_axis,
  axi4s_if.master  m_axis
);

  // One-stage register-slice with canonical label injection into low bits
  localparam int KEY_W   = 64;
  localparam int TUPLE_W = (TDATA_W >= 128) ? 128 : TDATA_W;

  logic                vld_q;
  logic [TDATA_W-1:0]  data_q;
  logic [(TDATA_W+7)/8-1:0] keep_q;
  logic                last_q;

  logic [KEY_W-1:0]    key_w;
  logic [TUPLE_W-1:0]  tuple_w;

  assign tuple_w = s_axis.TDATA[TUPLE_W-1:0];

  fsm_canonical_label #(
    .WIDTH_IN (TUPLE_W),
    .WIDTH_OUT(KEY_W)
  ) u_label (
    .clk     (clk),
    .rst_n   (rst_n),
    .tuple_in(tuple_w),
    .key_out (key_w)
  );

  // Backpressure: accept when empty or when downstream consumes
  always_comb begin
    s_axis.TREADY = (~vld_q) | (vld_q & m_axis.TREADY);

    m_axis.TVALID = vld_q;
    m_axis.TDATA  = data_q;
    m_axis.TKEEP  = keep_q;
    m_axis.TLAST  = last_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      vld_q  <= 1'b0;
      data_q <= '0;
      keep_q <= '0;
      last_q <= 1'b0;
    end else begin
      // Load on input handshake
      if (s_axis.TVALID && s_axis.TREADY) begin
        vld_q  <= 1'b1;
        data_q <= s_axis.TDATA;
        // inject key into low bits
        data_q[KEY_W-1:0] <= key_w;
        keep_q <= s_axis.TKEEP;
        last_q <= s_axis.TLAST;
      end
      // Drain on output handshake
      if (m_axis.TVALID && m_axis.TREADY) begin
        vld_q <= 1'b0;
      end
    end
  end

endmodule : fsm_pipeline
