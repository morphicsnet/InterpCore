# NSI-CP Simulation Scaffolding

This directory contains minimal simulation scaffolding for module-level bring-up.

Targets:
- `noc/tb_noc_router.sv` — simple two-router fragment that sends a single flit from Router A West to Router B East and asserts delivery.

Example invocations (adjust tool paths as needed):

- Verilator:
  verilator -sv --cc hw/rtl/common/axi4l_pkg.sv hw/rtl/common/axi4s_pkg.sv hw/rtl/common/noc_pkg.sv hw/rtl/common/util_pkg.sv \
                   hw/rtl/noc/noc_router.sv sim/noc/tb_noc_router.sv --exe sim_main.cpp
  # Provide a trivial sim_main.cpp or use --build and --run with your harness.

- Questa:
  vlog +acc=rn hw/rtl/common/*.sv hw/rtl/noc/*.sv sim/noc/tb_noc_router.sv
  vsim -c tb_noc_router -do "run -all; quit"

- Synopsys VCS:
  vcs -sverilog -full64 hw/rtl/common/*.sv hw/rtl/noc/*.sv sim/noc/tb_noc_router.sv -o simv
  ./simv

Notes:
- These are placeholders; point to your simulator and flags per your environment.
- Ensure your simulator supports SystemVerilog-2017 features as used in packages/interfaces.
