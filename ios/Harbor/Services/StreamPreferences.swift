import Foundation
import Observation

@MainActor @Observable
final class StreamPreferences {
    static let shared = StreamPreferences()
    var filterLevel = UserDefaults.standard.string(forKey: "streamFilterLevel") ?? "strict" {
        didSet { persist(filterLevel, forKey: "streamFilterLevel") }
    }
    var addonOrder = UserDefaults.standard.object(forKey: "streams.addonOrder") as? Bool ?? true {
        didSet { persist(addonOrder, forKey: "streams.addonOrder") }
    }
    /// Seconds Harbor waits for each addon (Desktop "Addon wait time", 8...120, default 30).
    var addonTimeoutSeconds = StreamSourceSettings.clamped(UserDefaults.standard.object(forKey: "streams.addonTimeoutSec") as? Int ?? StreamSourceSettings.defaultTimeoutSeconds) {
        didSet { persist(addonTimeoutSeconds, forKey: "streams.addonTimeoutSec") }
    }
    /// "Prefer these sources": both, direct/debrid or P2P.
    var sourceMode = StreamMode(stored: UserDefaults.standard.string(forKey: "streams.mode")) {
        didSet { persist(sourceMode.rawValue, forKey: "streams.mode") }
    }
    /// Addons listed first win ("Stream priority"). Empty follows the addon list.
    var priority = StreamPreferences.storedPriority() {
        didSet { persist(StreamPreferences.encode(priority), forKey: "streams.priority") }
    }
    /// "condensed" (top pick, quality tiles and a drawer) or "stremio" (a flat list grouped by addon).
    /// Desktop opens on Stremio; the iPhone keeps the Condensed picker it already shipped with.
    var pickerLayout = UserDefaults.standard.string(forKey: "streams.pickerLayout") ?? "condensed" {
        didSet { persist(pickerLayout, forKey: "streams.pickerLayout") }
    }
    var pickerShowFilename = UserDefaults.standard.object(forKey: "streams.pickerShowFilename") as? Bool ?? false {
        didSet { persist(pickerShowFilename, forKey: "streams.pickerShowFilename") }
    }
    var fullStreamDescription = UserDefaults.standard.object(forKey: "streams.fullDescription") as? Bool ?? true {
        didSet { persist(fullStreamDescription, forKey: "streams.fullDescription") }
    }
    var pickerRefreshNextToBack = UserDefaults.standard.object(forKey: "streams.pickerRefreshNextToBack") as? Bool ?? false {
        didSet { persist(pickerRefreshNextToBack, forKey: "streams.pickerRefreshNextToBack") }
    }
    var sourceSettings: StreamSourceSettings { .init(timeoutSeconds: addonTimeoutSeconds, mode: sourceMode, priority: priority) }
    func configuration() -> StreamFilterConfiguration { .init(level: filterLevel, addonOrder: addonOrder, sources: sourceSettings) }
    private nonisolated static func storedPriority() -> [StreamPriorityEntry] {
        guard let text = UserDefaults.standard.string(forKey: "streams.priority"),
              let entries = try? JSONDecoder().decode([StreamPriorityEntry].self, from: Data(text.utf8)) else { return [] }
        return Array(entries.prefix(64))
    }
    private nonisolated static func encode(_ entries: [StreamPriorityEntry]) -> String {
        (try? JSONEncoder().encode(Array(entries.prefix(64)))).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    var automatic = UserDefaults.standard.object(forKey: "streams.automatic") as? Bool ?? true {
        didSet { persist(automatic, forKey: "streams.automatic") }
    }
    var keepSourceNextEpisode = UserDefaults.standard.object(forKey: "keepSourceNextEpisode") as? Bool ?? false {
        didSet { persist(keepSourceNextEpisode, forKey: "keepSourceNextEpisode") }
    }
    var excludeCamera = UserDefaults.standard.object(forKey: "streams.excludeCamera") as? Bool ?? true {
        didSet { persist(excludeCamera, forKey: "streams.excludeCamera") }
    }
    var maximum = UserDefaults.standard.object(forKey: "streams.maximum") as? Int ?? 2160 {
        didSet { persist(maximum, forKey: "streams.maximum") }
    }
    var minimum = UserDefaults.standard.object(forKey: "streams.minimum") as? Int ?? 0 {
        didSet { persist(minimum, forKey: "streams.minimum") }
    }
    func filter(_ offers: [StreamOffer]) -> [StreamOffer] {
        offers.filter { offer in
            if excludeCamera && offer.cameraRecording { return false }
            let height = offer.videoHeight
            return height <= maximum && (minimum == 0 || height >= minimum)
        }
    }
    func preferred(_ offers: [StreamOffer]) -> StreamOffer? {
        let candidates = offers.filter(\.automaticallyPlayable)
        // Rust ranking still breaks ties within the same resolution.
        let bestHeight = candidates.map(\.videoHeight).max()
        return candidates.first { $0.videoHeight == bestHeight }
    }
    func preferredContinuation(_ offers: [StreamOffer], previous: StreamSourceIdentity?) -> StreamOffer? {
        if keepSourceNextEpisode, let previous, let matched = preferred(offers.filter { previous.matches($0) }) { return matched }
        return preferred(offers)
    }
    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        filterLevel = UserDefaults.standard.string(forKey: "streamFilterLevel") ?? "strict"
        addonOrder = UserDefaults.standard.object(forKey: "streams.addonOrder") as? Bool ?? true
        automatic = UserDefaults.standard.object(forKey: "streams.automatic") as? Bool ?? true
        keepSourceNextEpisode = UserDefaults.standard.object(forKey: "keepSourceNextEpisode") as? Bool ?? false
        excludeCamera = UserDefaults.standard.object(forKey: "streams.excludeCamera") as? Bool ?? true
        maximum = UserDefaults.standard.object(forKey: "streams.maximum") as? Int ?? 2160
        minimum = UserDefaults.standard.object(forKey: "streams.minimum") as? Int ?? 0
        addonTimeoutSeconds = StreamSourceSettings.clamped(UserDefaults.standard.object(forKey: "streams.addonTimeoutSec") as? Int ?? StreamSourceSettings.defaultTimeoutSeconds)
        sourceMode = StreamMode(stored: UserDefaults.standard.string(forKey: "streams.mode"))
        priority = StreamPreferences.storedPriority()
        pickerLayout = UserDefaults.standard.string(forKey: "streams.pickerLayout") ?? "condensed"
        pickerShowFilename = UserDefaults.standard.object(forKey: "streams.pickerShowFilename") as? Bool ?? false
        fullStreamDescription = UserDefaults.standard.object(forKey: "streams.fullDescription") as? Bool ?? true
        pickerRefreshNextToBack = UserDefaults.standard.object(forKey: "streams.pickerRefreshNextToBack") as? Bool ?? false
    }
}

