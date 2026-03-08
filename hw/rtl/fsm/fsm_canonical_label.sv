// SPDX-License-Identifier: Apache-2.0
// File: fsm_canonical_label.sv
// Purpose: Canonical label pipeline stub
// Clock/Reset Domain: clk_fsm_1g / rst_n
// TODO:
// - Implement tuple->key derivation and hashing

module fsm_canonical_label #(
  parameter int WIDTH_IN  = 128,
  parameter int WIDTH_OUT = 64
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic [WIDTH_IN-1:0]  tuple_in,
  output logic [WIDTH_OUT-1:0] key_out
);

  // Lightweight combinational canonical key derivation via XOR-fold + rotate
  function automatic [WIDTH_OUT-1:0] rol(input [WIDTH_OUT-1:0] x, input int sh);
    automatic int s;
    begin
      s = ((sh % WIDTH_OUT) + WIDTH_OUT) % WIDTH_OUT;
      rol = (x << s) | (x >> (WIDTH_OUT - s));
    end
  endfunction

  logic [WIDTH_OUT-1:0] acc, chunk;

  always_comb begin
    acc = {WIDTH_OUT{1'b0}};
    acc[WIDTH_OUT-1 -: (WIDTH_OUT>64?64:WIDTH_OUT)] = 64'h9E37_79B9_7F4A_7C15[ (WIDTH_OUT>64?64:WIDTH_OUT)-1 : 0 ];

    for (int i = 0; i < WIDTH_IN; i += WIDTH_OUT) begin
      chunk = '0;
      for (int b = 0; b < WIDTH_OUT; b++) begin
        if (i + b < WIDTH_IN) chunk[b] = tuple_in[i + b];
      end
      acc = rol(acc ^ chunk, 13) ^ {{(WIDTH_OUT>6?WIDTH_OUT-6:0){1'b0}}, i[5:0]};
      acc = acc ^ (acc >> 7);
    end

    key_out = acc ^ (acc << 17);
  end

endmodule : fsm_canonical_label
