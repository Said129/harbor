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
    run_pipeline_full(streams, trust_opts, score_opts, debrid, &AnimeOptions::default())
}

/// Desktop's anime inputs to the pipeline. `absolute_episode` comes from a `kitsu:ID:EP` or
/// `mal:ID:EP` id; `aliases` are the other episode numbers the request accepts.
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnimeOptions {
    #[serde(default)]
    pub absolute_episode: Option<i64>,
    #[serde(default)]
    pub aliases: Vec<i64>,
}

/// Key under which the native host adds the filename fields of a raw stream (Desktop's
/// `enhanceAnimeStreams` output). It is removed before parsing so it never reaches the ranked output.
const ANIME_FIELDS_KEY: &str = "harborAnimeFields";

const GIB_BYTES: u64 = 1024 * 1024 * 1024;

/// Desktop's runPipeline order: parse (with anime filename fields), exact-episode filter, debrid
/// flags, trust, corroborated early-leak rescue, score and rank.
pub fn run_pipeline_full(
    streams: Vec<Stream>,
    trust_opts: &TrustOptions,
    score_opts: &ScoreOptions,
    debrid: &DebridFlags,
    anime: &AnimeOptions,
) -> PipelineResult {
    let enrich = anime.absolute_episode.is_some();
    let parsed: Vec<ParsedStream> = streams
        .into_iter()
        .map(|stream| parse_with_anime_fields(stream, enrich))
        .collect();
    let (mut parsed, anime_dropped) = exact_episode_filter(parsed, anime, trust_opts);
    apply_debrid_flags(&mut parsed, debrid);
    let trusted = trust::apply_trust(parsed, trust_opts);
    let mut keep = trusted.keep;
    let mut rejected: Vec<Rejection> = Vec::new();
    let rescued = rescued_leak_indices(
        &trusted.rejected,
        trust_opts.release_date.as_deref(),
        trust::now_unix_ms(),
    );
    for (index, entry) in trusted.rejected.into_iter().enumerate() {
        if rescued.contains(&index) {
            keep.push(entry.stream);
        } else {
            rejected.push(entry);
        }
    }
    rejected.extend(anime_dropped);
    let corpus = scoring::compute_corpus_stats(&keep, score_opts);
    let scored = keep
        .into_iter()
        .map(|s| scoring::score_stream(s, score_opts, &corpus))
        .collect();
    PipelineResult {
        picker: scoring::rank_and_pick(
            scored,
            &score_opts.active_debrids,
            score_opts.respect_addon_order,
        ),
        rejected,
    }
}

fn parse_with_anime_fields(mut stream: Stream, enrich: bool) -> ParsedStream {
    let fields = stream.extra.remove(ANIME_FIELDS_KEY);
    let mut parsed = parser::parse_stream(stream);
    let fields = if enrich { fields } else { None };
    if let Some(fields) = fields {
        apply_anime_fields(&mut parsed, &fields);
    }
    parsed
}

fn text_field<'a>(fields: &'a serde_json::Value, key: &str) -> Option<&'a str> {
    fields.get(key).and_then(|value| value.as_str()).filter(|text| !text.is_empty())
}

fn int_field(fields: &serde_json::Value, key: &str) -> Option<i64> {
    fields.get(key).and_then(|value| value.as_i64())
}

