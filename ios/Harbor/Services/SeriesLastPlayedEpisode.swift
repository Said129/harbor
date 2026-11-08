import Foundation

/// Desktop `lastPlayedEpisode` (src/lib/resume.ts): the episode of one series with the newest resume
/// entry. Resume keys are `<id>|s<season>e<episode>` (the bridge's `resumeKey`).
enum SeriesLastPlayedEpisode {
    struct Hit: Equatable, Sendable {
        let season: Int
        let episode: Int
        let entry: ResumeEntry
    }

    static func find(seriesID: String, entries: [String: ResumeEntry]) -> Hit? {
        let prefix = seriesID + "|s"
        var best: Hit?
        // Sorted keys make a tie on the timestamp resolve the same way every time.
        for key in entries.keys.sorted() {
            guard key.hasPrefix(prefix), let entry = entries[key] else { continue }
            let parts = key.dropFirst(prefix.count).split(separator: "e", omittingEmptySubsequences: false)
            guard parts.count == 2, let season = digits(parts[0]), let episode = digits(parts[1]),
                  season >= 1, episode >= 1 else { continue }
            // Desktop keeps the first entry with the newest timestamp, so a tie never replaces it.
            if let current = best, entry.t <= current.entry.t { continue }
            best = Hit(season: season, episode: episode, entry: entry)
        }
        return best
    }

    private static func digits(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}
