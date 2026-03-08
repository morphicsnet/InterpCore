// SPDX-License-Identifier: Apache-2.0
// Module: axi4l_pkg
// Purpose: AXI4-Lite package: parameters, typedefs, and interface with master/slave modports
// Clock/Reset: Interfaces carry clk and active-low rst_n
// Notes:
// - Use UPPERCASE channel signal names to match the rest of the RTL
// - BRESP/RRESP use axi4l_resp_e typedef for type safety

package axi4l_pkg;

  // Parameter defaults for AXI4-Lite
  parameter int AXI4L_ADDR_WIDTH = 32;
  parameter int AXI4L_DATA_WIDTH = 32;
  parameter int AXI4L_STRB_WIDTH = AXI4L_DATA_WIDTH/8;

  // Typedefs
  typedef logic [AXI4L_ADDR_WIDTH-1:0] axi4l_addr_t;
  typedef logic [AXI4L_DATA_WIDTH-1:0] axi4l_data_t;
  typedef logic [AXI4L_STRB_WIDTH-1:0] axi4l_strb_t;
  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi4l_resp_e;

  // AXI4-Lite interface
  interface axi4l_if #(
    parameter int ADDR_WIDTH = AXI4L_ADDR_WIDTH,
    parameter int DATA_WIDTH = AXI4L_DATA_WIDTH,
    parameter int STRB_WIDTH = DATA_WIDTH/8
  ) (
    input  logic clk,
    input  logic rst_n
  );
    // Write address channel
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [2:0]            AWPROT;
    logic                  AWVALID;
    logic                  AWREADY;

    // Write data channel
    logic [DATA_WIDTH-1:0] WDATA;
    logic [STRB_WIDTH-1:0] WSTRB;
    logic                  WVALID;
    logic                  WREADY;

    // Write response channel
    axi4l_resp_e           BRESP;
    logic                  BVALID;
    logic                  BREADY;

    // Read address channel
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [2:0]            ARPROT;
    logic                  ARVALID;
    logic                  ARREADY;

    // Read data channel
    logic [DATA_WIDTH-1:0] RDATA;
    axi4l_resp_e           RRESP;
    logic                  RVALID;
    logic                  RREADY;

    // Master modport
    modport master (
      input  clk, input rst_n,
      // AW
      output AWADDR, AWPROT, AWVALID,
      input  AWREADY,
      // W
      output WDATA, WSTRB, WVALID,
      input  WREADY,
      // B
      input  BRESP, BVALID,
      output BREADY,
      // AR
      output ARADDR, ARPROT, ARVALID,
      input  ARREADY,
      // R
      input  RDATA, RRESP, RVALID,
      output RREADY
    );

    // Slave modport
    modport slave (
      input  clk, input rst_n,
      // AW
      input  AWADDR, AWPROT, AWVALID,
      output AWREADY,
      // W
      input  WDATA, WSTRB, WVALID,
      output WREADY,
      // B
      output BRESP, BVALID,
      input  BREADY,
      // AR
      input  ARADDR, ARPROT, ARVALID,
      output ARREADY,
      // R
      output RDATA, RRESP, RVALID,
      input  RREADY
    );

    // TODO: Optional USER sideband and helper tasks for CSR access

  endinterface : axi4l_if

endpackage : axi4l_pkg