/// Desktop's enhanceAnimeStreams: each filename field that was recognised replaces the parsed value.
fn apply_anime_fields(parsed: &mut ParsedStream, fields: &serde_json::Value) {
    if let Some(title) = text_field(fields, "animeTitle") {
        parsed.parsed_title = title.to_string();
    }
    if let Some(episode) = int_field(fields, "episodeNumber").and_then(|n| i32::try_from(n).ok()) {
        parsed.episode = Some(episode);
    }
    if let Some(title) = text_field(fields, "episodeTitle") {
        parsed.episode_title = Some(title.to_string());
    }
    if let Some(season) = int_field(fields, "season").and_then(|n| i32::try_from(n).ok()) {
        parsed.season = Some(season);
    }
    if let Some(year) = int_field(fields, "year").and_then(|n| u16::try_from(n).ok()) {
        parsed.year = Some(year);
    }
    if let Some(group) = text_field(fields, "releaseGroup") {
        parsed.release_group = Some(group.to_string());
        let normalized: String = group
            .to_uppercase()
            .chars()
            .filter(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
            .collect();
        parsed.release_group_normalized = Some(normalized);
    }
    let resolution = fields
        .get("resolution")
        .and_then(|value| serde_json::from_value::<Resolution>(value.clone()).ok());
    if let Some(resolution) = resolution {
        parsed.resolution = resolution;
    }
    if let Some(hash) = text_field(fields, "fileChecksum") {
        parsed.anime_hash = Some(hash.to_string());
    }
    if matches!(fields.get("isBatch").and_then(|value| value.as_bool()), Some(true)) {
        parsed.season_pack = true;
    }
}

/// Desktop's applyAnimeEpisodeFilter and partitionByExactAnimeEpisode. A stream with a concrete episode
/// that is neither the expected absolute episode nor an alias is dropped; packs and episode-less streams
/// pass. Skipped when trust filtering is off, as on Desktop.
fn exact_episode_filter(
    parsed: Vec<ParsedStream>,
    anime: &AnimeOptions,
    trust_opts: &TrustOptions,
) -> (Vec<ParsedStream>, Vec<Rejection>) {
    let Some(expected) = anime.absolute_episode else {
        return (parsed, Vec::new());
    };
    if trust_opts.disabled {
        return (parsed, Vec::new());
    }
    let mut keep = Vec::with_capacity(parsed.len());
    let mut dropped = Vec::new();
    for stream in parsed {
        let concrete: Option<i32> = if stream.season_pack { None } else { stream.episode };
        let Some(episode) = concrete.map(i64::from) else {
            keep.push(stream);
            continue;
        };
        let accepted = episode == expected
            || anime.aliases.iter().any(|alias| *alias >= 1 && *alias == episode);
        if accepted {
            keep.push(stream);
        } else {
            let reason = format!("anime-episode-mismatch:{episode}-vs-{expected}");
            dropped.push(Rejection { stream, reason });
        }
    }
    (keep, dropped)
}

/// Desktop's rescueCorroboratedLeaks. Recent high-resolution rejections (fresh-cinema-fake or
/// new-release-stub) that corroborate one another are restored: three or more in one quarter-GiB size
/// bucket of the same resolution, or two different release groups. Returns the indices to restore.
pub(crate) fn rescued_leak_indices(
    rejected: &[Rejection],
    release_date: Option<&str>,
    now_ms: i64,
) -> Vec<usize> {
    let Some(released) = release_date.and_then(trust::parse_iso_date_to_unix_ms) else {
        return Vec::new();
    };
    let days = (now_ms - released) as f64 / 86_400_000.0;
    let inside_window = days > -90.0 && days < 60.0;
    if !inside_window {
        return Vec::new();
    }
    let mut clusters: std::collections::BTreeMap<(u8, i64), Vec<(usize, Option<&str>)>> =
        std::collections::BTreeMap::new();
    for (index, entry) in rejected.iter().enumerate() {
        let reason = entry.reason.as_str();
        if !(reason.starts_with("fresh-cinema-fake") || reason.starts_with("new-release-stub")) {
            continue;
        }
        let stream = &entry.stream;
        let (kind, min_size): (u8, u64) = match stream.resolution {
            Resolution::UHD => (0, GIB_BYTES / 2 * 5),
            Resolution::P1080 => (1, GIB_BYTES),
            _ => continue,
        };
        let Some(size) = stream.size else {
            continue;
        };
        if size < min_size {
            continue;
        }
        let bucket = ((size as f64 / GIB_BYTES as f64) * 4.0).round() as i64;
        let group = stream.release_group_normalized.as_deref().filter(|g| !g.is_empty());
        clusters.entry((kind, bucket)).or_default().push((index, group));
    }
    let mut rescued = Vec::new();
    for members in clusters.values() {
        let groups: std::collections::BTreeSet<&str> =
            members.iter().filter_map(|(_, group)| *group).collect();
        if members.len() >= 3 || groups.len() >= 2 {
            rescued.extend(members.iter().map(|(index, _)| *index));
        }
    }
    rescued
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

    fn raw_stream(title: &str, extra: serde_json::Value) -> Stream {
        let mut value = serde_json::json!({
            "addonId": "addon",
            "addonName": "Addon",
            "url": "https://example.com/video.mkv",
            "title": title
        });
        if let (Some(base), Some(more)) = (value.as_object_mut(), extra.as_object()) {
            for (key, item) in more {
                base.insert(key.clone(), item.clone());
            }
        }
        serde_json::from_value(value).expect("valid test stream")
    }

    fn leak(size: u64, group: Option<&str>, reason: &str) -> Rejection {
        let parsed = ParsedStream {
            stream: raw_stream("leak", serde_json::json!({})),
            resolution: Resolution::P1080,
            size: Some(size),
            release_group_normalized: group.map(str::to_string),
            ..Default::default()
        };
        Rejection {
            stream: parsed,
            reason: reason.to_string(),
        }
    }

    #[test]
    fn anime_fields_replace_parsed_values_and_never_leak_the_key() {
        let fields = serde_json::json!({
            "harborAnimeFields": {"episodeNumber": 12, "releaseGroup": "Sub-Pls", "resolution": "4K", "isBatch": false}
        });
        let parsed = parse_with_anime_fields(raw_stream("Show - 05 [1080p].mkv", fields), true);
        assert_eq!(parsed.episode, Some(12));
        assert_eq!(parsed.release_group_normalized.as_deref(), Some("SUBPLS"));
        assert_eq!(parsed.resolution, Resolution::UHD);
        assert!(!parsed.stream.extra.contains_key("harborAnimeFields"));
    }

    #[test]
    fn anime_fields_are_dropped_without_an_absolute_episode() {
        let fields = serde_json::json!({"harborAnimeFields": {"episodeNumber": 12}});
        let parsed = parse_with_anime_fields(raw_stream("Show", fields), false);
        assert_ne!(parsed.episode, Some(12));
        assert!(!parsed.stream.extra.contains_key("harborAnimeFields"));
    }

    #[test]
    fn exact_episode_filter_drops_other_episodes_and_accepts_aliases() {
        let anime = AnimeOptions {
            absolute_episode: Some(12),
            aliases: vec![5],
        };
        let streams = vec![
            raw_stream("a", serde_json::json!({"harborAnimeFields": {"episodeNumber": 11}})),
            raw_stream("b", serde_json::json!({"harborAnimeFields": {"episodeNumber": 5}})),
            raw_stream("c", serde_json::json!({"harborAnimeFields": {"episodeNumber": 12}})),
        ];
        let result = run_pipeline_full(
            streams,
            &TrustOptions::default(),
            &ScoreOptions::default(),
            &DebridFlags::default(),
            &anime,
        );
        assert!(result
            .rejected
            .iter()
            .any(|r| r.reason == "anime-episode-mismatch:11-vs-12"));
        assert!(!result
            .rejected
            .iter()
            .any(|r| r.reason == "anime-episode-mismatch:5-vs-12"));
    }

    #[test]
    fn corroborated_fresh_cinema_leaks_are_rescued_inside_the_window() {
        let now = crate::trust::parse_iso_date_to_unix_ms("2026-11-10").expect("date");
        let size = GIB_BYTES + GIB_BYTES / 2;
        let rejected = vec![
            leak(size, Some("AAA"), "fresh-cinema-fake-web"),
            leak(size, Some("AAA"), "new-release-stub-900mb"),
            leak(size, None, "fresh-cinema-fake-hdtv"),
            leak(size, Some("BBB"), "addon-status-card"),
        ];
        assert_eq!(rescued_leak_indices(&rejected, Some("2026-11-01"), now), vec![0, 1, 2]);
        assert!(rescued_leak_indices(&rejected, Some("2026-01-01"), now).is_empty());
        assert!(rescued_leak_indices(&rejected, None, now).is_empty());
    }

    #[test]
    fn two_release_groups_corroborate_a_leak_cluster() {
        let now = crate::trust::parse_iso_date_to_unix_ms("2026-11-10").expect("date");
        let size = GIB_BYTES + GIB_BYTES / 2;
        let pair = vec![
            leak(size, Some("AAA"), "fresh-cinema-fake-web"),
            leak(size, Some("BBB"), "fresh-cinema-fake-web"),
        ];
        assert_eq!(rescued_leak_indices(&pair, Some("2026-11-01"), now), vec![0, 1]);
        let single = vec![leak(size, Some("AAA"), "fresh-cinema-fake-web")];
        assert!(rescued_leak_indices(&single, Some("2026-11-01"), now).is_empty());
    }
}