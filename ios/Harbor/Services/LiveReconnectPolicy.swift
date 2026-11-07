import Foundation
import Observation

/// Desktop's live auto-reconnect rules from `src/views/player/hooks/use-auto-retry.ts`:
/// lines 135-137 (`livePlayedRef`), 139-162 (the reconnect effect), 142 (`maxAttempts`), 159 (the delay).
/// Desktop reconnects a live channel only when the player reports an error code, and it resets the
/// counter only when the channel URL changes. This type holds the numbers and the decision, with no timers.
struct LiveReconnectPolicy: Equatable, Sendable {
    /// Wait before reconnecting when the channel has not produced progress yet (Desktop: 1500 ms).
    let delayBeforeProgressMs: Int
    /// Wait before reconnecting once the channel has played (Desktop: 4000 ms).
    let delayAfterProgressMs: Int
    /// Reconnects allowed when the channel has never played (Desktop: 1).
    let maxAttemptsBeforeProgress: Int
    /// Reconnects allowed after the channel has played (Desktop: 2).
    let maxAttemptsAfterProgress: Int

    static let desktop = LiveReconnectPolicy(
        delayBeforeProgressMs: 1_500,
        delayAfterProgressMs: 4_000,
        maxAttemptsBeforeProgress: 1,
        maxAttemptsAfterProgress: 2
    )

    /// Desktop marks the channel as played when position or buffered time is above 0.5 s (`use-auto-retry.ts` lines 90, 136).
    static func hasProgress(positionSeconds: Double, bufferedSeconds: Double) -> Bool {
        positionSeconds > 0.5 || bufferedSeconds > 0.5
    }

    enum Decision: Equatable, Sendable {
        /// Reconnect number `attempt` (1-based) after `delayMs`.
        case reconnect(attempt: Int, delayMs: Int)
        /// No more reconnects for this channel; the error stays visible.
        case giveUp
    }

    func maxAttempts(livePlayed: Bool) -> Int {
        livePlayed ? maxAttemptsAfterProgress : maxAttemptsBeforeProgress
    }

    func delayMs(livePlayed: Bool) -> Int {
        livePlayed ? delayAfterProgressMs : delayBeforeProgressMs
    }

    /// `attemptsMade` counts reconnects already fired since the channel URL last changed.
    func decision(attemptsMade: Int, livePlayed: Bool) -> Decision {
        guard attemptsMade < maxAttempts(livePlayed: livePlayed) else { return .giveUp }
        return .reconnect(attempt: attemptsMade + 1, delayMs: delayMs(livePlayed: livePlayed))
    }
}

/// Drives `LiveReconnectPolicy` for one live channel. It never imports the player: the player supplies
/// `isStalled` (true while the player reports an error for the live stream) and `reopen` (reloads the same URL).
/// Call `poll()` about once per second and `reset()` whenever the channel URL changes.
@MainActor @Observable
final class LiveReconnectController {
    private(set) var attemptsMade = 0
    private(set) var livePlayed = false
    /// Clock value (seconds, same scale as `now`) when the pending reconnect fires; nil when none is pending.
    private(set) var dueAt: TimeInterval?
    private(set) var gaveUp = false

    @ObservationIgnored private let policy: LiveReconnectPolicy
    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    @ObservationIgnored private let isStalled: @MainActor () -> Bool
    @ObservationIgnored private let reopen: @MainActor () -> Void
    /// A drop is handled once; the next one is accepted only after `isStalled` has read false again.
    /// Desktop's effect re-runs only when the error code changes, so a persistent error does not re-trigger.
    @ObservationIgnored private var armed = true

    init(
        policy: LiveReconnectPolicy = .desktop,
        now: @escaping @MainActor () -> TimeInterval,
        isStalled: @escaping @MainActor () -> Bool,
        reopen: @escaping @MainActor () -> Void
    ) {
        self.policy = policy
        self.now = now
        self.isStalled = isStalled
        self.reopen = reopen
    }

    /// Call from the player's progress updates with the current position and buffered seconds.
    func noteProgress(positionSeconds: Double, bufferedSeconds: Double) {
        if LiveReconnectPolicy.hasProgress(positionSeconds: positionSeconds, bufferedSeconds: bufferedSeconds) {
            livePlayed = true
        }
    }

    /// Call about once per second. Schedules one reconnect per drop and fires it when due.
    func poll() {
        guard isStalled() else {
            // Desktop clears its timer when the error code goes back to null.
            armed = true
            dueAt = nil
            return
        }
        if let pending = dueAt {
            if now() >= pending { fire() }
            return
        }
        guard armed else { return }
        armed = false
        switch policy.decision(attemptsMade: attemptsMade, livePlayed: livePlayed) {
        case .giveUp:
            gaveUp = true
        case .reconnect(_, let delayMs):
            dueAt = now() + Double(delayMs) / 1_000
        }
    }

    /// Clears the counter and the played flag. Desktop does this only when the channel URL changes.
    func reset() {
        attemptsMade = 0
        livePlayed = false
        dueAt = nil
        gaveUp = false
        armed = true
    }

    private func fire() {
        dueAt = nil
        attemptsMade += 1
        reopen()
    }
}
