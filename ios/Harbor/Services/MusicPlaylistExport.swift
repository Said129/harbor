import Foundation

struct MusicPlaylistExport: Sendable {
    let data: Data
    let filename: String
    let name: String
    let count: Int
}
struct MusicM3UEntry: Sendable { let track: MusicTrack; let location: String }
enum MusicPlaylistExportError: Error { case unavailable, location }

actor MusicM3URenderer {
    func render(_ entries: [MusicM3UEntry]) throws -> Data {
        var content = "#EXTM3U\n"
        for entry in entries {
            try Task.checkCancellation()
            let location = entry.location.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !location.isEmpty, location.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n")) == nil else { throw MusicPlaylistExportError.location }
            content += "#EXTINF:\(entry.track.durationSeconds),\(Self.oneLine(entry.track.artist)) - \(Self.oneLine(entry.track.title))\n\(location)\n"
        }
        return Data(content.utf8)
    }
    private static func oneLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    nonisolated static func filename(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: #"[<>:"/\\|?*]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "playlist" : cleaned) + ".m3u"
    }
}

@MainActor enum MusicPlaylistExporter {
    static func prepare(_ playlist: MusicPlaylist, tracks: [MusicTrack], owner: String,
                        using resolver: any MusicPlaybackResolving, allowed: @MainActor () -> Bool) async throws -> MusicPlaylistExport {
        func validate() throws {
            try Task.checkCancellation(); try resolver.validate()
            guard resolver.scope.owner == owner, allowed() else { throw CancellationError() }
        }
        try validate()
        // Export the complete stored list in its original order, including when
        // the visible collection is filtered. Never silently drop missing files.
        guard tracks.map(\.id) == playlist.trackIds else { throw MusicPlaylistExportError.unavailable }
        var entries: [MusicM3UEntry] = [], leases: [@MainActor @Sendable () -> Bool] = []
        for track in tracks {
            try validate()
            let resolved = try await resolver.resolve(track)
            try validate(); guard resolved.valid() else { throw CancellationError() }
            entries.append(.init(track: track, location: resolved.stream.url.isFileURL ? resolved.stream.url.path : resolved.stream.url.absoluteString))
            leases.append(resolved.valid)
        }
        let data = try await MusicM3URenderer().render(entries)
        try validate(); guard leases.allSatisfy({ $0() }) else { throw CancellationError() }
        return .init(data: data, filename: MusicM3URenderer.filename(playlist.name), name: playlist.name, count: tracks.count)
    }
}
