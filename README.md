# InterpCore (NSI-CP) - Rust Simulation

## Overview
InterpCore is a single-crate Rust simulation of the Neuro-Symbolic Interpretability Co-Processor (NSI-CP) dataflow: Graph Streaming Engine (GSE), Parallel Traversal Accelerator (PTA), Frequent Subgraph Miner (FSM), Graph Memory Fabric (GMF), and HIF export.

## Quickstart
```bash
cargo build
cargo run
```

Expected behavior:
- Prints readiness
- Processes synthetic activations
- Discovers at least one hyperedge (dummy oracle)
- Prints HIF JSON

## Repository Map
- `src/` Rust simulation (GSE, PTA, FSM, GMF, HIF)
- `hw/` RTL scaffolding and register stubs
- `fpga/` board wrappers and constraints
- `sim/` simulation testbenches
- `docs/` developer documentation

## Configuration
Profile selection order (highest to lowest):
1. CLI flag: `--profile openai|anthropic`
2. Env var: `NSICP_PROFILE=openai|anthropic`
3. Cargo features: `--features openai` or `--features anthropic`
4. Default: `anthropic`

Environment overrides:
- `NSICP_STII_THRESHOLD` (f32)
- `NSICP_MAX_K` (u8)
- `NSICP_PTA_SAMPLE_COUNT` (usize)
- `NSICP_ACT_CAP` (usize)
- `NSICP_CAND_CAP` (usize)

## Docs Index
- FPGA bring-up: `docs/FPGA_BRINGUP.md`
- RTL scaffolding: `docs/RTL_README.md`

## Development and Testing
```bash
cargo test
```

## Status and Limitations
- Simulation and RTL are scaffolding for bring-up and integration planning.
- HIF export is a minimal JSON shape intended for early validation.
