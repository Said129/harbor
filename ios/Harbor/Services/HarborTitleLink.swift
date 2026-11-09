import Foundation

/// The Desktop title-link route, with an optional episode hint for the existing detail screen.
struct HarborTitleLink: Hashable, Sendable {
    let kind: String
    let mediaID: String
    let videoID: String?

    var media: Media { Media(id: mediaID, type: kind, name: mediaID) }

    var episodeHint: Episode? {
        guard let videoID, kind == "series" || kind == "anime" else { return nil }
        let prefix = mediaID + ":"
        let parts = videoID.hasPrefix(prefix) ? videoID.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false) : []
        guard parts.count == 2, let season = Int(parts[0]), season >= 0,
              let episode = Int(parts[1]), episode > 0 else { return Episode(id: videoID) }
        return Episode(id: videoID, season: season, episode: episode)
    }

    static func parse(_ url: URL) -> Self? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["harbor", "stremio"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.lowercased() == "detail", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.query == nil, parts.fragment == nil else { return nil }
        let path = parts.percentEncodedPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard parts.percentEncodedPath.hasPrefix("/"), (2...3).contains(path.count),
              let kind = path[0].removingPercentEncoding, ["movie", "series", "anime", "tv", "channel"].contains(kind),
              let id = path[1].removingPercentEncoding, isSafeID(id) else { return nil }
        var video: String?
        if path.count == 3 {
            guard let id = path[2].removingPercentEncoding, isSafeID(id) else { return nil }
            video = id
        }
        return .init(kind: kind, mediaID: id, videoID: video)
    }

    private static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 256 && id != "." && id != ".." &&
            !id.contains("/") && !id.contains("\\") && id.rangeOfCharacter(from: .controlCharacters) == nil
    }
}
