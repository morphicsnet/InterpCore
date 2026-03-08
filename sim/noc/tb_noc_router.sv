// SPDX-License-Identifier: Apache-2.0
// File: tb_noc_router.sv
// Purpose: Minimal self-checking testbench for NoC router pass-through
// Clock: 100 MHz, Reset: active-low

`timescale 1ns/1ps
import noc_pkg::*;

module tb_noc_router;

  localparam int VCS    = noc_pkg::NOC_VC_NUM;
  localparam int FLIT_W = noc_pkg::NOC_FLIT_W;

  logic clk;
  logic rst_n;

  // A and B router IOs
  logic                  in_valid_A [5][VCS];
  logic                  in_ready_A [5][VCS];
  logic [FLIT_W-1:0]     in_flit_A  [5][VCS];
  logic                  out_valid_A[5][VCS];
  logic                  out_ready_A[5][VCS];
  logic [FLIT_W-1:0]     out_flit_A [5][VCS];

  logic                  in_valid_B [5][VCS];
  logic                  in_ready_B [5][VCS];
  logic [FLIT_W-1:0]     in_flit_B  [5][VCS];
  logic                  out_valid_B[5][VCS];
  logic                  out_ready_B[5][VCS];
  logic [FLIT_W-1:0]     out_flit_B [5][VCS];

  logic [7:0]            credit_in_A [5][VCS];
  logic [7:0]            credit_out_A[5][VCS];
  logic [7:0]            credit_in_B [5][VCS];
  logic [7:0]            credit_out_B[5][VCS];

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
        in_valid_A[p][v] = 1'b0;
        in_flit_A [p][v] = '0;
        out_ready_A[p][v]= 1'b1;
        credit_in_A[p][v]= '0;

        in_valid_B[p][v] = 1'b0;
        in_flit_B [p][v] = '0;
        out_ready_B[p][v]= 1'b1;
        credit_in_B[p][v]= '0;
      end
    end
  end

  // DUTs
  noc_router #(.FLIT_W(FLIT_W), .VCS(VCS)) u_router_A (
    .clk(clk), .rst_n(rst_n),
    .in_valid(in_valid_A), .in_ready(in_ready_A), .in_flit(in_flit_A),
    .out_valid(out_valid_A), .out_ready(out_ready_A), .out_flit(out_flit_A),
    .credit_in(credit_in_A), .credit_out(credit_out_A)
  );

  noc_router #(.FLIT_W(FLIT_W), .VCS(VCS)) u_router_B (
    .clk(clk), .rst_n(rst_n),
    .in_valid(in_valid_B), .in_ready(in_ready_B), .in_flit(in_flit_B),
    .out_valid(out_valid_B), .out_ready(out_ready_B), .out_flit(out_flit_B),
    .credit_in(credit_in_B), .credit_out(credit_out_B)
  );

  // Wire A.East -> B.West (VC0) and propagate backpressures
  // Port indices: N=0,S=1,E=2,W=3,L=4
  generate
    genvar vc;
    for (vc = 0; vc < VCS; vc++) begin
      // A.E -> B.W
      assign in_valid_B[3][vc] = out_valid_A[2][vc];
      assign in_flit_B [3][vc] = out_flit_A [2][vc];
      assign out_ready_A[2][vc]= in_ready_B [3][vc];

      // Keep other directions idle
    end
  endgenerate

  // Test stimulus: drive a single flit on A.West VC0 and expect on B.East VC0
  initial begin : test_sequence
    noc_hdr_t hdr;
    hdr.src      = 8'hAA;
    hdr.dst      = 8'hBB;
    hdr.vc       = VC0_CTRL;
    hdr.pkt_type = 4'h1;
    hdr.len      = 8'd1;

    // Wait for reset deassert
    @(posedge rst_n);
    @(posedge clk);

    // Drive one flit on A.West VC0
    in_flit_A [3][0] = { {FLIT_W-30{1'b0}}, hdr }; // place header in LSBs
    in_valid_A[3][0] = 1'b1;
    @(posedge clk);
    in_valid_A[3][0] = 1'b0;

    // Expect delivery on B.East VC0 within N cycles
    int cycles = 0;
    bit delivered = 0;
    while (cycles < 16) begin
      @(posedge clk);
      if (out_valid_B[2][0]) begin
        delivered = 1;
        // Immediate assertions
        assert (out_flit_B[2][0][7:0]   == hdr.len);
        assert (out_flit_B[2][0][11:8]  == hdr.pkt_type);
        assert (out_flit_B[2][0][13:12] == hdr.vc);
        assert (out_flit_B[2][0][21:14] == hdr.dst);
        assert (out_flit_B[2][0][29:22] == hdr.src);
        break;
      end
      cycles++;
    end
    assert (delivered) else $fatal(1, "Flit not delivered within 16 cycles");
    $display("tb_noc_router: PASS");
    $finish;
  end

endmodule : tb_noc_router
