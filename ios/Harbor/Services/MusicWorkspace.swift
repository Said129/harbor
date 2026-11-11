import Foundation

/// Catalog navigation and a song playing outside the Music page keep the same
/// profile-owned server session, including its credential revision.
@MainActor final class MusicWorkspace {
    let scope: PluginExecutionScope
    let library: MusicLibrary
    let playlists: MusicPlaylistStore
    let plex: PlexMusicService
    let jellyfin: JellyfinMusicService
    let server: SubsonicMusicService
    let spotify: SpotifyMusicService
    let lyrics: MusicLyricsClient
    let soundcloud: SoundCloudMusicService
    let youtube: YouTubeMusicService
    let audio: MusicAudioPreferences
    let lastfm: LastFmMusicService
    let catalog: MusicCatalogModel
    let playback: MusicPlaybackSession
    private var disposed = false
    var available: Bool { !disposed && server.active }
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope
        let library = MusicLibrary(owner: scope.owner), playlists = MusicPlaylistStore(owner: scope.owner)
        let server = SubsonicMusicService(scope: scope, currentScope: currentScope)
        self.library = library; self.playlists = playlists; self.server = server
        let plex = PlexMusicService(scope: scope, currentScope: currentScope); self.plex = plex
        let jellyfin = JellyfinMusicService(scope: scope, currentScope: currentScope); self.jellyfin = jellyfin
        spotify = SpotifyMusicService(scope: scope, currentScope: currentScope)
        let lyrics = MusicLyricsClient(scope: scope, currentScope: currentScope); self.lyrics = lyrics
        let soundcloud = SoundCloudMusicService(scope: scope, currentScope: currentScope); self.soundcloud = soundcloud
        let youtube = YouTubeMusicService(scope: scope, currentScope: currentScope); self.youtube = youtube
        let audio = MusicAudioPreferences(owner: scope.owner); self.audio = audio
        let lastfm = LastFmMusicService(scope: scope, currentScope: currentScope); self.lastfm = lastfm
        spotify.configureScrobbling(lastfm)
        let catalogClient = MusicServerCatalogClient(server: server, soundcloud: soundcloud, youtube: youtube, jellyfin: jellyfin, plex: plex, currentScope: currentScope)
        catalog = MusicCatalogModel(client: catalogClient)
        playback = MusicPlaybackSession(server: server, playlists: playlists, localRecords: { library.records }, localRevision: { library.revision }, lyrics: lyrics, soundcloud: soundcloud, youtube: youtube, jellyfin: jellyfin, plex: plex, audio: audio, lastfm: lastfm, catalog: catalogClient, currentScope: currentScope)
    }
    func dispose() { disposed = true; lastfm.dispose(); plex.dispose(); jellyfin.dispose(); soundcloud.dispose(); youtube.dispose(); lyrics.dispose(); spotify.dispose(); server.dispose(); library.cancelImport(); catalog.invalidatePrivateServer() }
}
