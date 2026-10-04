use harbor_core::{addons, resume, ScoreOptions, Stream, TrustOptions};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "camelCase")]
enum Request {
    NormalizeAddon {
        url: String,
    },
    InstallAddon {
        url: String,
        manifest: addons::Manifest,
    },
    Catalogs {
        addons: Vec<addons::Addon>,
        search: Option<String>,
        genre: Option<String>,
        #[serde(default)]
        skip: u32,
    },
    Resources {
        addons: Vec<addons::Addon>,
        resource: String,
        kind: String,
        id: String,
    },
    MapStreams {
        plan: addons::RequestPlan,
        response: Value,
    },
    Rank {
        streams: Vec<Stream>,
        #[serde(default)]
        trust: TrustOptions,
        #[serde(default)]
        score: ScoreOptions,
    },
    ResolveDirect {
        stream: Stream,
    },
    ResumePosition {
        target: resume::Target,
        document: resume::Document,
        #[serde(rename = "durationMs")]
        duration_ms: f64,
        playback: bool,
        prompt: bool,
    },
    ValidateResume {
        document: resume::Document,
    },
    ResumeCheckpoint {
        target: resume::Target,
        #[serde(rename = "positionMs")]
        position_ms: f64,
        #[serde(rename = "durationMs")]
        duration_ms: f64,
        #[serde(rename = "timestampMs")]
        timestamp_ms: u64,
        exiting: bool,
    },
}

pub fn dispatch(bytes: &[u8]) -> Result<Value, &'static str> {
    let request: Request = serde_json::from_slice(bytes).map_err(|_| "invalid-request")?;
    match request {
        Request::NormalizeAddon { url } => {
            Ok(json!({ "url": addons::normalize_manifest_url(&url)? }))
        }
        Request::InstallAddon { url, manifest } => {
            if manifest.id.trim().is_empty() || manifest.name.trim().is_empty() {
                return Err("invalid-manifest");
            }
            Ok(json!(addons::Addon {
                manifest,
                transport_url: addons::normalize_manifest_url(&url)?,
                enabled: true
            }))
        }
        Request::Catalogs {
            addons,
            search,
            genre,
            skip,
        } => Ok(json!(addons::catalog_plans(
            &addons,
            search.as_deref(),
            genre.as_deref(),
            skip
        )?)),
        Request::Resources {
            addons,
            resource,
            kind,
            id,
        } => Ok(json!(addons::resource_plans(
            &addons, &resource, &kind, &id
        )?)),
        Request::MapStreams { plan, response } => Ok(json!(addons::map_streams(&plan, response)?)),
        Request::Rank {
            streams,
            trust,
            score,
        } => Ok(json!(harbor_core::run_pipeline(streams, &trust, &score))),
        Request::ResolveDirect { stream } => resolve_direct(stream),
        Request::ResumePosition {
            target,
            document,
            duration_ms,
            playback,
            prompt,
        } => {
            resume::validate(&document)?;
            let key = resume::key(&target)?;
            let ms = document.entries.get(&key).map_or(0.0, |entry| entry.ms);
            Ok(json!(resume::start_plan(
                ms,
                duration_ms,
                playback,
                prompt
            )?))
        }
        Request::ValidateResume { document } => {
            resume::validate(&document)?;
            Ok(json!(document))
        }
        Request::ResumeCheckpoint {
            target,
            position_ms,
            duration_ms,
            timestamp_ms,
            exiting,
        } => Ok(
            json!({"checkpoint": resume::checkpoint(&target, position_ms, duration_ms, timestamp_ms, exiting)?}),
        ),
    }
}

fn resolve_direct(stream: Stream) -> Result<Value, &'static str> {
    let Some(url) = stream.url.as_deref() else {
        return Err(if stream.info_hash.is_some() {
            "torrent-resolver-pending"
        } else if stream.yt_id.is_some() {
            "youtube-resolver-pending"
        } else if stream.external_url.is_some() {
            "external-url-only"
        } else if stream.extra.contains_key("nzbUrl") {
            "nzb-resolver-pending"
        } else {
            "no-source"
        });
    };
    if url == "#" {
        return Err("addon-not-configured");
    }
    // URL parsers can discard controls; CString would truncate at NUL. Preserve
    // valid URLs exactly, and reject ambiguous input before entering libmpv.
    if url.chars().any(char::is_control) {
        return Err("invalid-playback-url");
    }
    let parsed = url::Url::parse(url).map_err(|_| "invalid-playback-url")?;
    if !matches!(parsed.scheme(), "https" | "http") {
        return Err("invalid-playback-url");
    }
    if stream.subtitles.as_ref().is_some_and(|subtitles| {
        subtitles
            .iter()
            .any(|subtitle| subtitle.url.chars().any(char::is_control))
    }) {
        return Err("invalid-subtitle-url");
    }
    let value = serde_json::to_value(&stream).map_err(|_| "invalid-stream")?;
    let hints = &value["behaviorHints"];
    let headers = hints["proxyHeaders"]["request"]
        .as_object()
        .or_else(|| hints["headers"].as_object());
    if let Some(headers) = headers {
        for (name, value) in headers {
            let Some(value) = value.as_str() else {
                return Err("invalid-playback-header");
            };
            if name.is_empty()
                || name
                    .bytes()
                    .any(|b| !b.is_ascii_alphanumeric() && !b"!#$%&'*+-.^_`|~".contains(&b))
                || value.contains(['\r', '\n', '\0'])
            {
                return Err("invalid-playback-header");
            }
        }
    }
    Ok(
        json!({ "url": url, "headers": headers, "subtitles": value.get("subtitles").unwrap_or(&Value::Null), "via":"direct" }),
    )
}