struct StreamFilterConfiguration: Sendable {
    let level: String
    let addonOrder: Bool
    /// Wait time, source mode and addon order; defaults match a fresh Desktop profile.
    var sources = StreamSourceSettings()
    func trust(_ media: Media, season: Int?, episode: Int?) -> JSONValue {
        let strict = level == "strict"
        return .object(["kind": .string(media.episodic ? "series" : "movie"), "expectedTitle": .string(media.name),
                        "expectedYear": media.releaseInfo.flatMap { Int64($0.prefix(4)) }.map(JSONValue.integer) ?? .null,
                        "releaseDate": media.released.map(JSONValue.string) ?? .null,
                        "expectedSeason": season.map { .integer(Int64($0)) } ?? .null,
                        "expectedEpisode": episode.map { .integer(Int64($0)) } ?? .null,
                        "isAnime": .bool(AnimeService.isAnime(media.id)), "strict": .bool(strict), "disabled": .bool(level == "off"),
                        "allowSeasonPacks": .bool(!strict), "allowSizeOutliers": .bool(!strict)])
    }
}

struct StreamSourceIdentity: Sendable {
    let infoHash: String?
    let bingeGroup: String?
    let addonID: String?
    let resolution: String?
    let source: String?
    init(_ offer: StreamOffer) {
        infoHash = offer.raw["infoHash"].string.flatMap { $0.isEmpty ? nil : $0 }
        bingeGroup = offer.bingeGroup
        addonID = offer.addonID.flatMap { $0.isEmpty ? nil : $0 }
        resolution = offer.raw["resolution"].string
        source = offer.raw["source"].string
    }
    func matches(_ offer: StreamOffer) -> Bool {
        let candidate = StreamSourceIdentity(offer)
        if let infoHash, let other = candidate.infoHash { return infoHash.caseInsensitiveCompare(other) == .orderedSame }
        if let bingeGroup, let other = candidate.bingeGroup { return bingeGroup == other }
        return addonID != nil && addonID == candidate.addonID && resolution == candidate.resolution && source == candidate.source
    }
}

extension StreamOffer {
    var automaticallyPlayable: Bool {
        guard let value = raw["url"].string, value.rangeOfCharacter(from: .controlCharacters) == nil,
              let url = URLComponents(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return debridVerified }
        return true
    }
    /// A torrent hash that one of the profile's debrid services confirmed as cached
    /// or in its library. Desktop never starts an unverified torrent on its own.
    var debridVerified: Bool {
        raw["infoHash"].string?.isEmpty == false && raw["cacheVerified"].objectValue.values.contains(JSONValue.bool(true))
    }
    var videoHeight: Int {
        if quality.hasPrefix("4K") { return 2160 }
        if quality.hasPrefix("1080p") { return 1080 }
        if quality == "720p" { return 720 }
        return 0
    }
    var cameraRecording: Bool {
        if quality == "ROUGH" { return true }
        let source = raw["source"].string?.lowercased() ?? ""
        if ["cam", "ts", "hdts", "tc", "telesync", "telecine", "workprint"].contains(source) { return true }
        let text = [raw["name"].string, raw["title"].string, raw["description"].string].compactMap { $0 }.joined(separator: " ")
        return text.range(of: "(?i)(?:^|[^a-z0-9])(?:hdcam|camrip|cam|hdts|telesync|telecine|tsrip|ts|tc)(?:$|[^a-z0-9])", options: .regularExpression) != nil
    }

}
