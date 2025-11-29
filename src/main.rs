mod core;
mod engines;

use crate::core::hif::export_hif_json;
use crate::core::types::{GraphMemoryFabric, NodeId, SaeFeature};
use crate::engines::fsm::FrequentSubgraphMiner;
use crate::engines::gse::GraphStreamingEngine;
use crate::engines::pta::{ModelOracle, ParallelTraversalAccelerator};
use crate::core::config::{Config, Profile, choose_profile_from_args_env};
use roaring::RoaringBitmap;
use tokio::sync::mpsc;
use std::env;

struct DummyOracle;
impl ModelOracle for DummyOracle {
    fn get_loss_delta(&self, masked_features: &RoaringBitmap) -> f32 {
        let sz = masked_features.iter().count();
        if sz >= 2 { 0.06 } else { 0.02 }
    }
}

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    println!("Initializing InterpCore Co-Processor Simulation...");

    // Select profile and build Config
    let profile = choose_profile_from_args_env(env::args());
    let mut cfg = match profile {
        Profile::Openai => Config::openai_defaults(),
        Profile::Anthropic => Config::anthropic_defaults(),
    };
    cfg.apply_env_overrides();

    // Configure rayon global pool once (ignore error if already set)
    let _ = rayon::ThreadPoolBuilder::new()
        .num_threads(cfg.pta.max_parallelism)
        .build_global();

    // Shared memory fabric and engines
    let gmf = GraphMemoryFabric::default();
    let fsm = FrequentSubgraphMiner::new(cfg.fsm.frequency_threshold);
    let pta = ParallelTraversalAccelerator::from_config(Box::new(DummyOracle), &cfg);

    // Channels sized by profile
    let (tx_activations, rx_activations) =
        mpsc::channel::<SaeFeature>(cfg.channels.activations_capacity);
    let (tx_candidates, mut rx_candidates) =
        mpsc::channel::<Vec<NodeId>>(cfg.channels.candidates_capacity);

    // Start GSE
    let mut gse = GraphStreamingEngine::from_config(&cfg);
    tokio::spawn(async move {
        gse.run(rx_activations, tx_candidates).await;
    });

    // Simulate activations
    for id in 1u32..=4u32 {
        let feat = SaeFeature {
            id: NodeId(id),
            activation: 1.0,
            timestamp_ns: id as u64,
            layer: Some(0),
            label: Some(format!("feat-{}", id)),
        };
        if tx_activations.send(feat).await.is_err() {
            break;
        }
    }
    // Close the activations stream
    drop(tx_activations);

    // Process candidate islands until the GSE sender is dropped and channel closes
    while let Some(island) = rx_candidates.recv().await {
        // Choose a target (largest id for demo)
        let target = island.last().copied().unwrap_or(NodeId(0));
        if let Some(h) = pta.estimate_stii(island.clone(), target) {
            // Ensure nodes exist in GMF
            for id in h.sources.iter().chain(std::iter::once(target.0)) {
                let nid = NodeId(id);
                if !gmf.nodes.contains_key(&nid) {
                    gmf.insert_node(SaeFeature {
                        id: nid,
                        activation: 0.0,
                        timestamp_ns: 0,
                        layer: None,
                        label: None,
                    });
                }
            }
            gmf.insert_hyperedge(h.clone());

            // Stream a simple hyperpath to FSM: sources (as u64) + target + label=1
            let mut path: Vec<u64> = h.sources.iter().map(|x| x as u64).collect();
            path.sort_unstable();
            path.push(target.0 as u64);
            path.push(1u64); // synthetic edge label
            let label = fsm.canonicalize(&path);
            fsm.increment_pattern(label);
        }
    }

    // Export HIF and print
    let hif = export_hif_json(&gmf);
    println!("{}", serde_json::to_string_pretty(&hif).unwrap());

    println!("System Ready. Demo complete.");
}
