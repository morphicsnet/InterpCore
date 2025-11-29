use rayon::prelude::*;
use roaring::RoaringBitmap;
use uuid::Uuid;

use crate::core::config::{Config, Profile, SampleStrategy};
use crate::core::types::{Hyperedge, InteractionType, NodeId};

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use rand::Rng;
use rand::SeedableRng;
use rand::seq::index::sample;
use rand_chacha::ChaCha8Rng;

pub trait ModelOracle: Send + Sync {
    fn get_loss_delta(&self, masked_features: &RoaringBitmap) -> f32;
}

pub struct ParallelTraversalAccelerator {
    pub oracle: Box<dyn ModelOracle + Send + Sync>,
    pub stii_threshold: f32,
    pub max_k: u8,
    pub max_subsets: usize,
    pub cfg: Option<Config>,
}

impl ParallelTraversalAccelerator {
    pub fn new(
        oracle: Box<dyn ModelOracle + Send + Sync>,
        stii_threshold: f32,
        max_k: u8,
        max_subsets: usize,
    ) -> Self {
        Self {
            oracle,
            stii_threshold,
            max_k,
            max_subsets,
            cfg: None,
        }
    }

    pub fn from_config(oracle: Box<dyn ModelOracle + Send + Sync>, cfg: &Config) -> Self {
        Self {
            oracle,
            stii_threshold: cfg.pta.stii_threshold,
            max_k: cfg.pta.max_k,
            max_subsets: cfg.pta.max_subsets,
            cfg: Some(cfg.clone()),
        }
    }

    pub fn estimate_stii(&self, island: Vec<NodeId>, target: NodeId) -> Option<Hyperedge> {
        if island.is_empty() {
            return None;
        }
        let sources_bitmap: RoaringBitmap = island.iter().map(|id| id.0).collect();

        // Config-driven paths
        if let Some(cfg) = &self.cfg {
            match cfg.profile {
                Profile::Openai => {
                    let subsets = self.sample_subsets_openai(&island, target, cfg);
                    if subsets.is_empty() {
                        return None;
                    }
                    let sum_abs: f32 = subsets
                        .par_iter()
                        .map(|subset| self.oracle.get_loss_delta(subset).abs())
                        .sum();
                    let mean_abs = sum_abs / (subsets.len() as f32);
                    if mean_abs >= self.stii_threshold {
                        return Some(Hyperedge {
                            id: Some(Uuid::new_v4()),
                            sources: sources_bitmap,
                            target,
                            interaction_type: InteractionType::Synergistic,
                            stii_weight: mean_abs,
                        });
                    }
                    return None;
                }
                Profile::Anthropic => {
                    let (mean_abs, half_width) =
                        self.stream_estimate_with_ci(&island, target, cfg);
                    let accept = if cfg.pta.early_stop {
                        (mean_abs - half_width) >= self.stii_threshold
                    } else {
                        mean_abs >= self.stii_threshold
                    };
                    if accept {
                        return Some(Hyperedge {
                            id: Some(Uuid::new_v4()),
                            sources: sources_bitmap,
                            target,
                            interaction_type: InteractionType::Synergistic,
                            stii_weight: mean_abs,
                        });
                    }
                    return None;
                }
            }
        }

        // Fallback: deterministic capped enumeration
        let subsets = Self::generate_powerset(&island, self.max_k, self.max_subsets);
        if subsets.is_empty() {
            return None;
        }
        let sum_abs: f32 = if subsets.len() > 1 {
            subsets
                .par_iter()
                .map(|subset| self.oracle.get_loss_delta(subset).abs())
                .sum()
        } else {
            subsets
                .iter()
                .map(|subset| self.oracle.get_loss_delta(subset).abs())
                .sum()
        };
        let mean_abs = sum_abs / (subsets.len() as f32);
        if mean_abs >= self.stii_threshold {
            Some(Hyperedge {
                id: Some(Uuid::new_v4()),
                sources: sources_bitmap,
                target,
                interaction_type: InteractionType::Synergistic,
                stii_weight: mean_abs,
            })
        } else {
            None
        }
    }

    /// OPENAI throughput path: Monte Carlo sampling with deterministic seed.
    fn sample_subsets_openai(
        &self,
        island: &[NodeId],
        target: NodeId,
        cfg: &Config,
    ) -> Vec<RoaringBitmap> {
        let n = island.len();
        if n == 0 {
            return Vec::new();
        }
        let k_max = (cfg.pta.max_k as usize).min(n).max(1);
        let sample_count = cfg.pta.sample_count.min(self.max_subsets).max(1);

        // Deterministic seed from (island, target, profile)
        let mut hasher = DefaultHasher::new();
        for id in island.iter().map(|x| x.0) {
            id.hash(&mut hasher);
        }
        target.0.hash(&mut hasher);
        "openai".hash(&mut hasher);
        let seed = hasher.finish();
        let mut rng = ChaCha8Rng::seed_from_u64(seed);

        let mut out = Vec::with_capacity(sample_count);
        for _ in 0..sample_count {
            // Simple k selection: uniform from 1..=k_max (can later stratify by C(n,k))
            let k = rng.gen_range(1..=k_max) as usize;
            let sel = sample(&mut rng, n, k);
            let mut bm = RoaringBitmap::new();
            for idx in sel.into_iter() {
                bm.insert(island[idx].0);
            }
            out.push(bm);
        }
        out
    }

