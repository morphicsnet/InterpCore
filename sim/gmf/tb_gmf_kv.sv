// SPDX-License-Identifier: Apache-2.0
// File: tb_gmf_kv.sv
// Purpose: Unit test for GMF bank KV ops (PUT/GET/DEL) + legacy ops (ECHO/INC32/VERSION)

`timescale 1ns/1ps
import axi4s_pkg::*;

module tb_gmf_kv;

  localparam int TDATA_W = 256;
  localparam int CLK_PER = 10; // 100 MHz

  // Clock/Reset
  logic clk, rst_n;
  initial clk = 1'b0;
  always #(CLK_PER/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
  end

  // AXI-Stream wires
  axi4s_if #(.TDATA_W(TDATA_W)) if_req (.ACLK(clk), .ARESETn(rst_n));
  axi4s_if #(.TDATA_W(TDATA_W)) if_rsp (.ACLK(clk), .ARESETn(rst_n));

  // DUT
  gmf_bank #(.TDATA_W(TDATA_W)) u_bank (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_axis_req (if_req),
    .m_axis_rsp (if_rsp),
    .busy       (/* unused */),
    .version_counter(/* unused */)
  );

  // Always ready to consume responses
  initial begin
    if_rsp.TREADY = 1'b1;
  end

  // Helpers: pack request payload
  function automatic logic [TDATA_W-1:0] pack_req(input byte opcode, input logic [31:0] key, input logic [31:0] val);
    logic [TDATA_W-1:0] d; begin
      d = '0;
      d[7:0]    = opcode;
      d[39:8]   = key; // req_key slice in DUT
      d[71:40]  = val; // req_val slice in DUT
      return d;
    end
  endfunction

  // Handshake send (single beat)
  task automatic send_req(input logic [TDATA_W-1:0] data);
    begin
      if_req.TDATA  = data;
      if_req.TKEEP  = '1;
      if_req.TLAST  = 1'b1;
      if_req.TVALID = 1'b1;
      // wait handshake
      do @(posedge clk); while (!(if_req.TVALID && if_req.TREADY));
      @(posedge clk);
      if_req.TVALID = 1'b0;
      if_req.TLAST  = 1'b0;
    end
  endtask

  // Wait and capture a response
  task automatic recv_rsp(output logic [TDATA_W-1:0] d);
    begin
      do @(posedge clk); while (!(if_rsp.TVALID && if_rsp.TREADY));
      d = if_rsp.TDATA;
      // TLAST should be 1 for single-beat response
      if (if_rsp.TLAST !== 1'b1) $error("Response TLAST not asserted");
      // consume
      @(posedge clk);
    end
  endtask

  // Scoreboard
  int pass_cnt;

  // Stimulus
  initial begin : run
    logic [TDATA_W-1:0] d;
    logic [31:0] val_low;
    bit found;
    bit success;

    // Wait reset
    @(posedge rst_n);
    repeat (4) @(posedge clk);

    // VERSION (0x10): returns next version in low 32b
    send_req(pack_req(8'h10, 32'h0, 32'h0));
    recv_rsp(d);
    val_low = d[31:0];
    if (val_low == 32'd0) $fatal(1, "VERSION did not increment");
    pass_cnt++;

    // ECHO (0x00)
    logic [TDATA_W-1:0] echo_payload;
    echo_payload = pack_req(8'h00, 32'hDEAD_BEEF, 32'h1234_5678);
    send_req(echo_payload);
    recv_rsp(d);
    if (d !== echo_payload) $fatal(1, "ECHO mismatch");
    pass_cnt++;

    // INC32 (0x01)
    logic [31:0] base;
    base = 32'hABCD_0001;
    send_req(pack_req(8'h01, 32'h0, 32'h0) | base); // place base in low bits
    recv_rsp(d);
    if (d[31:0] !== base + 32'd1) $fatal(1, "INC32 incorrect");
    pass_cnt++;

    // PUT (0x21) key=DEADBEEF val=12345678 -> success flag in bit[0]
    send_req(pack_req(8'h21, 32'hDEAD_BEEF, 32'h1234_5678));
    recv_rsp(d);
    success = d[0];
    if (!success) $fatal(1, "PUT failed");
    pass_cnt++;

    // GET (0x20) key=DEADBEEF -> found flag in bit[32], value in [31:0]
    send_req(pack_req(8'h20, 32'hDEAD_BEEF, 32'h0));
    recv_rsp(d);
    found   = d[32];
    val_low = d[31:0];
    if (!found)                 $fatal(1, "GET did not find key");
    if (val_low !== 32'h1234_5678) $fatal(1, "GET returned wrong value");
    pass_cnt++;

    // DEL (0x22) key=DEADBEEF -> success=1
    send_req(pack_req(8'h22, 32'hDEAD_BEEF, 32'h0));
    recv_rsp(d);
    success = d[0];
    if (!success) $fatal(1, "DEL failed");
    pass_cnt++;

    // GET again -> not found
    send_req(pack_req(8'h20, 32'hDEAD_BEEF, 32'h0));
    recv_rsp(d);
    found = d[32];
    if (found) $fatal(1, "GET found deleted key");
    pass_cnt++;

    $display("tb_gmf_kv: PASS (%0d checks)", pass_cnt);
    $finish;
  end

endmodule : tb_gmf_kv