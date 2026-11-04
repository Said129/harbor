//! Shared Harbor stream engine. WASM exports remain enabled by default.
pub mod account;
pub mod addons;
pub mod music;
pub mod music_audio;
pub mod music_m3u;
pub mod music_matching;
pub mod parser;
pub mod resume;
pub mod scoring;
pub mod subtitle_moviehash;
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
    run_pipeline_with_debrid(streams, trust_opts, score_opts, &DebridFlags::default())
}

/// Desktop's applyDebridFlags: a hash that a provider confirmed as cached or as
/// part of its library is marked cached (and in library) on that provider, and
/// verified, before trust filtering and scoring.
pub fn apply_debrid_flags(parsed: &mut [ParsedStream], flags: &DebridFlags) {
    if flags.cached.is_empty() && flags.library.is_empty() {
        return;
    }
    let slugs: std::collections::BTreeSet<&String> =
        flags.cached.keys().chain(flags.library.keys()).collect();
    for stream in parsed.iter_mut() {
        let Some(hash) = stream.stream.info_hash.as_deref().map(str::to_lowercase) else {
            continue;
        };
        for slug in &slugs {
            let listed = |map: &std::collections::BTreeMap<String, Vec<String>>| {
                map.get(*slug)
                    .is_some_and(|hashes| hashes.iter().any(|value| value.eq_ignore_ascii_case(&hash)))
            };
            let in_library = listed(&flags.library);
            if !listed(&flags.cached) && !in_library {
                continue;
            }
            stream.cached.insert((*slug).clone(), true);
            if in_library {
                stream.in_library.insert((*slug).clone(), true);
            }
            stream.cache_verified.insert((*slug).clone(), true);
        }
    }
}

pub fn run_pipeline_with_debrid(
    streams: Vec<Stream>,
    trust_opts: &TrustOptions,
    score_opts: &ScoreOptions,
    debrid: &DebridFlags,
) -> PipelineResult {
    let mut parsed: Vec<ParsedStream> = streams.into_iter().map(parser::parse_stream).collect();
    apply_debrid_flags(&mut parsed, debrid);
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

#[cfg(test)]
mod tests {
    use super::*;

    fn hashed(hash: &str) -> ParsedStream {
        let mut parsed = ParsedStream::default();
        parsed.stream.info_hash = Some(hash.to_string());
        parsed
    }

    #[test]
    fn provider_confirmed_hashes_are_marked_cached_library_and_verified() {
        let mut streams = vec![hashed("AABBCC"), hashed("ddeeff"), ParsedStream::default()];
        let mut flags = DebridFlags::default();
        flags.cached.insert("rd".into(), vec!["aabbcc".into()]);
        flags.library.insert("tb".into(), vec!["DDEEFF".into()]);
        apply_debrid_flags(&mut streams, &flags);
        assert_eq!(streams[0].cached.get("rd"), Some(&true));
        assert_eq!(streams[0].cache_verified.get("rd"), Some(&true));
        assert!(streams[0].in_library.is_empty());
        assert!(!streams[0].cached.contains_key("tb"));
        assert_eq!(streams[1].cached.get("tb"), Some(&true));
        assert_eq!(streams[1].in_library.get("tb"), Some(&true));
        assert_eq!(streams[1].cache_verified.get("tb"), Some(&true));
        assert!(streams[2].cached.is_empty() && streams[2].cache_verified.is_empty());
    }

    #[test]
    fn no_flags_change_nothing_and_text_markers_are_not_verification() {
        let mut streams = vec![hashed("aabbcc")];
        streams[0].cached.insert("rd".into(), true);
        apply_debrid_flags(&mut streams, &DebridFlags::default());
        assert_eq!(streams[0].cached.get("rd"), Some(&true));
        assert!(streams[0].cache_verified.is_empty());
    }
}