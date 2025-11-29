use dashmap::DashMap;
use roaring::RoaringBitmap;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Copy, Clone, Eq, PartialEq, Ord, PartialOrd, Hash, Debug, Serialize, Deserialize)]
pub struct NodeId(pub u32);

impl From<u32> for NodeId {
    fn from(v: u32) -> Self {
        NodeId(v)
    }
}
impl From<NodeId> for u32 {
    fn from(n: NodeId) -> Self {
        n.0
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct SaeFeature {
    pub id: NodeId,
    pub activation: f32,
    pub timestamp_ns: u64,
    pub layer: Option<u16>,
    pub label: Option<String>,
}

#[derive(Clone, Copy, Eq, PartialEq, Hash, Debug, Serialize, Deserialize)]
pub enum InteractionType {
    Additive,
    Synergistic,
    Redundant,
    Inhibitory,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Hyperedge {
    pub id: Option<Uuid>,
    pub sources: RoaringBitmap,
    pub target: NodeId,
    pub interaction_type: InteractionType,
    pub stii_weight: f32,
}

#[derive(Default)]
pub struct GraphMemoryFabric {
    pub nodes: DashMap<NodeId, SaeFeature>,
    pub hyperedges_by_target: DashMap<NodeId, Vec<Hyperedge>>,
}

impl GraphMemoryFabric {
    pub fn insert_node(&self, feat: SaeFeature) {
        self.nodes.insert(feat.id, feat);
    }

    pub fn insert_hyperedge(&self, h: Hyperedge) {
        let key = h.target;
        self.hyperedges_by_target.entry(key).or_default().push(h);
    }
}

pub fn node_ids_to_bitmap<'a, I>(ids: I) -> RoaringBitmap
where
    I: IntoIterator<Item = &'a NodeId>,
{
    let mut bm = RoaringBitmap::new();
    for id in ids {
        bm.insert(id.0);
    }
    bm
}

pub fn bitmap_contains_node(bitmap: &RoaringBitmap, id: NodeId) -> bool {
    bitmap.contains(id.0)
}

#[derive(Debug, Error)]
pub enum NsiError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Serialization error: {0}")]
    Serde(#[from] serde_json::Error),
}
