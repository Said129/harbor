//! Pure local music identity/tag grouping extracted from the public beta's
//! music.rs and music/connectors/local/tags.rs. Native hosts own files/decoding.
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const AUDIO_EXTENSIONS: [&str; 8] = ["flac", "mp3", "m4a", "aac", "ogg", "opus", "wav", "wv"];

/// Original Desktop playlist name rules, with a transport NUL guard.
pub fn playlist_name(name: &str) -> Result<String, &'static str> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 100 || name.contains('\0') {
        return Err("music-playlist-name");
    }
    Ok(name.to_string())
}

/// Original Desktop index arithmetic; the native host owns persistence.
pub fn playlist_order(
    mut ids: Vec<String>,
    track_id: &str,
    to_index: usize,
) -> Result<Vec<String>, &'static str> {
    if ids.len() > 500
        || ids
            .iter()
            .any(|id| id.is_empty() || id.len() > 256 || id.contains('\0'))
        || ids.iter().collect::<std::collections::HashSet<_>>().len() != ids.len()
    {
        return Err("music-playlist-order");
    }
    let Some(from) = ids.iter().position(|id| id == track_id) else {
        return Ok(ids);
    };
    let track = ids.remove(from);
    let to = to_index.min(ids.len());
    ids.insert(to, track);
    Ok(ids)
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MusicTrack {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub explicit: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub media_kind: Option<String>,
    pub id: String,
    pub connector_id: Option<String>,
    pub source_id: Option<String>,
    pub playback_url: Option<String>,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub artwork: String,
    pub duration_seconds: u64,
    pub duration_label: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalTags {
    pub source_id: String,
    pub filename: String,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub track_no: Option<u32>,
    pub disc_no: Option<u32>,
    pub year: Option<u32>,
    pub duration_seconds: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalTrack {
    pub track: MusicTrack,
    pub album_key: Option<String>,
    pub artist_key: String,
    pub album_artist: Option<String>,
    pub track_no: Option<u32>,
    pub disc_no: Option<u32>,
    pub year: Option<u32>,
}

fn hash(value: &str) -> u64 {
    value
        .as_bytes()
        .iter()
        .fold(0xcbf29ce484222325, |hash, byte| {
            (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
        })
}

pub fn track_id(location: &str) -> String {
    format!("local:{:016x}", hash(location))
}

pub fn stable_key(value: &str) -> String {
    format!("{:016x}", hash(&value.to_lowercase()))
}

pub fn duration_label(seconds: u64) -> String {
    format!("{}:{:02}", seconds / 60, seconds % 60)
}

fn clean(value: Option<String>) -> Option<String> {
    value
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

/// Accept a relative content-addressed filename, never a host path or URL.
/// Identical owned file contents retain their identity across iOS containers.
pub fn local_track(input: LocalTags) -> Result<LocalTrack, &'static str> {
    let invalid = || "invalid-music-tags";
    let (stem, extension) = input.source_id.rsplit_once('.').ok_or_else(invalid)?;
    if stem.len() != 64
        || !stem
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
        || !AUDIO_EXTENSIONS.contains(&extension)
        || input.filename.is_empty()
        || input.filename.len() > 1_024
        || input.filename.contains(['/', '\\', '\0'])
        || input.duration_seconds > 31_536_000
        || [
            &input.title,
            &input.artist,
            &input.album,
            &input.album_artist,
        ]
        .iter()
        .any(|value| {
            value
                .as_ref()
                .is_some_and(|text| text.len() > 4_096 || text.contains('\0'))
        })
    {
        return Err(invalid());
    }
    let title = clean(input.title).unwrap_or_else(|| {
        Path::new(&input.filename)
            .file_stem()
            .and_then(|value| value.to_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("Untitled track")
            .to_owned()
    });
    let artist = clean(input.artist).unwrap_or_else(|| "Unknown artist".to_owned());
    let album = clean(input.album);
    let album_artist = clean(input.album_artist);
    let credited = album_artist.as_deref().unwrap_or(&artist);
    let album_key = album
        .as_deref()
        .map(|album| stable_key(&format!("{credited}::{album}")));
    let artist_key = stable_key(credited);
    Ok(LocalTrack {
        track: MusicTrack {
            explicit: None,
            version: None,
            media_kind: None,
            id: track_id(&input.source_id),
            connector_id: Some("local".to_owned()),
            source_id: Some(input.source_id),
            playback_url: None,
            title,
            artist,
            album,
            artwork: String::new(),
            duration_seconds: input.duration_seconds,
            duration_label: duration_label(input.duration_seconds),
        },
        album_key,
        artist_key,
        album_artist,
        track_no: input.track_no,
        disc_no: input.disc_no,
        year: input.year,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_original_grouping_and_rejects_host_paths() {
        let input = LocalTags {
            source_id: format!("{}.flac", "a".repeat(64)),
            filename: "  Night song.flac".to_owned(),
            title: None,
            artist: Some(" Guest ".to_owned()),
            album: Some(" Night ".to_owned()),
            album_artist: Some(" Ensemble ".to_owned()),
            track_no: Some(2),
            disc_no: Some(1),
            year: Some(2026),
            duration_seconds: 125,
        };
        let result = local_track(input.clone()).unwrap();
        assert_eq!(result.track.title, "Night song");
        assert_eq!(result.track.artist, "Guest");
        assert_eq!(result.track.duration_label, "2:05");
        assert_eq!(result.album_key, Some(stable_key("Ensemble::Night")));
        assert_eq!(result.artist_key, stable_key("ensemble"));
        assert_eq!(result.track.playback_url, None);
        let mut different_credit = input.clone();
        different_credit.album_artist = Some("Other ensemble".to_owned());
        assert_ne!(
            result.album_key,
            local_track(different_credit).unwrap().album_key
        );
        for path in [
            "../track.flac",
            "file:///private/track.flac",
            "https://private.example/track.mp3",
        ] {
            let mut bad = input.clone();
            bad.source_id = path.to_owned();
            assert_eq!(local_track(bad).unwrap_err(), "invalid-music-tags");
        }
        assert_eq!(playlist_name("  Late night  "), Ok("Late night".to_owned()));
        assert!(playlist_name(" ").is_err());
        assert!(playlist_name(&"界".repeat(101)).is_err());
        let ids = || ["a", "b", "c", "d"].map(str::to_owned).to_vec();
        assert_eq!(playlist_order(ids(), "a", 2).unwrap(), ["b", "c", "a", "d"]);
        assert_eq!(playlist_order(ids(), "d", 0).unwrap(), ["d", "a", "b", "c"]);
        assert_eq!(
            playlist_order(ids(), "a", 99).unwrap(),
            ["b", "c", "d", "a"]
        );
        assert_eq!(playlist_order(ids(), "missing", 0).unwrap(), ids());
        assert!(playlist_order(vec!["a".into(), "a".into()], "a", 0).is_err());
    }
}
