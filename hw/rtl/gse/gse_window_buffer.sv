// SPDX-License-Identifier: Apache-2.0
// File: gse_window_buffer.sv
// Purpose: Window buffer stub with enqueue/dequeue handshakes
// Clock/Reset Domain: stream domain
// TODO:
// - Implement RAM-based window buffering and boundary handling

module gse_window_buffer #(
  parameter int WIDTH = 256,
  parameter int DEPTH = 1024
) (
  input  logic                 clk,
  input  logic                 rst_n,

  // Enqueue
  input  logic                 enq_valid,
  output logic                 enq_ready,
  input  logic [WIDTH-1:0]     enq_data,

  // Dequeue
  output logic                 deq_valid,
  input  logic                 deq_ready,
  output logic [WIDTH-1:0]     deq_data
);

  // Ring buffer state
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [$clog2(DEPTH)-1:0]     wr_ptr, rd_ptr;
  logic [$clog2(DEPTH+1)-1:0]   count;

  // Outputs
  always_comb begin
    enq_ready = (count < DEPTH);
    deq_valid = (count != 0);
    deq_data  = mem[rd_ptr];
  end

  // Push/pop
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else begin
      // Enqueue
      if (enq_valid && enq_ready) begin
        mem[wr_ptr] <= enq_data;
        wr_ptr      <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
        count       <= count + 1'b1;
      end
      // Dequeue
      if (deq_valid && deq_ready) begin
        rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
        count  <= count - 1'b1;
      end
    end
  end

endmodule : gse_window_buffer
