use serde_json::Value;
use std::sync::LazyLock;
use std::time::Duration;

pub const API_VERSION: &str = "1.2.2";
pub const AGENT: &str = "Harbor/1.0";
pub const ACCOUNT_ORIGIN: &str = "https://clients.plex.tv";
pub const COVER_SIZE: u32 = 480;
pub const CIRCLE_SIZE: u32 = 320;

static CLIENT: LazyLock<Result<reqwest::Client, String>> = LazyLock::new(|| {
    reqwest::Client::builder()
        .user_agent(AGENT)
        .connect_timeout(Duration::from_secs(6))
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            let Some(first) = attempt.previous().first() else {
                return attempt.stop();
            };
            if attempt.previous().len() < 5 && first.origin() == attempt.url().origin() {
                attempt.follow()
            } else {
                attempt.stop()
            }
        }))
        .gzip(true)
        .build()
        .map_err(|error| error.to_string())
});

fn client() -> Result<&'static reqwest::Client, String> {
    CLIENT.as_ref().map_err(Clone::clone)
}

pub fn encode(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

pub fn normalized_origin(raw: &str) -> Result<String, String> {
    let parsed = url::Url::parse(raw.trim()).map_err(|_| invalid_origin())?;
    if !matches!(parsed.scheme(), "http" | "https")
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        return Err(invalid_origin());
    }
    let port = match parsed.port() {
        Some(port) => format!(":{port}"),
        None => String::new(),
    };
    Ok(format!(
        "{}://{}{port}",
        parsed.scheme(),
        parsed.host_str().unwrap_or_default()
    ))
}

fn invalid_origin() -> String {
    "Enter a Plex server address such as https://192-168-1-8.plex.direct:32400".to_string()
}

pub fn safe_path(path: &str) -> Result<String, String> {
    let path = path.trim();
    if !path.starts_with('/')
        || path.starts_with("//")
        || path.contains("..")
        || path.contains(['\\', ' ', '"'])
    {
        return Err("Plex returned an unusable resource path".to_string());
    }
    Ok(path.to_string())
}

pub fn safe_key(raw: &str) -> Result<String, String> {
    let key = raw.trim();
    if key.is_empty()
        || key.len() > 40
        || !key
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || character == '-')
    {
        return Err("Plex item id is invalid".to_string());
    }
    Ok(key.to_string())
}

pub async fn get_json(
    origin: &str,
    path: &str,
    client_id: &str,
    token: Option<&str>,
    timeout: Duration,
) -> Result<Value, String> {
    let bytes = get_bytes(origin, path, client_id, token, timeout, 8 * 1024 * 1024).await?;
    serde_json::from_slice(&bytes).map_err(|_| "Plex sent an unreadable response".into())
}
pub async fn get_bytes(
    origin: &str,
    path: &str,
    client_id: &str,
    token: Option<&str>,
    timeout: Duration,
    maximum: usize,
) -> Result<Vec<u8>, String> {
    safe_path(path)?;
    let request = client()?
        .get(format!("{origin}{path}"))
        .timeout(timeout)
        .header("Accept", "application/json")
        .header("X-Plex-Product", "Harbor")
        .header("X-Plex-Version", "1")
        .header("X-Plex-Platform", std::env::consts::OS)
        .header("X-Plex-Platform-Version", "1")
        .header("X-Plex-Device", "Harbor")
        .header("X-Plex-Device-Name", "Harbor iPhone and iPad")
        .header("X-Plex-Model", "standalone")
        .header("X-Plex-Pms-Api-Version", API_VERSION)
        .header("X-Plex-Client-Identifier", client_id);
    let request = match token {
        Some(token) => request.header("X-Plex-Token", token),
        None => request,
    };
    let mut response = request
        .send()
        .await
        .map_err(|error| format!("Plex request failed: {error}"))?;
    let status = response.status();
    if status == reqwest::StatusCode::UNAUTHORIZED || status == reqwest::StatusCode::FORBIDDEN {
        return Err("Plex rejected the stored access token".to_string());
    }
    if !status.is_success() {
        return Err(format!("Plex answered {}", status.as_u16()));
    }
    if response
        .content_length()
        .is_some_and(|value| value > maximum as u64)
    {
        return Err("Plex response too large".into());
    }
    let mut data = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| "Plex response failed".to_string())?
    {
        if data.len().saturating_add(chunk.len()) > maximum {
            return Err("Plex response too large".into());
        }
        data.extend_from_slice(&chunk);
    }
    Ok(data)
}

