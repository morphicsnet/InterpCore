# InterpCore RTL Bring-Up Guide
> Navigable map for the NSI-CP RTL scaffolding: layout, conventions, simulation entry points, and integration hooks.

## Choose your path
- I want the repo-level story: [InterpCore root](../README.md)
- I want simulation first: [sim/README.md](../sim/README.md)
- I want FPGA planning: [FPGA_BRINGUP.md](FPGA_BRINGUP.md)

## What lives where
- `hw/rtl/common`: shared packages and interfaces
- `hw/rtl/top`: top-level integration shells
- `hw/rtl/host`: host endpoint and DMA stubs
- `hw/rtl/noc`: NoC router and bridges
- `hw/rtl/gse`, `hw/rtl/gmf`, `hw/rtl/pta`, `hw/rtl/fsm`, `hw/rtl/mc`, `hw/rtl/clkreset`: functional blocks and glue
- `hw/regs`: HJSON register-map placeholders
- `fpga/`: board wrappers and constraints
- `sim/`: simulation testbenches and smoke benches

## Conventions
- SystemVerilog-2017
- shared typedefs and parameters through packages, not magic widths
- active-low resets named `rst_n` / `rstn_*`
- AXI4-Lite and AXI4-Stream conventions through interfaces
- CDC made explicit; do not bury it in convenience logic

## Bring-up workflow
1. start with a small sim target in [`sim/`](../sim/README.md)
2. validate shared packages and interfaces compile cleanly
3. add or wire a specific block
4. only then widen to top-level or FPGA wrappers

## Adding registers
- author HJSON in `hw/regs/*.hjson`
- implement block CSR directly in RTL or through generated regfiles later
- use `mc_axi_regs.sv` as the early, low-ceremony reference point

## Adding a NoC endpoint
- control path: wire an AXI4-Lite bridge on VC0
- stream path: wire an AXI4S packetizer on VC1/VC2/VC3
- connect through `noc_router.sv` and declare routing/VC policy early

## Lint and simulation guidance
- use Verilator plus commercial lint if available
- enable width/unused warnings early
- keep placeholder modules compile-ready even before they are functionally deep

## Go next
- Root guide: [InterpCore](../README.md)
- Simulation lab: [sim README](../sim/README.md)
- FPGA notes: [FPGA_BRINGUP.md](FPGA_BRINGUP.md)
