import Foundation

/// Desktop's "Auto-skip stalled streams" (`views/player.tsx`, `lib/player/stall-wait.ts`).
/// Desktop watches only the first load of an automatically started source: when playback has
/// not begun by the end of the wait, the source is set aside and the next candidate is opened.
/// Buffering after playback has begun is left alone, as on Desktop.
enum StreamStallPolicy {
    /// Desktop's "How long to wait first" choices (`STALL_WAIT_OPTIONS`).
    static let waitChoices = [10, 20, 30, 45, 60]
    static let minimumWaitSeconds = 5
    static let maximumWaitSeconds = 120
    static let fallbackWaitSeconds = 10
    /// Sources one automatic start may try; the same limit as `DetailModel.autoAttemptLimit`.
    static let maximumAttempts = 8

    enum Decision: Equatable, Sendable {
        /// Keep waiting for the source to start.
        case wait
        /// Set this source aside and open the next candidate.
        case switchStream
        /// Nothing to do: playback started, the source ended or failed, or the feature is off.
        case keep
    }

    /// What the player reports about the source being started (Desktop's `hasPlaybackStartedForStallCheck` inputs).
    struct Sample: Equatable, Sendable {
        var paused = false
        var position: Double = 0
        var videoWidth = 0
        var videoHeight = 0
        var ended = false
        var failed = false
        var live = false
    }

    struct Input: Equatable, Sendable {
        /// Seconds since this source was opened.
        var elapsedSeconds: Double
        var sample: Sample
        /// Whether the automatic start chose this source (Desktop's `src.autoFired`).
        var automatic: Bool
        /// Sources tried so far, including this one.
        var attempts: Int
    }

    /// Desktop clamps the stored wait to 5...120 seconds and falls back to 10 when it is missing.
    static func waitSeconds(_ stored: Int?) -> Int {
        guard let stored else { return fallbackWaitSeconds }
        return min(maximumWaitSeconds, max(minimumWaitSeconds, stored))
    }

    /// Desktop's `hasPlaybackStartedForStallCheck`: paused, moved, or showing video counts as started.
    static func started(_ sample: Sample) -> Bool {
        sample.paused || sample.position > 0 || (sample.videoWidth > 0 && sample.videoHeight > 0)
    }

    /// The timer rule from `player.tsx`: only an automatic, non-live source that has not started,
    /// has not ended or failed, and is under the attempt limit can be switched.
    static func decide(enabled: Bool, waitSeconds: Int, input: Input) -> Decision {
        guard enabled, input.automatic, !input.sample.live else { return .keep }
        guard !started(input.sample), !input.sample.ended, !input.sample.failed else { return .keep }
        guard input.attempts < maximumAttempts else { return .keep }
        return input.elapsedSeconds >= Double(waitSeconds) ? .switchStream : .wait
    }

    /// Desktop's dedupe key (`use-auto-candidates.ts`): the URL, else the info hash, else the addon and title.
    static func identity(_ offer: StreamOffer) -> String {
        if let url = offer.raw["url"].string { return url }
        if let hash = offer.raw["infoHash"].string { return hash }
        return (offer.addonID ?? "") + ":" + offer.title
    }

    /// The next source to open after a stall. It uses the ranking of `StreamPreferences.preferred` (highest
    /// resolution, then list order) and skips sources already tried and any copy of one of them.
    static func nextCandidate(_ offers: [StreamOffer], tried: Set<Int>) -> StreamOffer? {
        let triedIdentities = Set(offers.filter { tried.contains($0.id) }.map(identity))
        let fresh = offers.filter { offer in
            !tried.contains(offer.id) && !triedIdentities.contains(identity(offer)) && offer.automaticallyPlayable
        }
        guard let best = fresh.map(\.videoHeight).max() else { return nil }
        return fresh.first { $0.videoHeight == best }
    }
}
