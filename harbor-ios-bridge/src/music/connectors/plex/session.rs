use super::client;
use super::parse::{container, nodes};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::Duration;
const PROBE_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_PROBES: usize = 8;
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlexConfig {
    pub origin: String,
    pub token: String,
    pub client_id: String,
    pub section: String,
    pub section_uuid: Option<String>,
    pub server: Option<String>,
}

struct Candidate {
    origin: String,
    token: String,
    server: String,
    rank: u8,
}

fn candidates(resources: &Value) -> Vec<Candidate> {
    let mut out = Vec::new();
    for resource in resources.as_array().map(Vec::as_slice).unwrap_or(&[]) {
        let provides = resource
            .get("provides")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if !provides.split(',').any(|entry| entry.trim() == "server") {
            continue;
        }
        let Some(token) = resource.get("accessToken").and_then(Value::as_str) else {
            continue;
        };
        let server = resource
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("Plex")
            .to_string();
        for connection in nodes(resource, "connections") {
            let relay = connection.get("relay").and_then(Value::as_bool) == Some(true);
            let local = connection.get("local").and_then(Value::as_bool) == Some(true);
            let uri = connection.get("uri").and_then(Value::as_str).unwrap_or("");
            let Ok(origin) = client::normalized_origin(uri) else {
                continue;
            };
            out.push(Candidate {
                origin,
                token: token.to_string(),
                server: server.clone(),
                rank: if relay {
                    2
                } else if local {
                    0
                } else {
                    1
                },
            });
        }
    }
    out.sort_by_key(|candidate| candidate.rank);
    out.truncate(MAX_PROBES);
    out
}

pub async fn music_section(
    origin: &str,
    token: &str,
    client_id: &str,
) -> Result<(String, Option<String>), String> {
    let body = client::get_json(
        origin,
        "/library/sections",
        client_id,
        Some(token),
        PROBE_TIMEOUT,
    )
    .await?;
    nodes(container(&body), "Directory")
        .iter()
        .find(|entry| entry.get("type").and_then(Value::as_str) == Some("artist"))
        .and_then(|entry| {
            let key = entry
                .get("key")
                .and_then(Value::as_str)
                .map(str::to_string)?;
            let uuid = entry
                .get("uuid")
                .and_then(Value::as_str)
                .map(str::to_string);
            Some((key, uuid))
        })
        .ok_or_else(|| "This Plex server has no music library".to_string())
}

impl PlexConfig {
    pub fn validated(mut self) -> Result<Self, String> {
        self.origin = client::normalized_origin(&self.origin)?;
        validate_header(&self.token, 16384)?;
        validate_header(&self.client_id, 128)?;
        if !self
            .client_id
            .bytes()
            .all(|v| v.is_ascii_alphanumeric() || v == b'-')
        {
            return Err("Invalid Plex client".into());
        }
        self.section = client::safe_key(&self.section)?;
        Ok(self)
    }
}
pub fn validate_header(value: &str, maximum: usize) -> Result<(), String> {
    if value.is_empty() || value.len() > maximum || value.bytes().any(|v| v.is_ascii_control()) {
        return Err("Invalid Plex account".into());
    }
    Ok(())
}
pub async fn connect(origin: &str, token: String, client_id: String) -> Result<PlexConfig, String> {
    validate_header(&token, 16384)?;
    validate_header(&client_id, 128)?;
    if !client_id
        .bytes()
        .all(|v| v.is_ascii_alphanumeric() || v == b'-')
    {
        return Err("Invalid Plex client".into());
    }
    if origin.trim().is_empty() {
        return tokio::time::timeout(Duration::from_secs(10), discover(&token, &client_id))
            .await
            .map_err(|_| "Plex discovery timed out".to_string())?;
    }
    let origin = client::normalized_origin(origin)?;
    let (section, section_uuid) = music_section(&origin, &token, &client_id).await?;
    PlexConfig {
        origin,
        token,
        client_id,
        section,
        section_uuid,
        server: None,
    }
    .validated()
}
async fn discover(token: &str, client_id: &str) -> Result<PlexConfig, String> {
    let resources = client::get_json(
        client::ACCOUNT_ORIGIN,
        "/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1",
        client_id,
        Some(token),
        Duration::from_secs(7),
    )
    .await?;
    let servers = candidates(&resources);
    let mut probes = tokio::task::JoinSet::new();
    for (index, candidate) in servers.iter().enumerate() {
        let origin = candidate.origin.clone();
        let token = candidate.token.clone();
        let client_id = client_id.to_string();
        probes.spawn(async move { (index, music_section(&origin, &token, &client_id).await) });
    }
    let mut found = Vec::new();
    while let Some(result) = probes.join_next().await {
        if let Ok((index, Ok(section))) = result {
            found.push((index, section));
        }
    }
    found.sort_by_key(|(index, _)| *index);
    if let Some((index, (section, section_uuid))) = found.into_iter().next() {
        let candidate = &servers[index];
        return PlexConfig {
            origin: candidate.origin.clone(),
            token: candidate.token.clone(),
            client_id: client_id.to_string(),
            section,
            section_uuid,
            server: Some(candidate.server.clone()),
        }
        .validated();
    }
    Err("No Plex music server was reachable".into())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn candidates_prefer_local_then_remote_then_relay() {
        let resources = serde_json::json!([
            { "name": "Ignore", "provides": "player", "accessToken": "x", "connections": [] },
            {
                "name": "Attic",
                "provides": "server,player",
                "accessToken": "srv",
                "connections": [
                    { "uri": "https://relay.plex.direct:443", "relay": true, "local": false },
                    { "uri": "https://remote.plex.direct:32400", "relay": false, "local": false },
                    { "uri": "https://192-168-1-8.plex.direct:32400", "relay": false, "local": true }
                ]
            }
        ]);
        let found = candidates(&resources);
        assert_eq!(found.len(), 3);
        assert_eq!(found[0].origin, "https://192-168-1-8.plex.direct:32400");
        assert_eq!(found[1].origin, "https://remote.plex.direct:32400");
        assert_eq!(found[2].origin, "https://relay.plex.direct");
        assert_eq!(found[0].token, "srv");
        assert_eq!(found[0].server, "Attic");
    }

    #[test]
    fn private_account_input_is_validated_before_network_io() {
        assert!(validate_header("owned\nHeader", 100).is_err());
        assert!(validate_header("owned", 100).is_ok());
    }
}
