 // SPDX-License-Identifier: Apache-2.0
 // File: mc_axi_regs.sv
 // Purpose: AXI-Lite CSR slave with simple readable/writable flops for early integration
 // Clock/Reset Domain: clk_host or clk_mc (AXI domain), active-low rst_n
 // Improvements:
 // - Independent AW/W/AR capture
 // - Clear-on-write counters (addresses 64..65) when WDATA[0]==1
 // - Stable ready/valid handshakes
 
 import axi4l_pkg::*;
 import util_pkg::*;
 
 module mc_axi_regs #(
   parameter int ADDR_W = 12, // 4KB window
   parameter int DATA_W = 32
 ) (
   input  logic      ACLK,
   input  logic      ARESETn,
   axi4l_if.slave    s_axi
 );
 
   localparam int REG_WORDS = (1 << ADDR_W)/4;
 
   // Register banks per 4KB window
   logic [DATA_W-1:0] regs_mc  [0:255];
   logic [DATA_W-1:0] regs_gse [0:255];
   logic [DATA_W-1:0] regs_gmf [0:255];
   logic [DATA_W-1:0] regs_pta [0:255];
   logic [DATA_W-1:0] regs_fsm [0:255];
   logic [DATA_W-1:0] regs_dma [0:255];
 
   // Window decode
   localparam int WINDOW_SHIFT = 12; // 4KB per window
   typedef enum logic [3:0] {WIN_MC=4'h0, WIN_GSE=4'h1, WIN_GMF=4'h2, WIN_PTA=4'h3, WIN_FSM=4'h4, WIN_DMA=4'h5} win_e;
 
   // Channel state
   logic                   aw_captured, w_captured, ar_captured;
   logic [ADDR_W-1:0]      awaddr_q,    araddr_q;
   win_e                   aw_win_q,    ar_win_q;
   logic [DATA_W-1:0]      wdata_q,     rdata_q;
   logic                   bvalid_q,    rvalid_q;
 
   // Comb outputs
   always_comb begin
     s_axi.AWREADY = ARESETn & ~aw_captured & ~bvalid_q;
     s_axi.WREADY  = ARESETn & ~w_captured  & ~bvalid_q;
     s_axi.ARREADY = ARESETn & ~ar_captured & ~rvalid_q;
 
     s_axi.BRESP   = 2'b00; // OKAY
     s_axi.RRESP   = 2'b00; // OKAY
 
     s_axi.BVALID  = bvalid_q;
     s_axi.RVALID  = rvalid_q;
     s_axi.RDATA   = rdata_q;
   end
 
   // Sequential logic
   always_ff @(posedge ACLK or negedge ARESETn) begin
     if (!ARESETn) begin
       aw_captured <= 1'b0;
       w_captured  <= 1'b0;
       ar_captured <= 1'b0;
       awaddr_q    <= '0;
       araddr_q    <= '0;
       wdata_q     <= '0;
       rdata_q     <= '0;
       bvalid_q    <= 1'b0;
       rvalid_q    <= 1'b0;
       // init example regs in MC window; zero others
       regs_mc[0]  <= 32'h0000_0000; // CONTROL
       regs_mc[1]  <= 32'h0000_0001; // STATUS
       regs_mc[64] <= 32'h0000_0000; // COUNTERS[0]
       regs_mc[65] <= 32'h0000_0000; // COUNTERS[1]
       for (int i = 0; i < 256; i++) begin
         if (i != 0 && i != 1 && i != 64 && i != 65) regs_mc[i] <= '0;
         regs_gse[i] <= '0;
         regs_gmf[i] <= '0;
         regs_pta[i] <= '0;
         regs_fsm[i] <= '0;
         regs_dma[i] <= '0;
       end
     end else begin
       // Capture address/data channels
       if (!aw_captured && s_axi.AWVALID && s_axi.AWREADY) begin
         awaddr_q    <= s_axi.AWADDR[ADDR_W-1:0];
         aw_win_q    <= win_e'(s_axi.AWADDR[WINDOW_SHIFT+3:WINDOW_SHIFT]);
         aw_captured <= 1'b1;
       end
       if (!w_captured && s_axi.WVALID && s_axi.WREADY) begin
         wdata_q     <= s_axi.WDATA;
         w_captured  <= 1'b1;
       end
       if (!ar_captured && s_axi.ARVALID && s_axi.ARREADY) begin
         araddr_q    <= s_axi.ARADDR[ADDR_W-1:0];
         ar_win_q    <= win_e'(s_axi.ARADDR[WINDOW_SHIFT+3:WINDOW_SHIFT]);
         ar_captured <= 1'b1;
       end
 
       // Perform write when both captured
       if (aw_captured && w_captured && !bvalid_q) begin
         int widx;
         widx = awaddr_q[9:2]; // word index within 4KB
         // Clear-on-write behavior for MC counters when bit0==1
         if ((aw_win_q == WIN_MC) && (widx == 64 || widx == 65) && wdata_q[0]) begin
           regs_mc[widx] <= '0;
         end else begin
           unique case (aw_win_q)
             WIN_MC : regs_mc[widx]  <= wdata_q;
             WIN_GSE: regs_gse[widx] <= wdata_q;
             WIN_GMF: regs_gmf[widx] <= wdata_q;
             WIN_PTA: regs_pta[widx] <= wdata_q;
             WIN_FSM: regs_fsm[widx] <= wdata_q;
             WIN_DMA: regs_dma[widx] <= wdata_q;
             default: /* drop */;
           endcase
         end
         bvalid_q    <= 1'b1;
         aw_captured <= 1'b0;
         w_captured  <= 1'b0;
       end
 
       // Complete B channel
       if (s_axi.BVALID && s_axi.BREADY) begin
         bvalid_q <= 1'b0;
       end
 
       // Read path
       if (ar_captured && !rvalid_q) begin
         int ridx;
         ridx    = araddr_q[9:2];
         unique case (ar_win_q)
           WIN_MC : rdata_q = regs_mc[ridx];
           WIN_GSE: rdata_q = regs_gse[ridx];
           WIN_GMF: rdata_q = regs_gmf[ridx];
           WIN_PTA: rdata_q = regs_pta[ridx];
           WIN_FSM: rdata_q = regs_fsm[ridx];
           WIN_DMA: rdata_q = regs_dma[ridx];
           default: rdata_q = '0;
         endcase
         rvalid_q <= 1'b1;
         ar_captured <= 1'b0;
       end
       if (s_axi.RVALID && s_axi.RREADY) begin
         rvalid_q <= 1'b0;
       end
     end
   end
 
 endmodule : mc_axi_regs
