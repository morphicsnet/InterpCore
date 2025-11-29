use crate::core::types::{GraphMemoryFabric, InteractionType, NodeId, SaeFeature};
use serde::Serialize;
use serde_json::Value;
use uuid::Uuid;

#[derive(Serialize)]
pub struct GraphNetwork {
    #[serde(rename = "network-type")]
    pub network_type: String,
    pub nodes: Vec<HifNode>,
    pub hyperedges: Vec<HifHyperedge>,
}

#[derive(Serialize)]
pub struct HifNode {
    pub id: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

#[derive(Serialize)]
pub struct HifHyperedge {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Uuid>,
    pub tail: Vec<u32>,
    pub head: u32,
    pub interaction_type: InteractionType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weight: Option<f32>,
}

pub fn export_hif_json(gmf: &GraphMemoryFabric) -> Value {
    // Collect nodes deterministically by ascending NodeId
    let mut nodes: Vec<(NodeId, SaeFeature)> =
        gmf.nodes.iter().map(|r| (*r.key(), r.value().clone())).collect();
    nodes.sort_by_key(|(id, _)| id.0);

    let nodes: Vec<HifNode> = nodes
        .into_iter()
        .map(|(id, feat)| HifNode {
            id: id.0,
            label: feat.label.clone(),
        })
        .collect();

    // Collect hyperedges deterministically by (head, tail)
    let mut hes = Vec::<HifHyperedge>::new();
    for entry in gmf.hyperedges_by_target.iter() {
        let target = entry.key();
        for h in entry.value().iter() {
            let mut tail: Vec<u32> = h.sources.iter().collect();
            tail.sort_unstable();
            hes.push(HifHyperedge {
                id: h.id,
                tail,
                head: target.0,
                interaction_type: h.interaction_type,
                weight: Some(h.stii_weight),
            });
        }
    }
    hes.sort_by(|a, b| a.head.cmp(&b.head).then_with(|| a.tail.cmp(&b.tail)));

    let net = GraphNetwork {
        network_type: "hypergraph".to_string(),
        nodes,
        hyperedges: hes,
    };
    serde_json::to_value(net).expect("serialize HIF")
}

pub fn write_hif_json(gmf: &GraphMemoryFabric, path: &str) -> Result<(), std::io::Error> {
    let v = export_hif_json(gmf);
    let f = std::fs::File::create(path)?;
    serde_json::to_writer_pretty(f, &v).map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::types::{Hyperedge, InteractionType, NodeId, SaeFeature};
    use roaring::RoaringBitmap;

    #[test]
    fn hif_export_top_level_fields() {
        let gmf = GraphMemoryFabric::default();

        // Insert sample nodes
        for id in [1u32, 2, 3] {
            gmf.insert_node(SaeFeature {
                id: NodeId(id),
                activation: 0.0,
                timestamp_ns: 0,
                layer: None,
                label: Some(format!("feat-{}", id)),
            });
        }

        // Insert a hyperedge 1,2 -> 3
        let mut srcs = RoaringBitmap::new();
        srcs.insert(1);
        srcs.insert(2);
        gmf.insert_hyperedge(Hyperedge {
            id: Some(Uuid::new_v4()),
            sources: srcs,
            target: NodeId(3),
            interaction_type: InteractionType::Synergistic,
            stii_weight: 0.1,
        });

        let v = export_hif_json(&gmf);
        assert_eq!(v["network-type"], "hypergraph");
        assert!(v["nodes"].is_array());
        assert!(v["hyperedges"].is_array());
        assert_eq!(v["hyperedges"][0]["head"], 3);
        // tails contain 1 and 2
        let tail = v["hyperedges"][0]["tail"].as_array().unwrap();
        let mut vals: Vec<u32> = tail.iter().map(|x| x.as_u64().unwrap() as u32).collect();
        vals.sort_unstable();
        assert_eq!(vals, vec![1, 2]);
    }
}