    /// Anthropic accuracy path: streaming mean/variance with CI and early stop.
    /// Returns (mean_abs, half_width).
    fn stream_estimate_with_ci(
        &self,
        island: &[NodeId],
        target: NodeId,
        cfg: &Config,
    ) -> (f32, f32) {
        let n = island.len();
        if n == 0 {
            return (0.0, 0.0);
        }
        let k_max = (cfg.pta.max_k as usize).min(n).max(1);
        let max_n = cfg.pta.sample_count.min(self.max_subsets).max(1);

        // Deterministic seed from (island, target, profile)
        let mut hasher = DefaultHasher::new();
        for id in island.iter().map(|x| x.0) {
            id.hash(&mut hasher);
        }
        target.0.hash(&mut hasher);
        "anthropic".hash(&mut hasher);
        let seed = hasher.finish();
        let mut rng = ChaCha8Rng::seed_from_u64(seed);

        // Welford online mean/variance of |delta|
        let mut mean = 0.0_f32;
        let mut m2 = 0.0_f32;
        let mut count: usize = 0;

        // Z-score (normal approx) for common CIs
        let z = match (cfg.pta.ci_confidence * 100.0).round() as i32 {
            90 => 1.645,
            95 => 1.96,
            99 => 2.576,
            _ => 1.96,
        };

        for _ in 0..max_n {
            let k = rng.gen_range(1..=k_max) as usize;
            let sel = sample(&mut rng, n, k);
            let mut bm = RoaringBitmap::new();
            for idx in sel.into_iter() {
                bm.insert(island[idx].0);
            }
            // Optional replicates per subset to average out oracle noise
            let reps = cfg.pta.replicates_per_subset.max(1);
            let mut acc = 0.0_f32;
            for _ in 0..reps {
                acc += self.oracle.get_loss_delta(&bm).abs();
            }
            let delta = acc / (reps as f32);

            count += 1;
            // Welford updates
            let diff = delta - mean;
            mean += diff / (count as f32);
            let diff2 = delta - mean;
            m2 += diff * diff2;

            if cfg.pta.early_stop && count >= 30 {
                let var = (m2 / ((count - 1) as f32)).max(0.0);
                let std_err = (var / (count as f32)).sqrt();
                let half_width = z * std_err;
                if half_width <= cfg.pta.ci_target_width {
                    return (mean, half_width);
                }
            }
        }

        if count > 1 {
            let var = (m2 / ((count - 1) as f32)).max(0.0);
            let std_err = (var / (count as f32)).sqrt();
            let half_width = z * std_err;
            (mean, half_width)
        } else {
            (mean, 0.0)
        }
    }

    /// Deterministic combination generator (used in tests and fallback).
    pub fn generate_powerset(ids: &[NodeId], max_k: u8, max_subsets: usize) -> Vec<RoaringBitmap> {
        if ids.is_empty() || max_k == 0 {
            return Vec::new();
        }
        let mut sorted: Vec<NodeId> = ids.to_vec();
        sorted.sort_by_key(|id| id.0);

        let mut out = Vec::<RoaringBitmap>::new();
        let n = sorted.len();
        let k_max = (max_k as usize).min(n);

        for k in 1..=k_max {
            // first combination [0..k)
            let mut idx: Vec<usize> = (0..k).collect();
            loop {
                let bm: RoaringBitmap = idx.iter().map(|&i| sorted[i].0).collect::<RoaringBitmap>();
                out.push(bm);
                if out.len() >= max_subsets {
                    return out;
                }
                // next lexicographic combination
                let mut i = k;
                while i > 0 {
                    i -= 1;
                    if idx[i] != i + n - k {
                        idx[i] += 1;
                        for j in i + 1..k {
                            idx[j] = idx[j - 1] + 1;
                        }
                        break;
                    }
                }
                if i == 0 && idx[0] == n - k && idx[k - 1] == n - 1 {
                    break;
                }
            }
            if out.len() >= max_subsets {
                break;
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::types::NodeId;

    #[test]
    fn pta_generate_powerset_caps() {
        let ids = vec![NodeId(1), NodeId(2), NodeId(3), NodeId(4)];
        let v = ParallelTraversalAccelerator::generate_powerset(&ids, 2, 3);
        assert!(v.len() <= 3);
        for bm in &v {
            let sz = bm.iter().count();
            assert!(sz == 1 || sz == 2);
            for x in bm.iter() {
                assert!((1..=4).any(|n| n == x));
            }
        }
    }
}