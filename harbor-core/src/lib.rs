//! Shared Harbor stream engine. WASM exports remain enabled by default.
pub mod account;
pub mod addons;
pub mod music;
pub mod parser;
pub mod resume;
pub mod scoring;
pub mod trust;
mod types;
pub use types::*;

#[cfg(feature = "wasm")]
mod wasm;
#[cfg(feature = "wasm")]
pub use wasm::*;

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PipelineResult {
    pub picker: RankedPicker,
    pub rejected: Vec<Rejection>,
}

/// The native and WASM consumers share the exact parser/trust/scoring stages.
pub fn run_pipeline(
    streams: Vec<Stream>,
    trust_opts: &TrustOptions,
    score_opts: &ScoreOptions,
) -> PipelineResult {
    let parsed = streams.into_iter().map(parser::parse_stream).collect();
    let trusted = trust::apply_trust(parsed, trust_opts);
    let corpus = scoring::compute_corpus_stats(&trusted.keep, score_opts);
    let scored = trusted
        .keep
        .into_iter()
        .map(|s| scoring::score_stream(s, score_opts, &corpus))
        .collect();
    PipelineResult {
        picker: scoring::rank_and_pick(
            scored,
            &score_opts.active_debrids,
            score_opts.respect_addon_order,
        ),
        rejected: trusted.rejected,
    }
}
