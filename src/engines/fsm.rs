use dashmap::DashMap;

#[derive(Clone, Debug, Hash, Eq, PartialEq)]
pub struct CanonicalLabel(pub Vec<u64>);

pub struct FrequentSubgraphMiner {
    pub pattern_counts: DashMap<CanonicalLabel, u64>,
    pub frequency_threshold: u64,
}

impl Default for FrequentSubgraphMiner {
    fn default() -> Self {
        Self {
            pattern_counts: DashMap::new(),
            frequency_threshold: 5,
        }
    }
}

impl FrequentSubgraphMiner {
    pub fn new(threshold: u64) -> Self {
        Self {
            pattern_counts: DashMap::new(),
            frequency_threshold: threshold,
        }
    }

    /// Deterministic placeholder: sort ascending; replace with DFS code later.
    pub fn canonicalize(&self, raw_path: &[u64]) -> CanonicalLabel {
        let mut v = raw_path.to_vec();
        v.sort_unstable();
        CanonicalLabel(v)
    }

    /// Concurrency-safe increment; promotes when threshold reached.
    pub fn increment_pattern(&self, label: CanonicalLabel) {
        let mut entry = self.pattern_counts.entry(label.clone()).or_insert(0);
        *entry += 1;
        if *entry == self.frequency_threshold {
            self.promote_to_rule(&label);
        }
    }

    pub fn promote_to_rule(&self, label: &CanonicalLabel) {
        println!("FSM::promote label={:?}", label);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fsm_canonicalize_stable_ordering() {
        let fsm = FrequentSubgraphMiner::default();
        let a = vec![3u64, 1, 2, 2];
        let b = vec![2u64, 3, 2, 1];
        let l1 = fsm.canonicalize(&a);
        let l2 = fsm.canonicalize(&b);
        assert_eq!(l1, l2);
    }
}