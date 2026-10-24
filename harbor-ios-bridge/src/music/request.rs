use super::{connectors::catalog::CatalogConnector, CatalogContext, MusicAlbumRef,
    MusicArtistRef, MusicCatalogKind, MusicPlaylistRef};
use serde::Deserialize;
use serde_json::Value;
use std::sync::OnceLock;

#[derive(Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "camelCase", deny_unknown_fields)]
pub(crate) enum Request {
    Home,
    Search { query: String, #[serde(default = "default_limit")] limit: usize },
    AlbumTracks { album: MusicAlbumRef },
    ArtistTop { artist: MusicArtistRef },
    ArtistRows { artist: MusicArtistRef },
    ArtistCatalog { artist: MusicArtistRef, kind: MusicCatalogKind, cursor: Option<String> },
    PlaylistTracks { playlist: MusicPlaylistRef },
    Connection,
}
fn default_limit() -> usize { 24 }

pub(crate) async fn execute(request: Request) -> Result<Value, String> {
    static CATALOG: OnceLock<CatalogConnector> = OnceLock::new();
    let catalog = CATALOG.get_or_init(CatalogConnector::new);
    let context = CatalogContext;
    let value = match request {
        Request::Home => serde_json::to_value(catalog.browse_home(&context).await?),
        Request::Search { query, limit } => {
            let query = query.trim();
            if query.chars().count() > 200 || !(1..=100).contains(&limit) {
                return Err("Invalid music search request".into());
            }
            if query.is_empty() { return serde_json::to_value(super::MusicSearchResults::default()).map_err(|_| "Music response could not be encoded".into()); }
            serde_json::to_value(catalog.search_typed(&context, query, limit).await?)
        }
        Request::AlbumTracks { album } => serde_json::to_value(catalog.album_tracks(&context, &album).await?),
        Request::ArtistTop { artist } => serde_json::to_value(catalog.artist_top(&context, &artist).await?),
        Request::ArtistRows { artist } => serde_json::to_value(catalog.artist_rows(&context, &artist).await?),
        Request::ArtistCatalog { artist, kind, cursor } => serde_json::to_value(catalog.artist_catalog(&context, &artist, kind, cursor.as_deref()).await?),
        Request::PlaylistTracks { playlist } => serde_json::to_value(catalog.playlist_tracks(&context, &playlist).await?),
        Request::Connection => serde_json::to_value(catalog.connection()),
    };
    value.map_err(|_| "Music response could not be encoded".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn music_catalog_request_preserves_the_browse_only_connector_contract() {
        let value = execute(Request::Connection).await.unwrap();
        assert_eq!(value["id"], "catalog");
        assert_eq!(value["capabilities"], json!(["search", "browse"]));
        assert_eq!(value["anonymous"], true);
    }

    #[tokio::test]
    async fn music_catalog_empty_and_invalid_requests_never_make_provider_requests() {
        let empty = execute(Request::Search { query: "  ".into(), limit: 24 }).await.unwrap();
        assert_eq!(empty["tracks"], json!([])); assert_eq!(empty["albums"], json!([]));
        assert!(execute(Request::Search { query: "a".repeat(201), limit: 24 }).await.is_err());
        assert!(execute(Request::Search { query: "owned".into(), limit: 0 }).await.is_err());
        assert!(serde_json::from_value::<Request>(json!({"operation":"search","query":"owned","url":"https://unrelated.invalid"})).is_err());
        assert!(serde_json::from_value::<Request>(json!({"operation":"executeCode","code":"1+1"})).is_err());
    }
}
