import Foundation
import Observation

enum SpooktoberWorldIntent: Sendable {
    case media(Media), track(MusicTrack), video(MusicTrack), playlist(String), external(URL), back, reload, ready
    static let playlists: Set<String> = ["party", "dark", "scores", "goth", "emo", "darkpop"]
    static func parse(_ message: JSONValue) -> Self? {
        guard message["channel"].string == "harbor-spooktober", let intent = message["intent"].string else { return nil }
        switch intent {
        case "back": return .back
        case "reload": return .reload
        case "ready": return .ready
        case "playlist":
            guard let id = message["id"].string, playlists.contains(id) else { return nil }; return .playlist(id)
        case "external":
            guard let value = message["url"].string, let url = externalURL(value) else { return nil }; return .external(url)
        default: break
        }
        let item = message["item"]
        guard let title = item["title"].string, !title.isEmpty, title.utf8.count <= 2_048 else { return nil }
        if intent == "meta" {
            guard let id = item["imdbId"].string, id.range(of: #"^tt[0-9]{5,12}$"#, options: .regularExpression) != nil else { return nil }
            var media = Media(id: id, type: item["type"].string == "Series" ? "series" : "movie", name: title)
            media.poster = artwork(item["poster"].string); media.description = item["description"].string
            media.releaseInfo = item["year"].textValue ?? ""
            media.genres = item["genres"].array.compactMap(\.string); return .media(media)
        }
        guard let id = item["id"].string, !id.isEmpty, id.utf8.count <= 256 else { return nil }
        if intent == "video" {
            guard id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
            return .video(MusicTrack(id: id, connectorId: "youtube", sourceId: id, playbackUrl: nil, title: title,
                artist: item["artist"].string ?? "", album: nil, artwork: artwork(item["image"].string) ?? "",
                durationSeconds: 0, durationLabel: "", mediaKind: "video"))
        }
        if intent == "track" {
            guard let artist = item["creator"].string, !artist.isEmpty, artist.utf8.count <= 2_048 else { return nil }
            let source = id.range(of: #"^music-[0-9]+$"#, options: .regularExpression) == nil ? nil : String(id.dropFirst(6))
            let number = item["duration"].numericValue ?? 0
            guard number.isFinite, number <= 604_800 else { return nil }
            let duration = UInt64(max(0, number.rounded()))
            return .track(MusicTrack(id: source.map { "itunes:track:" + $0 } ?? "spooktober:" + id,
                connectorId: "catalog", sourceId: source, playbackUrl: nil, title: title, artist: artist,
                album: item["album"].string ?? "", artwork: artwork(item["poster"].string) ?? "",
                durationSeconds: duration, durationLabel: "\(duration / 60):" + String(format: "%02d", duration % 60),
                explicit: item["explicit"] == .null ? nil : item["explicit"] == .bool(true), mediaKind: "audio"))
        }
        return nil
    }
    static func externalURL(_ value: String) -> URL? {
        guard value.utf8.count <= 4_096, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }; return url
    }
    static func artwork(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if externalURL(value) != nil { return value }
        let path = value.hasPrefix("/spooktober/") ? String(value.dropFirst()) : value.hasPrefix("assets/") ? "spooktober/" + value : nil
        let url = path.flatMap { URL(string: "harbor-spook://world/" + $0) } ?? URL(string: value)
        guard let url, let path = SpooktoberWorldResources.path(url), path.hasPrefix("spooktober/assets/") else { return nil }
        return url.absoluteString
    }
}

@MainActor protocol SpooktoberWorldPersistence {
    func read(owner: String) throws -> [String: String]?
    func write(_ value: [String: String], owner: String) throws
}
@MainActor private struct KeychainSpooktoberWorld: SpooktoberWorldPersistence {
    private func key(_ owner: String) -> String { "spooktober-world-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> [String: String]? { try KeychainStore().read(key(owner), as: [String: String].self) }
    func write(_ value: [String: String], owner: String) throws { try KeychainStore().write(value, key: key(owner)) }
}
@MainActor @Observable final class SpooktoberWorldStore {
    static let keys: Set<String> = ["harbor-spookfest-list", "harbor-spookfest-motion", "spooktober-twilight-team"]
    let owner: String
    private let persistence: any SpooktoberWorldPersistence
    private(set) var values: [String: String] = [:]
    private(set) var ready = false
    private(set) var error: String?
    init(owner: String, persistence: (any SpooktoberWorldPersistence)? = nil) {
        self.owner = owner; self.persistence = persistence ?? KeychainSpooktoberWorld()
        do {
            guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "spooktober-owner") }
            let values = try self.persistence.read(owner: owner) ?? [:]
            guard Self.valid(values) else { throw HarborError(code: "spooktober-state") }
            self.values = values; ready = true
        } catch { self.error = "Could not read your Spooktober preferences. Your data is preserved." }
    }
    func set(_ key: String, value: String?) throws {
        guard ready, Self.keys.contains(key) else { throw HarborError(code: "spooktober-state") }
        var next = values; next[key] = value
        guard Self.valid(next) else { throw HarborError(code: "spooktober-state") }
        try persistence.write(next, owner: owner); values = next; error = nil
    }
    private static func valid(_ values: [String: String]) -> Bool {
        guard Set(values.keys).isSubset(of: keys), values.values.allSatisfy({ $0.utf8.count <= 256 * 1_024 }) else { return false }
        if let saved = values["harbor-spookfest-list"] {
            guard let data = saved.data(using: .utf8), let ids = try? JSONDecoder().decode([String].self, from: data),
                  ids.count <= 2_000, ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else { return false }
        }
        if let motion = values["harbor-spookfest-motion"], !["on", "off"].contains(motion) { return false }
        if let team = values["spooktober-twilight-team"], !["", "edward", "jacob"].contains(team) { return false }
        return true
    }
}
