// SPDX-License-Identifier: Apache-2.0
// File: tb_noc_multi_vc.sv
// Purpose: Multi-VC stimulus/scoreboard for noc_router across directions
// Clock: 100 MHz, Reset: active-low

`timescale 1ns/1ps
import noc_pkg::*;

module tb_noc_multi_vc;

  localparam int VCS     = noc_pkg::NOC_VC_NUM;
  localparam int FLIT_W  = noc_pkg::NOC_FLIT_W;
  localparam int HDR_W   = noc_pkg::NOC_HDR_W;

  // Ports indices
  localparam int P_N = 0;
  localparam int P_S = 1;
  localparam int P_E = 2;
  localparam int P_W = 3;
  localparam int P_L = 4;

  // Clock/reset
  logic clk;
  logic rst_n;

  // Router IOs
  logic                  in_valid [5][VCS];
  logic                  in_ready [5][VCS];
  logic [FLIT_W-1:0]     in_flit  [5][VCS];

  logic                  out_valid[5][VCS];
  logic                  out_ready[5][VCS];
  logic [FLIT_W-1:0]     out_flit [5][VCS];

  logic [7:0]            credit_in [5][VCS];
  logic [7:0]            credit_out[5][VCS];

  // Clock
  initial clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  // Reset
  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // Defaults
  initial begin : init_ios
    int p, v;
    for (p = 0; p < 5; p++) begin
      for (v = 0; v < VCS; v++) begin
        in_valid[p][v]  = 1'b0;
        in_flit [p][v]  = '0;
        out_ready[p][v] = 1'b1;
        credit_in[p][v] = '0;
      end
    end
  end

  // DUT
  noc_router #(
    .FLIT_W(FLIT_W),
    .VCS   (VCS),
    .CUR_X (0),
    .CUR_Y (0)
  ) u_router (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .in_ready  (in_ready),
    .in_flit   (in_flit),
    .out_valid (out_valid),
    .out_ready (out_ready),
    .out_flit  (out_flit),
    .credit_in (credit_in),
    .credit_out(credit_out)
  );

  // Task to drive a single-flit transaction on a given VC and direction
  task automatic drive_and_expect(
    input int vc,
    input int src_port,       // ingress port index
    input int dst_port,       // egress port index
    input byte src_id,
    input byte dst_xy         // {y[3:0], x[3:0]} per noc_router route_port
  );
    noc_hdr_t hdr;
    logic [FLIT_W-1:0] flit;
    int cycles;
    bit delivered;

    begin
      hdr.src      = src_id;
      hdr.dst      = dst_xy;
      hdr.vc       = vc[1:0];
      hdr.pkt_type = 4'h1;
      hdr.len      = 8'd1;

      flit = '0;
      flit[FLIT_W-1 -: HDR_W] = hdr;

      // Drive one cycle pulse
      @(posedge clk);
      in_flit [src_port][vc] <= flit;
      in_valid[src_port][vc] <= 1'b1;
      @(posedge clk);
      in_valid[src_port][vc] <= 1'b0;

      // Expect on dst_port
      cycles    = 0;
      delivered = 0;
      while (cycles < 32) begin
        @(posedge clk);
        if (out_valid[dst_port][vc]) begin
          delivered = 1;
          // Check header fields in place
          assert(out_flit[dst_port][vc][FLIT_W-1 -: 8] == hdr.src)
            else $fatal(1, "SRC mismatch on VC%0d", vc);
          // pkt_type and len are within the header word; rough check on vc field
          // exact field bit slices depend on noc_hdr_t packing, we check VC field:
          // Extract header to a temp and compare structure fields
          noc_hdr_t oh;
          oh = out_flit[dst_port][vc][FLIT_W-1 -: HDR_W];
          assert(oh.vc == hdr.vc) else $fatal(1, "VC field mismatch exp=%0d got=%0d", hdr.vc, oh.vc);
          assert(oh.dst == hdr.dst) else $fatal(1, "DST mismatch");
          break;
        end
        cycles++;
      end
      assert(delivered) else $fatal(1, "Flit on VC%0d not delivered within 32 cycles", vc);
    end
  endtask

  // Test sequence:
  // - For each VC, send West->East; then North->South; then South->North
  initial begin : test_sequence
    // Wait reset
    @(posedge rst_n);
    @(posedge clk);

    // VC-wise West->East (dst x>0 for XY routing)
    for (int vc = 0; vc < VCS; vc++) begin
      drive_and_expect(vc, P_W, P_E, 8'h10 + vc[7:0], 8'h01); // dst_x=1,dst_y=0
    end

    // VC-wise North->South (dst y>0)
    for (int vc = 0; vc < VCS; vc++) begin
      drive_and_expect(vc, P_N, P_S, 8'h20 + vc[7:0], 8'h10); // dst_x=0,dst_y=1
    end

    // VC-wise South->North (dst y<0 encoded as local rule -> route to N)
    for (int vc = 0; vc < VCS; vc++) begin
      drive_and_expect(vc, P_S, P_N, 8'h30 + vc[7:0], 8'h00); // dst at (0,0) -> Local; N/S swap validates path
    end

    $display("tb_noc_multi_vc: PASS");
    $finish;
  end

endmodule : tb_noc_multi_vc