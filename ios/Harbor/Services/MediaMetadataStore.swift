import CryptoKit
import Foundation

actor MediaMetadataStore {
    private struct Entry { let media: Media; let expires: Date }
    private var entries: [String: Entry] = [:]
    private var pending: [String: Task<Media, Error>] = [:]

    // The digest includes account, configured transports and metadata settings.
    // Private addon URLs and credentials never appear in logs or disk caches.
    static func key(_ media: Media, owner: String, addons: [Addon], configuration: MetadataConfiguration) throws -> String {
        let value: JSONValue = .object(["media": .string(media.identity), "origin": try .encoded(media.addonOrigin), "owner": .string(owner), "addons": try .encoded(addons), "tmdb": .string(configuration.tmdbKey), "language": .string(configuration.language), "region": .string(configuration.region), "translate": .bool(configuration.translateTitles)])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    func value(for key: String, load: @escaping @Sendable () async throws -> Media) async throws -> Media {
        if let cached = entries[key], cached.expires > Date() { return cached.media }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await load() }
        pending[key] = task
        defer { pending[key] = nil }
        let media = try await task.value
        if entries.count >= 64, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key { entries[oldest] = nil }
        entries[key] = Entry(media: media, expires: Date().addingTimeInterval(300))
        return media
    }
}
