//! Pinned Desktop 0.9.132 Jellyfin parsing, browsing and stream selection.
//! iOS supplies profile-owned Keychain credentials per cancellable operation.
mod api;
mod browse;
mod config;
mod http;
mod items;
mod rows;
mod stream;
use crate::music::{
    MusicCatalogItem, MusicCatalogPage, MusicCatalogScope, MusicStream, MusicTrack,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;

#[derive(Deserialize)]
#[serde(
    tag = "action",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum Request {
    SignIn {
        address: String,
        username: String,
        password: String,
        device_id: String,
    },
    Connected {
        config: config::JellyfinConfig,
        command: Command,
    },
}
#[derive(Deserialize)]
#[serde(
    tag = "action",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum Command {
    Home,
    Search {
        query: String,
        limit: usize,
    },
    AlbumTracks {
        id: String,
    },
    ArtistTop {
        id: String,
    },
    ArtistCatalog {
        id: String,
        kind: crate::music::MusicCatalogKind,
    },
    PlaylistTracks {
        id: String,
    },
    StationTracks {
        id: String,
    },
    Resolve {
        track: MusicTrack,
    },
    Started {
        session: api::PlaybackSession,
        direct: bool,
    },
    Stopped {
        session: api::PlaybackSession,
    },
}
pub(crate) async fn execute(request: Request) -> Result<Value, String> {
    let (config, command) = match request {
        Request::SignIn {
            address,
            username,
            password,
            device_id,
        } => {
            if address.len() > 4096 || username.len() > 512 || password.len() > 16384 {
                return Err("Invalid Jellyfin account".into());
            }
            let fields = HashMap::from([
                ("url".into(), address),
                ("username".into(), username),
                ("password".into(), password),
            ]);
            return serde_json::to_value(api::sign_in(device_id, &fields).await?)
                .map_err(|_| "Invalid Jellyfin response".into());
        }
        Request::Connected { config, command } => (config.validated()?, command),
    };
    let value = match command {
        Command::Home => {
            let library = browse::library_id(&config).await;
            serde_json::to_value(rows::home(&config, library.as_deref()).await?)
        }
        Command::Search { query, limit } => {
            let query = query.trim();
            if query.chars().count() > 200 || !(1..=100).contains(&limit) {
                return Err("Invalid music search request".into());
            }
            serde_json::to_value(if query.is_empty() {
                crate::music::MusicSearchResults::default()
            } else {
                browse::search_typed(&config, query, limit).await?
            })
        }
        Command::AlbumTracks { id } => {
            serde_json::to_value(browse::album_tracks(&config, &id).await?)
        }
        Command::ArtistTop { id } => serde_json::to_value(browse::artist_top(&config, &id).await?),
        Command::ArtistCatalog { id, kind } => {
            let items = match kind {
                crate::music::MusicCatalogKind::Tracks => browse::artist_top(&config, &id)
                    .await?
                    .into_iter()
                    .map(MusicCatalogItem::Track)
                    .collect(),
                crate::music::MusicCatalogKind::Albums => Vec::new(),
            };
            serde_json::to_value(MusicCatalogPage {
                items,
                next_cursor: None,
                total: None,
                scope: MusicCatalogScope::Limited,
            })
        }
        Command::PlaylistTracks { id } => {
            serde_json::to_value(browse::playlist_tracks(&config, &id).await?)
        }
        Command::StationTracks { id } => {
            serde_json::to_value(browse::station_tracks(&config, &id).await?)
        }
        Command::Resolve { track } => {
            if track.connector_id.as_deref() != Some("jellyfin") {
                return Err("Invalid Jellyfin recording".into());
            }
            let item_id = items::safe_item_id(stream::source_of(&track))?;
            let info = api::playback_info(&config, &item_id, stream::TRANSCODE_BITRATE).await?;
            let source = info.media_sources.into_iter().next().unwrap_or_default();
            let direct = stream::direct_play(&source);
            let session = api::PlaybackSession {
                item_id: item_id.clone(),
                play_session_id: info.play_session_id.unwrap_or_else(|| item_id.clone()),
                media_source_id: source.id.clone(),
            };
            let resolved = MusicStream {
                http_headers: Default::default(),
                url: stream::universal(&config, &item_id, &session)?,
                mime_type: stream::mime_for(&source, direct).to_string(),
                bitrate: stream::bitrate_for(&source, direct),
            };
            Ok(json!({ "stream": resolved, "session": session, "direct": direct }))
        }
        Command::Started { session, direct } => {
            validate_session(&session)?;
            api::report_started(&config, &session, direct).await?;
            Ok(Value::Null)
        }
        Command::Stopped { session } => {
            validate_session(&session)?;
            api::report_stopped(&config, &session).await?;
            Ok(Value::Null)
        }
    };
    value.map_err(|_| "Invalid Jellyfin response".into())
}
fn validate_session(session: &api::PlaybackSession) -> Result<(), String> {
    items::safe_item_id(&session.item_id)?;
    config::validate_header_field(&session.play_session_id, 512)?;
    if let Some(id) = &session.media_source_id {
        items::safe_item_id(id)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn private_request_boundary_rejects_unaddressable_items_before_io() {
        let config = json!({"origin":"https://media.example.test/proxy", "userId":"u1", "userName":"Owned", "token":"owned", "deviceId":"owned-device", "serverName":"Owned", "libraryId":null});
        let value = json!({"action":"connected", "config":config, "command":{"action":"albumTracks", "id":"../System/Info"}});
        assert!(execute(serde_json::from_value(value).unwrap())
            .await
            .is_err());
        let malformed = json!({"action":"signIn", "address":"https://media.example.test", "username":"owned", "password":"owned", "deviceId":"bad\nHeader"});
        assert!(execute(serde_json::from_value(malformed).unwrap())
            .await
            .is_err());
        assert!(serde_json::from_value::<Request>(json!({"action":"signIn", "address":"https://media.example.test", "username":"owned", "password":"owned", "deviceId":"device", "command":"executeCode"})).is_err());
    }
}
