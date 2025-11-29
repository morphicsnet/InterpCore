# InterpCore (NSI-CP) – Rust Simulation

Single-crate Rust implementation of the Neuro-Symbolic Interpretability Co-Processor (NSI-CP) dataflow:
- Graph Streaming Engine (GSE)
- Parallel Traversal Accelerator (PTA)
- Frequent Subgraph Miner (FSM)
- Graph Memory Fabric (GMF)
- HIF export

## Build and Run

```bash
cargo build
cargo run
```

Expected "hello world":
- Prints readiness
- Processes synthetic activations
- Discovers ≥ 1 hyperedge (dummy oracle threshold 0.05)
- FSM increments at least one motif
- Prints HIF JSON with network-type, nodes, and hyperedges

## Profiles

Select runtime profiles via CLI, environment variable, or Cargo features:

- CLI flag:
  ```bash
  cargo run -- --profile openai
  cargo run -- --profile anthropic
  ```
- Env var:
  ```bash
  NSICP_PROFILE=openai cargo run
  NSICP_PROFILE=anthropic cargo run
  ```
- Cargo features (build-time default):
  ```bash
  cargo run --features openai
  cargo run --features anthropic
  ```

OPENAI (throughput-first) defaults:
- GSE: window_size=128, island_max_size=6, dedup_recent_n=3, drop_on_full=true
- PTA: stii_threshold=0.05, max_k=3, max_subsets=50_000, sample_strategy=MonteCarlo, sample_count=20_000, early_stop=false, max_parallelism=num_cpus
- FSM: frequency_threshold=50, shard_count=8, local_batch_size=2048, merge_interval=10_000
- Channels: activations=16384, candidates=8192

Anthropic (accuracy-first) defaults:
- GSE: window_size=256, island_max_size=10, dedup_recent_n=5, drop_on_full=false
- PTA: stii_threshold=0.05, max_k=4, max_subsets=200_000, sample_strategy=QmcSobol, sample_count=100_000, ci_target_width=0.01, ci_confidence=0.95, early_stop=true, max_parallelism=min(half cores, 8)
- FSM: frequency_threshold=10, shard_count=1, local_batch_size=128, merge_interval=1_000
- Channels: activations=1024, candidates=512

Environment overrides:
- NSICP_STII_THRESHOLD, NSICP_MAX_K, NSICP_PTA_SAMPLE_COUNT, NSICP_ACT_CAP, NSICP_CAND_CAP

## Tests

```bash
cargo test
```

Tests cover:
- FSM canonicalization stability
- PTA powerset generation caps
- HIF export top-level fields and tail/head mapping