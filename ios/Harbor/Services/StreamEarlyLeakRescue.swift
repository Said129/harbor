import Foundation

/// Desktop's corroborated early-leak rescue (`rescueCorroboratedLeaks` and `finalizeWithRescue` in
/// `src/lib/streams/pipeline.ts`). The trust stage rejects cam-like and stub-like copies of a recent
/// release. When several of those high-resolution rejections look like one another, they come back.
/// This file only decides which rejections are restored. Re-ranking them is the caller's job.
enum StreamEarlyLeakRescue {
    /// Desktop's GIB.
    static let gib = 1_073_741_824.0

    /// Desktop's RESCUABLE_REASON_RX, `/^(fresh-cinema-fake|new-release-stub)/`.
    static func isRescuableReason(_ reason: String) -> Bool {
        reason.hasPrefix("fresh-cinema-fake") || reason.hasPrefix("new-release-stub")
    }

    /// Desktop's minSize: 2.5 GiB for 4K, 1 GiB for everything else.
    static func minimumSize(resolution: String) -> Double {
        resolution == "4K" ? 2.5 * gib : gib
    }

    /// Desktop's window `days > -90 && days < 60`, where days is (now - release date) in days.
    static func isInWindow(releaseDate: Date, now: Date) -> Bool {
        let days = now.timeIntervalSince(releaseDate) / 86_400
        return days > -90 && days < 60
    }

    /// `new Date(text)` for the release dates the app stores: an ISO date (UTC midnight) or an ISO timestamp.
    static func releaseDate(_ text: String?) -> Date? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: value) { return date }
        internet.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = internet.date(from: value) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: value)
    }

    /// Desktop's rescueCorroboratedLeaks. `rejected` holds the ranker's `{stream, reason}` entries.
    /// The result is the set of their indices to restore. Desktop returns nothing when the release
    /// date is missing or invalid, which is the `releaseDate: nil` case here.
    static func rescuedIndices(_ rejected: [JSONValue], releaseDate: Date?, now: Date) -> Set<Int> {
        guard let releaseDate, isInWindow(releaseDate: releaseDate, now: now) else { return [] }
        var clusters: [String: [(index: Int, group: String?)]] = [:]
        for (index, entry) in rejected.enumerated() {
            guard isRescuableReason(entry["reason"].string ?? "") else { continue }
            let stream = entry["stream"]
            guard let resolution = stream["resolution"].string, resolution == "1080p" || resolution == "4K" else { continue }
            guard let size = number(stream["size"]), size >= minimumSize(resolution: resolution) else { continue }
            // Desktop: Math.round(size / GIB * 4) / 4, a quarter-GiB bucket.
            let bucket = (size / gib * 4).rounded(.toNearestOrAwayFromZero) / 4
            clusters[resolution + "|" + String(bucket), default: []].append((index: index, group: group(stream)))
        }
        var rescued = Set<Int>()
        for members in clusters.values {
            let groups = Set(members.compactMap { $0.group })
            // A cluster is corroborated by three or more streams, or by two different release groups.
            if members.count >= 3 || groups.count >= 2 {
                for member in members { rescued.insert(member.index) }
            }
        }
        return rescued
    }

    private static func group(_ stream: JSONValue) -> String? {
        guard let value = stream["releaseGroupNormalized"].string, !value.isEmpty else { return nil }
        return value
    }

    private static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .integer(let number): Double(number)
        case .unsigned(let number): Double(number)
        case .number(let number): number
        default: nil
        }
    }
}
