use std::env;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Profile {
    Openai,
    Anthropic,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SampleStrategy {
    DeterministicCombos,
    MonteCarlo,
    QmcSobol,
}

#[derive(Clone, Debug)]
pub struct GseConfig {
    pub window_size: usize,
    pub island_max_size: usize,
    pub island_dedup_recent_n: usize,
    pub drop_on_full: bool, // If true, try_send and drop on full (OPENAI); else await (Anthropic)
}

#[derive(Clone, Debug)]
pub struct PtaConfig {
    pub stii_threshold: f32,
    pub max_k: u8,
    pub max_subsets: usize,
    pub sample_strategy: SampleStrategy,
    pub sample_count: usize,
    pub ci_target_width: f32, // absolute half-width for CI (Anthropic)
    pub ci_confidence: f32,   // e.g., 0.95 (Anthropic)
    pub early_stop: bool,
    pub replicates_per_subset: u8,
    pub max_parallelism: usize,
}

#[derive(Clone, Debug)]
pub struct FsmConfig {
    pub frequency_threshold: u64,
    pub shard_count: usize,
    pub local_batch_size: usize,
    pub merge_interval: usize,
}

#[derive(Clone, Debug)]
pub struct ChannelsConfig {
    pub activations_capacity: usize,
    pub candidates_capacity: usize,
}

#[derive(Clone, Debug)]
pub struct Config {
    pub profile: Profile,
    pub gse: GseConfig,
    pub pta: PtaConfig,
    pub fsm: FsmConfig,
    pub channels: ChannelsConfig,
}

impl Config {
    pub fn openai_defaults() -> Self {
        let cores = num_cpus::get();
        Self {
            profile: Profile::Openai,
            gse: GseConfig {
                window_size: 128,
                island_max_size: 6,
                island_dedup_recent_n: 3,
                drop_on_full: true,
            },
            pta: PtaConfig {
                stii_threshold: 0.05,
                max_k: 3,
                max_subsets: 50_000,
                sample_strategy: SampleStrategy::MonteCarlo,
                sample_count: 20_000,
                ci_target_width: 0.02,
                ci_confidence: 0.95,
                early_stop: false,
                replicates_per_subset: 1,
                max_parallelism: cores,
            },
            fsm: FsmConfig {
                frequency_threshold: 50,
                shard_count: 8,
                local_batch_size: 2048,
                merge_interval: 10_000,
            },
            channels: ChannelsConfig {
                activations_capacity: 16_384,
                candidates_capacity: 8_192,
            },
        }
    }

    pub fn anthropic_defaults() -> Self {
        let half = (num_cpus::get() / 2).max(1).min(8);
        Self {
            profile: Profile::Anthropic,
            gse: GseConfig {
                window_size: 256,
                island_max_size: 10,
                island_dedup_recent_n: 5,
                drop_on_full: false,
            },
            pta: PtaConfig {
                stii_threshold: 0.05,
                max_k: 4,
                max_subsets: 200_000,
                sample_strategy: SampleStrategy::QmcSobol,
                sample_count: 100_000,
                ci_target_width: 0.01,
                ci_confidence: 0.95,
                early_stop: true,
                replicates_per_subset: 1,
                max_parallelism: half,
            },
            fsm: FsmConfig {
                frequency_threshold: 10,
                shard_count: 1,
                local_batch_size: 128,
                merge_interval: 1_000,
            },
            channels: ChannelsConfig {
                activations_capacity: 1_024,
                candidates_capacity: 512,
            },
        }
    }

    /// Apply common environment overrides. Missing or malformed vars are ignored.
    /// Supported (examples):
    /// - NSICP_STII_THRESHOLD=f32
    /// - NSICP_MAX_K=u8
    /// - NSICP_PTA_SAMPLE_COUNT=usize
    /// - NSICP_ACT_CAP=usize
    /// - NSICP_CAND_CAP=usize
    pub fn apply_env_overrides(&mut self) {
        if let Ok(s) = env::var("NSICP_STII_THRESHOLD") {
            if let Ok(v) = s.parse::<f32>() {
                self.pta.stii_threshold = v;
            }
        }
        if let Ok(s) = env::var("NSICP_MAX_K") {
            if let Ok(v) = s.parse::<u8>() {
                self.pta.max_k = v;
            }
        }
        if let Ok(s) = env::var("NSICP_PTA_SAMPLE_COUNT") {
            if let Ok(v) = s.parse::<usize>() {
                self.pta.sample_count = v;
            }
        }
        if let Ok(s) = env::var("NSICP_ACT_CAP") {
            if let Ok(v) = s.parse::<usize>() {
                self.channels.activations_capacity = v;
            }
        }
        if let Ok(s) = env::var("NSICP_CAND_CAP") {
            if let Ok(v) = s.parse::<usize>() {
                self.channels.candidates_capacity = v;
            }
        }
    }
}

/// Choose a profile based on CLI, env, then compile-time features.
/// - CLI flag: --profile openai|anthropic (searches args)
/// - Env var:  NSICP_PROFILE=openai|anthropic
/// - Features: cfg(feature="openai") / cfg(feature="anthropic")
/// - Default:  Anthropic
pub fn choose_profile_from_args_env(args: impl IntoIterator<Item = String>) -> Profile {
    // CLI flag has highest precedence
    let mut arg_profile: Option<Profile> = None;
    let mut it = args.into_iter().peekable();
    while let Some(a) = it.next() {
        if a == "--profile" {
            if let Some(val) = it.next() {
                arg_profile = parse_profile_str(&val);
                break;
            }
        } else if a.starts_with("--profile=") {
            let val = a.splitn(2, '=').nth(1).unwrap_or_default().to_string();
            arg_profile = parse_profile_str(&val);
            break;
        }
    }
    if let Some(p) = arg_profile {
        return p;
    }

    // Env var
    if let Ok(s) = env::var("NSICP_PROFILE") {
        if let Some(p) = parse_profile_str(&s) {
            return p;
        }
    }

    // Compile-time features
    #[cfg(feature = "openai")]
    {
        return Profile::Openai;
    }
    #[cfg(feature = "anthropic")]
    {
        return Profile::Anthropic;
    }

    // Default
    Profile::Anthropic
}

fn parse_profile_str(s: &str) -> Option<Profile> {
    match s.to_ascii_lowercase().as_str() {
        "openai" => Some(Profile::Openai),
        "anthropic" => Some(Profile::Anthropic),
        _ => None,
    }
}