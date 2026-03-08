# NSI-CP RTL Scaffolding

This repository contains compile-ready module stubs and common packages to bootstrap RTL development and FPGA bring-up.

Folder layout:
- `hw/rtl/common` — shared packages and interfaces ([axi4l_pkg.sv](../hw/rtl/common/axi4l_pkg.sv), [axi4s_pkg.sv](../hw/rtl/common/axi4s_pkg.sv), [noc_pkg.sv](../hw/rtl/common/noc_pkg.sv), [util_pkg.sv](../hw/rtl/common/util_pkg.sv))
- `hw/rtl/top` — top-level integration ([nsi_cp_top.sv](../hw/rtl/top/nsi_cp_top.sv))
- `hw/rtl/host` — host endpoint and DMA stubs
- `hw/rtl/noc` — NoC router and bridges
- `hw/rtl/gse`, `hw/rtl/gmf`, `hw/rtl/pta`, `hw/rtl/fsm`, `hw/rtl/mc`, `hw/rtl/clkreset`
- `hw/regs` — HJSON placeholders for register maps
- `fpga` — FPGA wrappers and constraints
- `sim` — simulation testbenches
- `docs` — developer documentation

Coding standards:
- SystemVerilog-2017
- Use packages for shared typedefs/parameters (no magic widths)
- Active-low resets named `rst_n`/`rstn_*`
- AXI4-Lite/AXI4-Stream conventions via interfaces
- Keep CDC explicit; use `reset_sync.sv` synchronizers

Lint recommendations:
- Use Verilator + commercial lint (Questa Lint/SpyGlass) with SV-2017
- Enable unused/width mismatch warnings early

Adding registers:
- Author HJSON in `hw/regs/*.hjson` (JSON-compatible)
- Implement block CSR in RTL or use auto-generated regfiles
- `mc_axi_regs.sv` contains a minimal AXI-Lite slave with readable/writable flops for early tests

Adding a NoC endpoint:
- For control: implement an AXI4-Lite bridge ([noc_bridge_axi4l.sv](../hw/rtl/noc/noc_bridge_axi4l.sv)) on VC0
- For streams: implement AXI4S packetizer ([noc_bridge_axi4s.sv](../hw/rtl/noc/noc_bridge_axi4s.sv)) on VC1/VC2/VC3
- Connect to [noc_router.sv](../hw/rtl/noc/noc_router.sv) ports and establish routing/VC policy
