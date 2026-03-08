// SPDX-License-Identifier: Apache-2.0
// File: noc_router.sv
// Purpose: NoC router with simple XY routing, per-VC 2-entry input FIFOs, RR arbitration
// Clock/Reset Domain: clk_fab / rst_n (active-low)

`timescale 1ns/1ps
import noc_pkg::*;

module noc_router #(
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VCS    = noc_pkg::NOC_VC_NUM,
  parameter int CUR_X  = 0,
  parameter int CUR_Y  = 0
) (
  input  logic clk,
  input  logic rst_n,
  // Ingress
  input  logic                  in_valid [5][VCS],
  output logic                  in_ready [5][VCS],
  input  logic [FLIT_W-1:0]     in_flit  [5][VCS],
  // Egress
  output logic                  out_valid[5][VCS],
  input  logic                  out_ready[5][VCS],
  output logic [FLIT_W-1:0]     out_flit [5][VCS],
  // Credits
  input  logic [7:0]            credit_in [5][VCS],
  output logic [7:0]            credit_out[5][VCS]
);

  localparam int P_N = 0;
  localparam int P_S = 1;
  localparam int P_E = 2;
  localparam int P_W = 3;
  localparam int P_L = 4;
  localparam int PORTS = 5;
  localparam int HDR_W  = noc_pkg::NOC_HDR_W;

  // Per-input, per-VC 2-entry FIFO
  logic [FLIT_W-1:0] fifo_d0 [PORTS][VCS];
  logic [FLIT_W-1:0] fifo_d1 [PORTS][VCS];
  logic [1:0]        fifo_cnt[PORTS][VCS]; // 0..2

  // Round-robin pointer per output and VC (next starting input index)
  logic [2:0] rr_ptr[PORTS][VCS]; // need 3 bits for 0..4

  // Helpers
  function automatic noc_pkg::noc_hdr_t hdr_of(input logic [FLIT_W-1:0] flit);
    noc_pkg::noc_hdr_t h;
    h = flit[FLIT_W-1 -: HDR_W];
    return h;
  endfunction

  function automatic int route_port(input noc_pkg::noc_hdr_t h);
    int dst_x, dst_y;
    dst_x = h.dst[3:0];
    dst_y = h.dst[7:4];
    if ((dst_x == CUR_X) && (dst_y == CUR_Y)) begin
      return P_L;
    end
    if (dst_x > CUR_X) return P_E;
    if (dst_x < CUR_X) return P_W;
    if (dst_y > CUR_Y) return P_S;
    return P_N;
  endfunction

  // Ingress readiness based on FIFO space
  genvar gp, gv;
  generate
    for (gp = 0; gp < PORTS; gp++) begin : gen_in_ready
      for (gv = 0; gv < VCS; gv++) begin : gen_in_ready_v
        always_comb begin
          in_ready[gp][gv] = (fifo_cnt[gp][gv] != 2);
        end
      end
    end
  endgenerate

  // Default outputs and credits
  integer p, v;
  always_comb begin
    for (p = 0; p < PORTS; p++) begin
      for (v = 0; v < VCS; v++) begin
        out_valid[p][v]  = 1'b0;
        out_flit [p][v]  = '0;
        credit_out[p][v] = credit_in[p][v]; // pass-through for now
      end
    end
  end

  // Arbitration and output driving
  // Compute head-route for each input FIFO
  logic [2:0] head_route[PORTS][VCS]; // 0..4
  logic       head_valid[PORTS][VCS];
  always_comb begin
    for (p = 0; p < PORTS; p++) begin
      for (v = 0; v < VCS; v++) begin
        head_valid[p][v] = (fifo_cnt[p][v] != 0);
        if (head_valid[p][v]) begin
          head_route[p][v] = route_port(hdr_of(fifo_d0[p][v]));
        end else begin
          head_route[p][v] = '0;
        end
      end
    end
  end

  // Selection per output, per VC
  logic [2:0] sel_inport[PORTS][VCS];
  logic       sel_valid  [PORTS][VCS];
  always_comb begin
    for (int op = 0; op < PORTS; op++) begin
      for (int vv = 0; vv < VCS; vv++) begin
        sel_inport[op][vv] = '0;
        sel_valid [op][vv] = 1'b0;
        // Round-robin search starting at rr_ptr
        for (int i = 0; i < PORTS; i++) begin
          int idx;
          idx = (rr_ptr[op][vv] + i) % PORTS;
          if (head_valid[idx][vv] && head_route[idx][vv] == op) begin
            sel_inport[op][vv] = idx[2:0];
            sel_valid [op][vv] = 1'b1;
            break;
          end
        end
        // Drive outputs if selected
        if (sel_valid[op][vv]) begin
          out_valid[op][vv] = 1'b1;
          out_flit [op][vv] = fifo_d0[sel_inport[op][vv]][vv];
        end
      end
    end
  end

  // Sequential: FIFOs push/pop and RR pointer updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (p = 0; p < PORTS; p++) begin
        for (v = 0; v < VCS; v++) begin
          fifo_cnt[p][v] <= '0;
          rr_ptr [p][v]  <= '0;
          fifo_d0[p][v]  <= '0;
          fifo_d1[p][v]  <= '0;
        end
      end
    end else begin
      // Push from ingress
      for (p = 0; p < PORTS; p++) begin
        for (v = 0; v < VCS; v++) begin
          if (in_valid[p][v] && in_ready[p][v]) begin
            case (fifo_cnt[p][v])
              2'd0: begin
                fifo_d0[p][v] <= in_flit[p][v];
                fifo_cnt[p][v] <= 2'd1;
              end
              2'd1: begin
                fifo_d1[p][v] <= in_flit[p][v];
                fifo_cnt[p][v] <= 2'd2;
              end
              default: ; // full
            endcase
          end
        end
      end
      // Pop to egress and update RR
      for (int op = 0; op < PORTS; op++) begin
        for (int vv = 0; vv < VCS; vv++) begin
          if (sel_valid[op][vv] && out_valid[op][vv] && out_ready[op][vv]) begin
            int si;
            si = sel_inport[op][vv];
            // Pop from selected input FIFO
            case (fifo_cnt[si][vv])
              2'd2: begin
                fifo_d0[si][vv] <= fifo_d1[si][vv];
                fifo_cnt[si][vv] <= 2'd1;
              end
              2'd1: begin
                fifo_cnt[si][vv] <= 2'd0;
              end
              default: ;
            endcase
            // Advance RR pointer
            rr_ptr[op][vv] <= (si + 1) % PORTS;
          end
        end
      end
    end
  end

  // Simple assertions (synthesis off)
  // pragma translate_off
  always @(posedge clk) begin
    for (int op = 0; op < PORTS; op++) begin
      for (int vv = 0; vv < VCS; vv++) begin
        if (out_valid[op][vv]) begin
          // Ensure a corresponding input exists
          int si = sel_inport[op][vv];
          if (!head_valid[si][vv]) $error("Router drove out_valid without head_valid");
        end
      end
    end
  end
  // pragma translate_on

endmodule : noc_router
