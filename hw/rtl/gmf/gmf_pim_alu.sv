// SPDX-License-Identifier: Apache-2.0
// File: gmf_pim_alu.sv
// Purpose: PIM ALU enum and pass-through result stub
// Clock/Reset Domain: any (combinational stub)
// TODO:
// - Implement ALU operations over payload

module gmf_pim_alu #(
  parameter int WIDTH = 32
) (
  input  logic [WIDTH-1:0]  a,
  input  logic [WIDTH-1:0]  b,
  input  logic [1:0]        op, // 0:ADD 1:BIT_SET 2:BIT_CLR 3:VERSION_INC
  output logic [WIDTH-1:0]  y
);

  localparam logic [1:0] OP_ADD         = 2'd0;
  localparam logic [1:0] OP_BIT_SET     = 2'd1;
  localparam logic [1:0] OP_BIT_CLR     = 2'd2;
  localparam logic [1:0] OP_VERSION_INC = 2'd3;

  // Combinational ALU
  always_comb begin
    unique case (op)
      OP_ADD:         y = a + b;
      OP_BIT_SET:     y = a | b;
      OP_BIT_CLR:     y = a & ~b;
      OP_VERSION_INC: y = a + {{(WIDTH-1){1'b0}}, 1'b1};
      default:        y = a;
    endcase
  end

endmodule : gmf_pim_alu
