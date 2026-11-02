//! Pinned Desktop 0.9.132 Plex music implementation, hosted by native iOS.
mod browse;
mod client;
mod parse;
mod session;
use crate::music::{
    MusicAlbumRef, MusicArtistRef, MusicCatalogItem, MusicCatalogKind, MusicCatalogPage,
    MusicCatalogScope, MusicPlaylistRef, MusicSearchResults, MusicStationRef, MusicTrack,
};
use base64::Engine;
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::Duration;
#[derive(Deserialize)]
#[serde(
    tag = "action",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum Request {
    Connect {
        address: String,
        token: String,
        client_id: String,
    },
    Connected {
        config: session::PlexConfig,
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
        album: MusicAlbumRef,
    },
    ArtistTop {
        artist: MusicArtistRef,
    },
    ArtistCatalog {
        artist: MusicArtistRef,
        kind: MusicCatalogKind,
    },
    PlaylistTracks {
        playlist: MusicPlaylistRef,
    },
    StationTracks {
        station: MusicStationRef,
    },
    Resolve {
        track: MusicTrack,
        session_id: String,
    },
    Artwork {
        reference: String,
    },
}
pub(crate) async fn execute(request: Request) -> Result<Value, String> {
    let (config, command) = match request {
        Request::Connect {
            address,
            token,
            client_id,
        } => {
            if address.len() > 4096 {
                return Err("Invalid Plex address".into());
            }
            return serde_json::to_value(session::connect(&address, token, client_id).await?)
                .map_err(|_| "Invalid Plex response".into());
        }
        Request::Connected { config, command } => (config.validated()?, command),
    };
    let value = match command {
        Command::Home => serde_json::to_value(browse::hubs(&config).await?),
        Command::Search { query, limit } => {
            let query = query.trim();
            if query.chars().count() > 200 || !(1..=100).contains(&limit) {
                return Err("Invalid Plex search".into());
            }
            serde_json::to_value(if query.is_empty() {
                MusicSearchResults::default()
            } else {
                browse::search(&config, query, limit).await?
            })
        }
        Command::AlbumTracks { album } => {
            check_connector(&album.connector_id)?;
            serde_json::to_value(browse::album_tracks(&config, &album).await?)
        }
        Command::ArtistTop { artist } => {
            check_connector(&artist.connector_id)?;
            serde_json::to_value(browse::artist_top(&config, &artist).await?)
        }
        Command::ArtistCatalog { artist, kind } => {
            check_connector(&artist.connector_id)?;
            let items = match kind {
                MusicCatalogKind::Tracks => browse::artist_top(&config, &artist)
                    .await?
                    .into_iter()
                    .map(MusicCatalogItem::Track)
                    .collect(),
                MusicCatalogKind::Albums => Vec::new(),
            };
            serde_json::to_value(MusicCatalogPage {
                items,
                next_cursor: None,
                total: None,
                scope: MusicCatalogScope::Limited,
            })
        }
        Command::PlaylistTracks { playlist } => {
            check_connector(&playlist.connector_id)?;
            serde_json::to_value(browse::playlist_tracks(&config, &playlist).await?)
        }
        Command::StationTracks { station } => {
            check_connector(&station.connector_id)?;
            serde_json::to_value(browse::station_tracks(&config, &station).await?)
        }
        Command::Resolve { track, session_id } => {
            check_connector(track.connector_id.as_deref().unwrap_or_default())?;
            session::validate_header(&session_id, 128)?;
            serde_json::to_value(browse::resolve(&config, &track, &session_id).await?)
        }
        Command::Artwork { reference } => {
            let url =
                url::Url::parse(&reference).map_err(|_| "Invalid Plex artwork".to_string())?;
            if url.scheme() != "harbor-music-art"
                || url.host_str() != Some("plex")
                || url.path() != format!("/{}", config.client_id)
            {
                return Err("Retired Plex artwork".into());
            }
            let path = url
                .query_pairs()
                .find(|(key, _)| key == "path")
                .map(|(_, value)| value.into_owned())
                .ok_or("Invalid Plex artwork")?;
            if !path.starts_with("/photo/:/transcode?") {
                return Err("Invalid Plex artwork".into());
            }
            let bytes = client::get_bytes(
                &config.origin,
                &client::authenticated_artwork_path(&path, &config.token)?,
                &config.client_id,
                Some(&config.token),
                Duration::from_secs(12),
                2 * 1024 * 1024,
            )
            .await?;
            Ok(json!({"data":base64::engine::general_purpose::STANDARD.encode(bytes)}))
        }
    };
    value.map_err(|_| "Invalid Plex response".into())
}
fn check_connector(value: &str) -> Result<(), String> {
    if value == "plex" {
        Ok(())
    } else {
        Err("Invalid Plex reference".into())
    }
}