pub fn artwork_path(thumb: &str, size: u32) -> Result<String, String> {
    let path = safe_path(thumb)?;
    let mut parsed = url::Url::parse(&format!("http://owned.invalid{path}"))
        .map_err(|_| "Invalid Plex cover".to_string())?;
    let params: Vec<(String, String)> = parsed
        .query_pairs()
        .filter(|(key, _)| {
            !key.eq_ignore_ascii_case("x-plex-token") && !key.eq_ignore_ascii_case("token")
        })
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect();
    parsed.set_query(None);
    parsed.set_fragment(None);
    if !params.is_empty() {
        parsed.query_pairs_mut().extend_pairs(params);
    }
    let relative = &parsed[url::Position::BeforePath..];
    Ok(format!("/photo/:/transcode?url={}&width={size}&height={size}&minSize=1&upscale=1&format=jpg&quality=-1", encode(relative)))
}
pub fn authenticated_artwork_path(path: &str, token: &str) -> Result<String, String> {
    let path = safe_path(path)?;
    let mut url = url::Url::parse(&format!("http://owned.invalid{path}"))
        .map_err(|_| "Invalid Plex artwork".to_string())?;
    if url.path() != "/photo/:/transcode" {
        return Err("Invalid Plex artwork".into());
    }
    let params: Vec<(String, String)> = url
        .query_pairs()
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect();
    let thumb = params
        .iter()
        .find(|(key, _)| key == "url")
        .map(|(_, value)| value.as_str())
        .ok_or("Invalid Plex artwork")?;
    safe_path(thumb)?;
    if !["/library/", "/playlists/", "/resources/"]
        .iter()
        .any(|prefix| thumb.starts_with(prefix))
    {
        return Err("Invalid Plex artwork source".into());
    }
    let mut inner = url::Url::parse(&format!("http://owned.invalid{thumb}"))
        .map_err(|_| "Invalid Plex artwork source".to_string())?;
    inner.query_pairs_mut().append_pair("X-Plex-Token", token);
    url.set_query(None);
    url.query_pairs_mut()
        .append_pair("url", &inner[url::Position::BeforePath..])
        .extend_pairs(
            params
                .iter()
                .filter(|(key, _)| key != "url" && !key.eq_ignore_ascii_case("x-plex-token"))
                .map(|(key, value)| (key.as_str(), value.as_str())),
        )
        .append_pair("X-Plex-Token", token);
    Ok(url[url::Position::BeforePath..].to_string())
}
pub fn artwork_reference(client_id: &str, thumb: &str, size: u32) -> String {
    let Ok(path) = artwork_path(thumb, size) else {
        return String::new();
    };
    format!("harbor-music-art://plex/{client_id}?path={}", encode(&path))
}

pub fn direct_stream_url(origin: &str, token: &str, part: &str) -> Result<String, String> {
    let path = safe_path(part)?;
    Ok(format!("{origin}{path}?X-Plex-Token={}", encode(token)))
}

pub fn transcode_stream_url(
    origin: &str,
    token: &str,
    client_id: &str,
    key: &str,
    session_id: &str,
) -> String {
    format!(
        "{origin}/music/:/transcode/universal/start.mp3?path={}&mediaIndex=0&partIndex=0&protocol=http&offset=0&directPlay=0&directStream=1&musicBitrate=320&hasMDE=1&X-Plex-Client-Identifier={}&X-Plex-Session-Identifier={}&X-Plex-Token={}",
        encode(&format!("/library/metadata/{key}")),
        encode(client_id),
        encode(session_id),
        encode(token)
    )
}

