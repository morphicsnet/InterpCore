use crate::core::types::{NodeId, SaeFeature};
use crate::core::config::Config;
use std::collections::{HashSet, VecDeque};
use tokio::sync::mpsc;

pub struct GraphStreamingEngine {
    pub window_size: usize,
    pub buffer: VecDeque<SaeFeature>,
    pub island_max_size: usize,
    pub dedup_recent_n: usize,
    pub drop_on_full: bool,
}

impl GraphStreamingEngine {
    // Legacy constructor with conservative defaults (keeps existing tests intact)
    pub fn new(window_size: usize) -> Self {
        Self {
            window_size,
            buffer: VecDeque::with_capacity(window_size),
            island_max_size: 3,
            dedup_recent_n: 3,
            drop_on_full: false,
        }
    }

    // Config-driven constructor
    pub fn from_config(cfg: &Config) -> Self {
        Self {
            window_size: cfg.gse.window_size,
            buffer: VecDeque::with_capacity(cfg.gse.window_size),
            island_max_size: cfg.gse.island_max_size,
            dedup_recent_n: cfg.gse.island_dedup_recent_n,
            drop_on_full: cfg.gse.drop_on_full,
        }
    }

    pub async fn run(
        &mut self,
        mut rx_activations: mpsc::Receiver<SaeFeature>,
        tx_candidates: mpsc::Sender<Vec<NodeId>>,
    ) {
        while let Some(feat) = rx_activations.recv().await {
            self.buffer.push_back(feat);
            while self.buffer.len() > self.window_size {
                self.buffer.pop_front();
            }

            // Emit a small candidate island when the window has at least 2 items
            if self.buffer.len() >= 2 {
                let tmp: Vec<SaeFeature> = self.buffer.iter().cloned().collect();
                let island = self.detect_archipelago_island(&tmp);
                if !island.is_empty() {
                    if self.drop_on_full {
                        // Throughput-first: drop on full to avoid backpressure
                        let _ = tx_candidates.try_send(island);
                    } else {
                        // Accuracy-first: await send and never drop
                        let _ = tx_candidates.send(island).await;
                    }
                }
            }
        }
    }

    /// Heuristic: take last up to dedup_recent_n distinct NodeIds (most recent-first),
    /// cap to island_max_size, then sort ascending.
    pub fn detect_archipelago_island(&self, buffer: &[SaeFeature]) -> Vec<NodeId> {
        let mut recent: Vec<NodeId> = Vec::new();
        let mut seen: HashSet<NodeId> = HashSet::new();
        let limit = self.dedup_recent_n.min(self.island_max_size).max(1);
        for f in buffer.iter().rev() {
            if seen.insert(f.id) {
                recent.push(f.id);
                if recent.len() >= limit {
                    break;
                }
            }
        }
        recent.sort_by_key(|id| id.0);
        if recent.len() > self.island_max_size {
            recent.truncate(self.island_max_size);
        }
        recent
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gse_detects_up_to_three_sorted_unique() {
        let gse = GraphStreamingEngine::new(4);
        let mut buf = Vec::new();
        // IDs: 2, 3, 2, 1 (reverse scan should capture 1,2,3 then sort -> 1,2,3)
        buf.push(SaeFeature { id: NodeId(2), activation: 0.0, timestamp_ns: 1, layer: None, label: None });
        buf.push(SaeFeature { id: NodeId(3), activation: 0.0, timestamp_ns: 2, layer: None, label: None });
        buf.push(SaeFeature { id: NodeId(2), activation: 0.0, timestamp_ns: 3, layer: None, label: None });
        buf.push(SaeFeature { id: NodeId(1), activation: 0.0, timestamp_ns: 4, layer: None, label: None });
        let island = gse.detect_archipelago_island(&buf);
        assert_eq!(island, vec![NodeId(1), NodeId(2), NodeId(3)]);
    }
}