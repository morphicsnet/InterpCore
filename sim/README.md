# InterpCore Simulation Lab
> Module-level and top-level scaffolding for exercising the NSI-CP dataflow before real bring-up pain arrives.

## Fastest path
Pick a simulator and run one of the existing smoke benches.

Example targets in this tree:
- `sim/noc/tb_noc_router.sv`
- `sim/noc/tb_noc_multi_vc.sv`
- `sim/gse/tb_activation_decoder.sv`
- `sim/gmf/tb_gmf_kv.sv`
- `sim/pipeline/tb_gse_gmf_smoke.sv`
- `sim/top/tb_nsi_cp_top_smoke.sv`

## Example invocations
### Verilator
```bash
verilator -sv --cc hw/rtl/common/axi4l_pkg.sv hw/rtl/common/axi4s_pkg.sv hw/rtl/common/noc_pkg.sv hw/rtl/common/util_pkg.sv   hw/rtl/noc/noc_router.sv sim/noc/tb_noc_router.sv --exe sim_main.cpp
```

### Questa
```bash
vlog +acc=rn hw/rtl/common/*.sv hw/rtl/noc/*.sv sim/noc/tb_noc_router.sv
vsim -c tb_noc_router -do "run -all; quit"
```

### Synopsys VCS
```bash
vcs -sverilog -full64 hw/rtl/common/*.sv hw/rtl/noc/*.sv sim/noc/tb_noc_router.sv -o simv
./simv
```

## What this surface is for
- router and VC smoke checks
- package and interface sanity checks
- simple pipeline bring-up before top-level integration gets crowded

## Go next
- Root guide: [InterpCore](../README.md)
- RTL bring-up: [docs/RTL_README.md](../docs/RTL_README.md)
- FPGA notes: [docs/FPGA_BRINGUP.md](../docs/FPGA_BRINGUP.md)
