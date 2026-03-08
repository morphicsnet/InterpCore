// SPDX-License-Identifier: Apache-2.0
// File: reset_sync.sv
// Purpose: Standard multi-stage reset synchronizer (active-low async input)
// Clock/Reset Domain: synchronized to clk, output rst_n_sync active-low
// Implemented fully (functional)

module reset_sync #(
  parameter int STAGES = 2
) (
  input  logic clk,
  input  logic async_rst_n,
  output logic rst_n_sync
);

  // Require STAGES >= 2
  initial begin
    if (STAGES < 2) $error("reset_sync: STAGES must be >= 2");
  end

  logic [STAGES-1:0] shreg;

  always_ff @(posedge clk or negedge async_rst_n) begin
    if (!async_rst_n) begin
      shreg <= '0;
    end else begin
      shreg <= {shreg[STAGES-2:0], 1'b1};
    end
  end

  assign rst_n_sync = shreg[STAGES-1];

endmodule : reset_sync
