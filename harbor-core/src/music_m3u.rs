//! Pure M3U grammar from Harbor Desktop 0.9.132, commit 0834340cec5531650bfe78cd628628702e636987.
//! Native hosts own file selection, security-scoped access and transactions.
use crate::music::{duration_label, MusicTrack};
use std::path::{Path, PathBuf};

pub const MAX_M3U_BYTES: usize = 5 * 1024 * 1024;
const MAX_M3U_TRACKS: usize = 5_000;

pub fn parse_bytes(content: &[u8], base: &Path) -> Result<Vec<MusicTrack>, String> {
    if content.len() > MAX_M3U_BYTES {
        return Err("M3U file is larger than 5 MB".to_string());
    }
    parse(&String::from_utf8_lossy(content), base)
}

#[derive(Default)]
struct EntryMetadata {
    duration_seconds: u64,
    artist: Option<String>,
    title: Option<String>,
}

fn parse(content: &str, base: &Path) -> Result<Vec<MusicTrack>, String> {
    let mut tracks = Vec::new();
    let mut pending = EntryMetadata::default();
    for raw_line in content.lines() {
        let line = raw_line.trim().trim_start_matches('\u{feff}');
        if line.is_empty() {
            continue;
        }
        if let Some(value) = line.strip_prefix("#EXTINF:") {
            pending = parse_metadata(value);
            continue;
        }
        if line.starts_with('#') {
            continue;
        }
        if tracks.len() >= MAX_M3U_TRACKS {
            return Err("M3U file contains more than 5000 tracks".to_string());
        }
        let location = normalize_location(line, base)?;
        let title = pending
            .title
            .take()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| title_from_location(&location));
        let artist = pending
            .artist
            .take()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "Unknown artist".to_string());
        let duration_seconds = pending.duration_seconds;
        pending = EntryMetadata::default();
        let connector = if location.contains("://") {
            "direct"
        } else {
            "local"
        };
        tracks.push(MusicTrack {
            explicit: None,
            version: None,
            media_kind: None,
            id: format!("m3u:{:016x}", stable_hash(&location)),
            connector_id: Some(connector.to_string()),
            source_id: Some(location.clone()),
            playback_url: Some(location),
            title,
            artist,
            album: None,
            artwork: String::new(),
            duration_seconds,
            duration_label: duration_label(duration_seconds),
        });
    }
    Ok(tracks)
}

fn parse_metadata(value: &str) -> EntryMetadata {
    let (duration, label) = value.split_once(',').unwrap_or((value, ""));
    let duration_seconds = duration.trim().parse::<i64>().unwrap_or(0).max(0) as u64;
    let label = label.trim();
    let (artist, title) = label
        .split_once(" - ")
        .map(|(artist, title)| {
            (
                Some(artist.trim().to_string()),
                Some(title.trim().to_string()),
            )
        })
        .unwrap_or((None, (!label.is_empty()).then(|| label.to_string())));
    EntryMetadata {
        duration_seconds,
        artist,
        title,
    }
}

fn normalize_location(location: &str, base: &Path) -> Result<String, String> {
    if location.contains("://") {
        let parsed =
            url::Url::parse(location).map_err(|_| "M3U contains an invalid URL".to_string())?;
        if !matches!(parsed.scheme(), "http" | "https" | "file") {
            return Err(format!(
                "M3U URL scheme is not supported: {}",
                parsed.scheme()
            ));
        }
        return Ok(parsed.to_string());
    }
    let path = PathBuf::from(location);
    let path = if path.is_absolute() {
        path
    } else {
        base.join(path)
    };
    Ok(path.to_string_lossy().to_string())
}

fn title_from_location(location: &str) -> String {
    if let Ok(url) = url::Url::parse(location) {
        if let Some(segment) = url.path_segments().and_then(|segments| segments.last()) {
            let title = segment
                .rsplit_once('.')
                .map(|item| item.0)
                .unwrap_or(segment);
            if !title.is_empty() {
                return title.to_string();
            }
        }
    }
    Path::new(location)
        .file_stem()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .unwrap_or("Untitled track")
        .to_string()
}

fn stable_hash(value: &str) -> u64 {
    value
        .as_bytes()
        .iter()
        .fold(0xcbf29ce484222325, |hash, byte| {
            (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn imports_original_metadata_locations_and_stable_ids_without_fetching_audio() {
        let input = "\u{feff}#EXTM3U\r\n#EXTINF:125,Björk - Jóga\r\nalbum/01.flac\r\n#EXTINF:-1,Radio\nhttps://example.com/live?token=fixture\n";
        let tracks = parse_bytes(input.as_bytes(), Path::new("/owned/music")).unwrap();
        assert_eq!(tracks.len(), 2);
        assert_eq!(tracks[0].artist, "Björk");
        assert_eq!(tracks[0].title, "Jóga");
        assert_eq!(tracks[0].duration_seconds, 125);
        assert_eq!(
            tracks[0].source_id.as_deref(),
            Some("/owned/music/album/01.flac")
        );
        assert_eq!(tracks[0].connector_id.as_deref(), Some("local"));
        assert_eq!(tracks[1].connector_id.as_deref(), Some("direct"));
        assert_eq!(tracks[1].duration_seconds, 0);
        assert_eq!(
            tracks[0].id,
            parse_bytes(input.as_bytes(), Path::new("/owned/music")).unwrap()[0].id
        );
    }

    #[test]
    fn rejects_excess_members_bytes_and_non_media_schemes() {
        assert_eq!(
            parse_bytes("a.flac\n".repeat(5_000).as_bytes(), Path::new("/music"))
                .unwrap()
                .len(),
            5_000
        );
        assert!(parse_bytes("a.flac\n".repeat(5_001).as_bytes(), Path::new("/music")).is_err());
        assert!(parse_bytes(&vec![b' '; MAX_M3U_BYTES + 1], Path::new("/music")).is_err());
        assert!(parse_bytes(b"javascript://example.com/track", Path::new("/music")).is_err());
        assert!(parse_bytes(b"https://[", Path::new("/music")).is_err());
    }
}
