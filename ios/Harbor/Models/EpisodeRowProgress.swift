import Foundation

/// Desktop's episode row progress: `getEpisodeProgress`, `WATCHED_THRESHOLD` and `formatRelativeWatched`
/// (`src/lib/episode-progress.ts`), and the row text and bar of `series-episode-row.tsx`. Pure: the view passes the
/// saved resume entry and the library's watched flag. Desktop's manual "not watched" override is not ported yet.
enum EpisodeRowProgress {
    struct Value: Equatable, Sendable {
        let ratio: Double
        let watched: Bool
        /// The resume entry's time in milliseconds, or 0 without one.
        let startedAt: UInt64
    }

    /// Desktop's `WATCHED_THRESHOLD`.
    static let watchedThreshold = 0.85

    /// Desktop's `getEpisodeProgress`, without the manual-watched override: the position as a share of the runtime,
    /// taken from the saved percentage when there is one, and 1 when the episode is already watched.
    static func progress(entry: ResumeEntry?, runtimeMinutes: Double?, done: Bool) -> Value {
        let startedAt = entry?.t ?? 0
        let durationMs: Double = {
            guard let runtimeMinutes, runtimeMinutes.isFinite, runtimeMinutes > 0 else { return 0 }
            return runtimeMinutes * 60 * 1000
        }()
        var ratio = 0.0
        if let pct = entry?.pct, pct.isFinite, durationMs > 0 {
            ratio = min(1, max(0, pct))
        } else if durationMs > 0, let ms = entry?.ms, ms > 0 {
            ratio = min(1, ms / durationMs)
        }
        return Value(ratio: done ? 1 : ratio, watched: done || ratio >= watchedThreshold, startedAt: startedAt)
    }

    /// Desktop's `formatRelativeWatched`: the time since `startedAt` in Desktop's words. `text` translates a template
    /// with `{n}` placeholders. Empty without a time. `nowMs` is the current time in milliseconds.
    static func relativeWatched(_ startedAt: UInt64, nowMs: Double = Date().timeIntervalSince1970 * 1000,
                                text: (String, [String: String]) -> String) -> String {
        guard startedAt > 0 else { return "" }
        let diffMs = max(0, nowMs - Double(startedAt))
        let seconds = Int(diffMs / 1000)
        if seconds < 60 { return text("just now", [:]) }
        let minutes = seconds / 60
        if minutes < 60 { return text("{n}m ago", ["n": "\(minutes)"]) }
        let hours = minutes / 60
        if hours < 24 { return text("{n}h ago", ["n": "\(hours)"]) }
        let days = hours / 24
        if days == 1 { return text("yesterday", [:]) }
        if days < 7 { return text("{n} days ago", ["n": "\(days)"]) }
        if days < 14 { return text("last week", [:]) }
        if days < 30 { return text("{n} weeks ago", ["n": "\(days / 7)"]) }
        if days < 365 {
            let months = days / 30
            return months == 1 ? text("last month", [:]) : text("{n} months ago", ["n": "\(months)"])
        }
        let years = days / 365
        return years == 1 ? text("last year", [:]) : text("{n} years ago", ["n": "\(years)"])
    }

    /// Desktop's row line: "Watched {ago}" for a watched episode, otherwise "{pct}% watched · {ago}" once it is started.
    /// Nil without a time, or when the episode is neither watched nor started.
    static func statusText(_ progress: Value, ago: String, text: (String, [String: String]) -> String) -> String? {
        guard !ago.isEmpty else { return nil }
        if progress.watched { return text("Watched {ago}", ["ago": ago]) }
        guard progress.ratio > 0.01 else { return nil }
        return text("{pct}% watched", ["pct": "\(Int((progress.ratio * 100).rounded()))"]) + " · " + ago
    }

    /// The fill of the bar on the still: Desktop's `max(2, ratio * 100)` percent.
    static func barFraction(_ ratio: Double) -> Double {
        min(1, max(0.02, ratio))
    }
}
