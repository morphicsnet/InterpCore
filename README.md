# interpchip

interpchip is a Rust and RTL workspace for graph streaming, hyperedge storage, traversal scoring, and HIF export. It is best understood as an early execution substrate for hypergraph-oriented interpretability workloads.

## Core Objects

The software path is built around:

- streamed feature activations
- graph-memory-fabric node and hyperedge storage
- candidate traversal and scoring
- frequent-subgraph pattern counting
- HIF JSON export

## Current Status

### Real Today

- concrete Rust types for graph memory fabric and HIF export
- a runnable software demo path
- profile and configuration handling
- traversal and graph-streaming scaffolding sufficient for early validation

### Still Placeholder or Synthetic

- the main demo uses `DummyOracle`
- the main demo feeds simulated activations
- frequent-subgraph canonicalization is still a placeholder sort
- much of `hw/` and `fpga/` is bring-up scaffolding rather than complete hardware

Representative paths:

- `src/main.rs`
- `src/engines/fsm.rs`
- `hw/rtl/top/nsi_cp_top.sv`
- `hw/rtl/host/pcie_cxl_endpoint.sv`
- `fpga/agilex/top_agilex.sv`
- `fpga/versax/top_versax.sv`

## Repository Map

- `src/`: Rust simulation and export path
- `sim/`: simulation support
- `hw/`: RTL surfaces
- `fpga/`: board wrappers and constraints
- `docs/`: hardware and bring-up notes

## Quickstart

```bash
cargo build
cargo run
```

Current demo behavior:

- initialize the software substrate
- process simulated activations
- discover at least one hyperedge through the current demo path
- print a minimal HIF JSON export

## Testing

```bash
cargo test
```

See also:

- [sim/README.md](sim/README.md)
- [docs/RTL_README.md](docs/RTL_README.md)
- [docs/FPGA_BRINGUP.md](docs/FPGA_BRINGUP.md)

## Status

- The Rust software path is the most concrete surface.
- The hardware tree is still explicitly incomplete.
- This repo should be treated as a substrate under construction, not a finished silicon program.
