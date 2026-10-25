import Foundation

/// This account section merges individual media keys. Layout documents instead
/// replace the complete value and must never use this clock-based rule.
struct DesktopWatchedBy: Equatable, Sendable {
    struct Entry: Equatable, Sendable { let profile: String; let timestamp: Double }
    static let maximum = 300
    private(set) var entries: [String: Entry]

    init(_ raw: JSONValue) {
        var values: [String: Entry] = [:]
        for (id, value) in raw.objectValue {
            if let profile = value.string, !profile.isEmpty { values[id] = Entry(profile: profile, timestamp: 0) }
            else if let profile = value["p"].string, !profile.isEmpty {
                values[id] = Entry(profile: profile, timestamp: value["t"].numericValue ?? 0)
            }
        }
        entries = values
    }
    private init(_ entries: [String: Entry]) { self.entries = entries }
    var raw: JSONValue {
        .object(entries.mapValues { .object(["p": .string($0.profile), "t": .number($0.timestamp)]) })
    }
    func capped() -> Self {
        guard entries.count > Self.maximum else { return self }
        let keys = entries.keys.sorted { left, right in
            let a = entries[left]!.timestamp, b = entries[right]!.timestamp
            // JSON objects have no portable ordering. A deterministic tie keeps
            // reopening a legacy zero-clock map from rotating its retained keys.
            return a == b ? left < right : a > b
        }
        return Self(Dictionary(uniqueKeysWithValues: keys.prefix(Self.maximum).map { ($0, entries[$0]!) }))
    }
    func merging(_ incoming: Self) -> Self {
        var next = entries
        for (id, entry) in incoming.entries {
            if next[id] == nil || entry.timestamp > next[id]!.timestamp { next[id] = entry }
        }
        return Self(next).capped()
    }
    func recording(mediaID: String, profileID: String, at timestamp: Double) throws -> Self {
        guard !mediaID.isEmpty, !profileID.isEmpty, timestamp.isFinite, timestamp >= 0 else { throw HarborError(code: "watched-by-record") }
        // Desktop does not refresh the clock when the same person resumes.
        guard entries[mediaID]?.profile != profileID else { return self }
        var next = entries; next[mediaID] = Entry(profile: profileID, timestamp: timestamp)
        return Self(next).capped()
    }
    func watcher(mediaID: String, fallbackID: String? = nil, activeID: String?, profiles: [DeviceHouseholdProfile]) -> DeviceHouseholdProfile? {
        let id = entries[mediaID]?.profile ?? fallbackID.flatMap { entries[$0]?.profile }
        guard let id, id != activeID else { return nil }
        // The Desktop wire contains device profile IDs. Unknown remote IDs are
        // kept for round trips, never guessed to be the household's primary.
        return profiles.first { $0.id == id && !$0.desktop.isKid }
    }
}
