use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MusicTrack {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    explicit: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    media_kind: Option<String>,
    id: String,
    connector_id: Option<String>,
    source_id: Option<String>,
    playback_url: Option<String>,
    title: String,
    artist: String,
    album: Option<String>,
    artwork: String,
    duration_seconds: u64,
    duration_label: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MusicStream {
    url: String,
    mime_type: String,
    bitrate: u64,
    #[serde(default, skip_serializing_if = "std::collections::BTreeMap::is_empty")]
    http_headers: std::collections::BTreeMap<String, String>,
}

fn duration_label(seconds: u64) -> String {
    format!("{}:{:02}", seconds / 60, seconds % 60)
}
