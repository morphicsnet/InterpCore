// SPDX-License-Identifier: Apache-2.0
// File: util_pkg.sv
// Purpose: Common utilities: clog2 macro, onehot encode/decode stubs
// Clock/Reset Domain: N/A
// TODO:
// - Extend to parameterized onehot widths
// - Add parity/CRC helpers

`ifndef UTIL_PKG_CLOG2
`define UTIL_PKG_CLOG2(x) ( \
  ((x) <= 1) ? 0 : \
  ((x) <= 2) ? 1 : \
  ((x) <= 4) ? 2 : \
  ((x) <= 8) ? 3 : \
  ((x) <= 16) ? 4 : \
  ((x) <= 32) ? 5 : \
  ((x) <= 64) ? 6 : \
  ((x) <= 128) ? 7 : \
  ((x) <= 256) ? 8 : \
  ((x) <= 512) ? 9 : \
  ((x) <= 1024) ? 10 : 11 )
`endif

package util_pkg;

  // Active-low reset convention: rst_n
  function automatic logic [31:0] onehot_encode(input int idx);
    logic [31:0] oh;
    oh = '0;
    if (idx >= 0 && idx < 32) oh[idx] = 1'b1;
    return oh;
  endfunction

  function automatic int onehot_decode(input logic [31:0] oh);
    int idx;
    idx = -1;
    for (int i = 0; i < 32; i++) begin
      if (oh[i]) idx = i;
    end
    return idx; // If multiple bits set, returns highest index
  endfunction

endpackage : util_pkg
