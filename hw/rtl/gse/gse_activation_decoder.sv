 // SPDX-License-Identifier: Apache-2.0
 // File: gse_activation_decoder.sv
 // Purpose: Activation decoder (BYTE/FP16/FX16 threshold)
 // Clock/Reset Domain: stream domain
 
 import axi4s_pkg::*;
 
 module gse_activation_decoder #(
   parameter int TDATA_W        = 256,
   // Legacy byte threshold for DATA_FMT=0
   parameter int THRESHOLD      = 0,
   // Data format selector:
   // 0 = BYTE (compare any byte > THRESHOLD)
   // 1 = FP16 (hit if any 16b half has exponent >= FP16_EXP_THR and exponent != 0)
   // 2 = FX16 (signed Q1.15; hit if abs(value) > FX16_ABS_THR)
   parameter int DATA_FMT       = 0,
   parameter logic [4:0]  FP16_EXP_THR  = 5'd5,
   parameter logic [15:0] FX16_ABS_THR  = 16'd1024
 ) (
   input  logic     clk,
   input  logic     rst_n,
 
   axi4s_if.slave   s_axis,
   axi4s_if.master  m_axis
 );
 
   localparam int BYTES  = (TDATA_W+7)/8;
   localparam int HALVES = (TDATA_W+15)/16;
   logic hit;
 
   always_comb begin
     hit = 1'b0;
     unique case (DATA_FMT)
       0: begin : fmt_byte
         // Any byte above THRESHOLD
         for (int i = 0; i < BYTES; i++) begin
           if (s_axis.TDATA[i*8 +: 8] > THRESHOLD[7:0]) hit = 1'b1;
         end
       end
       1: begin : fmt_fp16
         // Approx FP16: exponent field threshold (ignore sign; exclude subnormals exp=0)
         for (int i = 0; i < HALVES; i++) begin
           logic [15:0] h;
           h = s_axis.TDATA[i*16 +: 16];
           if (h[14:10] != 5'd0 && h[14:10] >= FP16_EXP_THR) hit = 1'b1;
         end
       end
       default: begin : fmt_fx16
         // Signed Q1.15: abs(value) > FX16_ABS_THR
         for (int i = 0; i < HALVES; i++) begin
           logic signed [15:0] fx;
           logic [15:0] abs_fx;
           fx     = s_axis.TDATA[i*16 +: 16];
           abs_fx = fx[15] ? (~fx + 16'd1) : fx;
           if (abs_fx > FX16_ABS_THR) hit = 1'b1;
         end
       end
     endcase
 
     // Forward when hit; otherwise consume-and-drop to keep pipeline moving
     m_axis.TVALID = s_axis.TVALID & hit;
     m_axis.TDATA  = s_axis.TDATA;
     m_axis.TKEEP  = s_axis.TKEEP;
     m_axis.TLAST  = s_axis.TLAST;
 
     s_axis.TREADY = (hit ? m_axis.TREADY : 1'b1);
   end
 
 endmodule : gse_activation_decoder
