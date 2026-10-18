//! Local resume rules from src/lib/resume.ts and src/views/player/hooks/use-resume-autosave.ts.
//! The host owns persistence; this module never stores media URLs or credentials.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Target {
    pub id: String,
    pub season: Option<i32>,
    pub episode: Option<i32>,
    /// Preserve distinct addon video IDs when season/episode metadata is absent.
    pub video_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Entry {
    pub ms: f64,
    pub t: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Document {
    pub version: u32,
    pub entries: BTreeMap<String, Entry>,
}

#[derive(Debug, Serialize)]
pub struct Checkpoint {
    pub key: String,
    pub entry: Entry,
}

fn valid_id(value: &str) -> bool {
    !value.trim().is_empty() && value.len() <= 2048 && !value.chars().any(char::is_control)
}

pub fn key(target: &Target) -> Result<String, &'static str> {
    if !valid_id(&target.id) {
        return Err("invalid-resume-target");
    }
    if let (Some(season), Some(episode)) = (target.season, target.episode) {
        if season < 0 || episode < 1 {
            return Err("invalid-resume-target");
        }
        return Ok(format!("{}|s{season}e{episode}", target.id));
    }
    if let Some(video) = &target.video_id {
        if !valid_id(video) {
            return Err("invalid-resume-target");
        }
        if video != &target.id {
            return Ok(format!("{}|v:{video}", target.id));
        }
    }
    Ok(target.id.clone())
}

pub fn validate(document: &Document) -> Result<(), &'static str> {
    if document.version != 1 {
        return Err("unsupported-resume-version");
    }
    if document.entries.iter().any(|(key, entry)| {
        key.trim().is_empty()
            || key.len() > 4100
            || key.chars().any(char::is_control)
            || !entry.ms.is_finite()
            || entry.ms < 0.0
    }) {
        return Err("invalid-resume-store");
    }
    Ok(())
}

#[derive(Debug, Serialize)]
pub struct StartPlan {
    pub ms: f64,
    pub prompt: bool,
}

/// use-bridge-load: default automatic resume, optional prompt above 30 seconds,
/// and restart episodes whose metadata runtime places the saved point at 80%.
pub fn start_plan(
    position_ms: f64,
    duration_ms: f64,
    playback: bool,
    prompt: bool,
) -> Result<StartPlan, &'static str> {
    if !position_ms.is_finite()
        || position_ms < 0.0
        || !duration_ms.is_finite()
        || duration_ms < 0.0
    {
        return Err("invalid-resume-position");
    }
    let ms = if !playback
        || position_ms <= 5000.0
        || (duration_ms > 0.0 && position_ms / duration_ms >= 0.8)
    {
        0.0
    } else {
        position_ms
    };
    Ok(StartPlan {
        ms,
        prompt: prompt && ms > 30_000.0,
    })
}

/// Autosave excludes short provider stubs (<150s) and positions below 5s.
/// Explicit exit follows use-player-exit's positive-position rule instead.
pub fn checkpoint(
    target: &Target,
    position_ms: f64,
    duration_ms: f64,
    timestamp_ms: u64,
    exiting: bool,
) -> Result<Option<Checkpoint>, &'static str> {
    let key = key(target)?;
    if !position_ms.is_finite()
        || position_ms < 0.0
        || !duration_ms.is_finite()
        || duration_ms < 0.0
    {
        return Err("invalid-resume-position");
    }
    if target.id.starts_with("iptv:")
        || position_ms == 0.0
        || (!exiting && (position_ms < 5000.0 || (duration_ms > 0.0 && duration_ms < 150_000.0)))
    {
        return Ok(None);
    }
    Ok(Some(Checkpoint {
        key,
        entry: Entry {
            ms: position_ms,
            t: timestamp_ms,
        },
    }))
}
