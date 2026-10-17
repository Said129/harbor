import Foundation
import Observation

@MainActor @Observable
final class StreamPreferences {
    static let shared = StreamPreferences()
    var filterLevel = UserDefaults.standard.string(forKey: "streamFilterLevel") ?? "strict" {
        didSet { UserDefaults.standard.set(filterLevel, forKey: "streamFilterLevel") }
    }
    var addonOrder = UserDefaults.standard.object(forKey: "streams.addonOrder") as? Bool ?? true {
        didSet { UserDefaults.standard.set(addonOrder, forKey: "streams.addonOrder") }
    }
    func configuration() -> StreamFilterConfiguration { .init(level: filterLevel, addonOrder: addonOrder) }
    var automatic = UserDefaults.standard.object(forKey: "streams.automatic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "streams.automatic") }
    }
    var keepSourceNextEpisode = UserDefaults.standard.object(forKey: "keepSourceNextEpisode") as? Bool ?? false {
        didSet { UserDefaults.standard.set(keepSourceNextEpisode, forKey: "keepSourceNextEpisode") }
    }
    var excludeCamera = UserDefaults.standard.object(forKey: "streams.excludeCamera") as? Bool ?? true {
        didSet { UserDefaults.standard.set(excludeCamera, forKey: "streams.excludeCamera") }
    }
    var maximum = UserDefaults.standard.object(forKey: "streams.maximum") as? Int ?? 2160 {
        didSet { UserDefaults.standard.set(maximum, forKey: "streams.maximum") }
    }
    var minimum = UserDefaults.standard.object(forKey: "streams.minimum") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(minimum, forKey: "streams.minimum") }
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
}

struct StreamFilterConfiguration: Sendable {
    let level: String
    let addonOrder: Bool
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
              let host = url.host, !host.isEmpty else { return false }
        return true
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
