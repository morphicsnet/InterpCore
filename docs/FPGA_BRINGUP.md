# NSI-CP FPGA Bring-up Plan

This plan outlines a staged bring-up to de-risk integration:

1) Synthesis-only wrappers
- Build [fpga/versax/top_versax.sv](../fpga/versax/top_versax.sv) or [fpga/agilex/top_agilex.sv](../fpga/agilex/top_agilex.sv)
- Use [fpga/constraints/top.xdc](../fpga/constraints/top.xdc) templates for clocks/resets
- Replace `clkgen.sv` with board PLLs later

2) NoC loopback test
- Keep [noc_router.sv](../hw/rtl/noc/noc_router.sv) pass-through
- Add simple traffic generation and observe fabric IO/LEDs

3) Add GSE windowing
- Chain [gse_ingress_dma.sv](../hw/rtl/gse/gse_ingress_dma.sv) -> [gse_activation_decoder.sv](../hw/rtl/gse/gse_activation_decoder.sv) -> [gse_window_buffer.sv](../hw/rtl/gse/gse_window_buffer.sv) -> [gse_island_builder.sv](../hw/rtl/gse/gse_island_builder.sv)

4) DMA loopback
- Use [dma_engine.sv](../hw/rtl/host/dma_engine.sv) streams loopback to validate bandwidth and backpressure

5) Stub host link
- Keep [pcie_cxl_endpoint.sv](../hw/rtl/host/pcie_cxl_endpoint.sv) as signals-only until vendor IP integration
- Exercise CSR via [mc_axi_regs.sv](../hw/rtl/mc/mc_axi_regs.sv)

Constraints notes:
- Keep clock uncertainty conservative until PLLs are in place
- Document IO standards per board schematics
