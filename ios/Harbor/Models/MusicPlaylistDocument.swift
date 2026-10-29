import Foundation

/// Membership and full recording metadata are committed together, as in Desktop's
/// playlist transaction. Existing local-only membership documents remain readable.
struct MusicPlaylistDocument: Codable, Sendable {
    var schema = 1
    var playlists: [MusicPlaylist] = []
    var tracks: [String: MusicTrack] = [:]

    func validated() throws -> Self {
        guard schema == 1, playlists.count <= 200,
              Set(playlists.map(\.id)).count == playlists.count,
              playlists.allSatisfy({ value in
                  UUID(uuidString: value.id) != nil && !value.name.isEmpty && value.name.unicodeScalars.count <= 100 && !value.name.contains("\0") &&
                  value.trackIds.count <= 500 && Set(value.trackIds).count == value.trackIds.count && value.trackIds.allSatisfy(Self.validID) &&
                  value.trackAddedAt.count <= 500 && Set(value.trackAddedAt.keys).isSubset(of: Set(value.trackIds)) &&
                  Int64(value.createdAt) != nil && Int64(value.updatedAt) != nil
              }), tracks.count <= 100_000,
              tracks.allSatisfy({ key, track in
                  key == track.id && Self.validID(key) &&
                  (track.mediaKind.map { ["audio", "video"].contains($0) } ?? true) &&
                  [track.quality?.sampleRateHz, track.quality?.bitDepth, track.quality?.bitrateKbps].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 })
              }), try JSONEncoder().encode(self).count <= 16 * 1024 * 1024 else { throw HarborError(code: "music-store") }
        return self
    }
    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8192 && value.rangeOfCharacter(from: .controlCharacters) == nil
    }
}

extension MusicTrack {
    /// Preserve Desktop's database defaults and nullable metadata merge. Remote
    /// stream URLs are resolved again for playback, rather than saved as recordings.
    func playlistRecording(replacing previous: MusicTrack?) -> MusicTrack {
        let connector = connectorId ?? "youtube"
        let incomingURL = playbackUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rememberedURL = incomingURL.flatMap { $0.isEmpty ? nil : $0 } ?? previous?.playbackUrl
        let kind = mediaKind.flatMap { ["audio", "video"].contains($0) ? $0 : nil } ?? previous?.mediaKind
        return MusicTrack(id: id, connectorId: connector, sourceId: sourceId ?? id,
            playbackUrl: ["local", "direct"].contains(connector) ? rememberedURL : nil,
            title: title, artist: artist, album: album, artwork: artwork, durationSeconds: durationSeconds,
            durationLabel: "\(durationSeconds / 60):" + String(format: "%02llu", durationSeconds % 60),
            explicit: explicit ?? previous?.explicit, version: version ?? previous?.version,
            mediaKind: kind, isrc: isrc ?? previous?.isrc, releaseDate: releaseDate ?? previous?.releaseDate,
            collectionOrigin: collectionOrigin ?? previous?.collectionOrigin, quality: quality ?? previous?.quality)
    }
}

@MainActor protocol MusicPlaylistPersistence {
    func read(owner: String) throws -> MusicPlaylistDocument?
    func write(_ value: MusicPlaylistDocument, owner: String) throws
}
@MainActor struct KeychainMusicPlaylistPersistence: MusicPlaylistPersistence {
    private func key(_ owner: String) -> String { "music-playlists-v2-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> MusicPlaylistDocument? {
        let keychain = KeychainStore()
        if let saved = try keychain.read(key(owner), as: MusicPlaylistDocument.self) { return saved }
        guard let legacy = try keychain.read("music-playlists-" + EBookShelf.hash(owner), as: [MusicPlaylist].self) else { return nil }
        return MusicPlaylistDocument(playlists: legacy)
    }
    func write(_ value: MusicPlaylistDocument, owner: String) throws {
        try KeychainStore().write(value, key: key(owner))
    }
}
