import SwiftUI

/// What an automatically started source gives the player so a stall can move on to the next candidate.
struct StreamStallHandle: Sendable {
    /// Sources the automatic start has tried so far, including this one.
    let attempts: Int
    let switchSource: @MainActor @Sendable () -> Void
}

/// Desktop's "Auto-skip stalled streams" (`views/player.tsx`): when a source the automatic start chose has not begun playing
/// by the end of the wait, it is set aside and the next candidate opens. Only the first load is watched; buffering after
/// playback has begun is left alone. The rules are in `StreamStallPolicy`. A modifier of its own, like `LiveReconnectDriver`,
/// keeps the player's long modifier chain quick to type-check.
struct StreamStallDriver: ViewModifier {
    let state: PlayerState
    let session: PlaybackSession

    func body(content: Content) -> some View {
        content.task(id: session.id) { await watch() }
    }

    @MainActor private func watch() async {
        guard let stall = session.stall else { return }
        let preferences = StreamAutoSwitchPreferences.shared
        guard preferences.autoNextOnStall else { return }
        let opened = Date()
        let wait = preferences.stallWaitSeconds
        let live = session.target.id.hasPrefix("iptv:")
        while !Task.isCancelled {
            let sample = StreamStallPolicy.Sample(paused: state.paused, position: state.position, videoWidth: state.videoWidth,
                                                  videoHeight: state.videoHeight, ended: state.ended, failed: state.error != nil, live: live)
            let input = StreamStallPolicy.Input(elapsedSeconds: Date().timeIntervalSince(opened), sample: sample, automatic: true, attempts: stall.attempts)
            switch StreamStallPolicy.decide(enabled: true, waitSeconds: wait, input: input) {
            case .wait: try? await Task.sleep(for: .milliseconds(500))
            case .switchStream:
                stall.switchSource()
                return
            case .keep: return
            }
        }
    }
}