pub fn mime_for(container: Option<&str>, codec: Option<&str>) -> String {
    let hint = container.or(codec).unwrap_or_default().to_ascii_lowercase();
    match hint.as_str() {
        "flac" => "audio/flac",
        "wav" => "audio/wav",
        "ogg" | "opus" | "vorbis" => "audio/ogg",
        "m4a" | "mp4" | "aac" | "alac" => "audio/mp4",
        "aiff" | "aif" => "audio/aiff",
        _ => "audio/mpeg",
    }
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origins_drop_paths_and_reject_credentials() {
        assert_eq!(
            normalized_origin("https://plex.local:32400/library/"),
            Ok("https://plex.local:32400".to_string())
        );
        assert_eq!(
            normalized_origin("http://10.0.0.4:32400"),
            Ok("http://10.0.0.4:32400".to_string())
        );
        assert!(normalized_origin("https://user:pass@plex.local:32400").is_err());
        assert!(normalized_origin("ftp://plex.local").is_err());
        assert!(normalized_origin("plex.local:32400").is_err());
    }

    #[test]
    fn paths_must_be_server_relative_and_free_of_traversal() {
        assert!(safe_path("/library/parts/4/17/file.flac").is_ok());
        assert!(safe_path("library/parts/4").is_err());
        assert!(safe_path("/library/../etc/passwd").is_err());
        assert!(safe_path("/library/parts/4 5").is_err());
    }

    #[test]
    fn keys_are_limited_to_plex_rating_key_shapes() {
        assert_eq!(safe_key(" 46618 "), Ok("46618".to_string()));
        assert!(safe_key("").is_err());
        assert!(safe_key("46618/children").is_err());
        assert!(safe_key("46618; rm").is_err());
    }

    #[test]
    fn artwork_references_never_carry_the_account_token_or_server_address() {
        let value = artwork_reference(
            "owned-client",
            "/library/metadata/12/thumb/1715?X-Plex-Token=owned-secret",
            400,
        );
        assert!(value.starts_with("harbor-music-art://plex/owned-client?path="));
        assert!(!value.contains("owned-secret"));
        assert!(!value.contains("plex.local"));
        let path = artwork_path(
            "/library/metadata/12/thumb/1715?X-Plex-Token=owned-secret",
            400,
        )
        .unwrap();
        assert!(path.contains("width=400&height=400"));
        assert!(!path.contains("owned-secret"));
        assert!(artwork_reference("owned-client", "not-a-path", 400).is_empty());
    }

    #[test]
    fn private_cover_request_retains_original_plex_transcoder_authorization_only_during_io() {
        let path = artwork_path("/library/metadata/12/thumb/1715", 400).unwrap();
        let authenticated = authenticated_artwork_path(&path, "owned-secret").unwrap();
        assert!(authenticated.contains("X-Plex-Token%3Downed-secret"));
        assert!(authenticated.ends_with("X-Plex-Token=owned-secret"));
        assert!(!path.contains("owned-secret"));
        assert!(authenticated_artwork_path(
            "/photo/:/transcode?url=%2F%2Fevil.example%2Fcover",
            "owned-secret"
        )
        .is_err());
    }

    #[test]
    fn direct_streams_append_the_token_to_the_part_key() {
        assert_eq!(
            direct_stream_url("https://plex.local", "abc", "/library/parts/1/2/a.flac"),
            Ok("https://plex.local/library/parts/1/2/a.flac?X-Plex-Token=abc".to_string())
        );
        assert!(direct_stream_url("https://plex.local", "abc", "parts/1").is_err());
    }

    #[test]
    fn transcode_urls_pin_the_client_identifier_and_bitrate() {
        let url = transcode_stream_url(
            "https://plex.local",
            "abc",
            "harbor-cid",
            "77",
            "owned-session",
        );
        assert!(
            url.contains("/music/:/transcode/universal/start.mp3?path=%2Flibrary%2Fmetadata%2F77")
        );
        assert!(url.contains("musicBitrate=320"));
        assert!(url.contains("X-Plex-Client-Identifier=harbor-cid"));
        assert!(url.contains("X-Plex-Session-Identifier="));
    }

    #[test]
    fn mime_types_follow_the_container_then_the_codec() {
        assert_eq!(mime_for(Some("flac"), None), "audio/flac");
        assert_eq!(mime_for(None, Some("aac")), "audio/mp4");
        assert_eq!(mime_for(Some("mp3"), Some("mp3")), "audio/mpeg");
        assert_eq!(mime_for(None, None), "audio/mpeg");
    }
}
