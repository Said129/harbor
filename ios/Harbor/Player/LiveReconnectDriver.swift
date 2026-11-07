import SwiftUI

/// Desktop's live reconnect (`use-auto-retry.ts`): when a live channel's player reports an error, the channel is reopened
/// once, or twice after it has played, with Desktop's delays. Only live sessions (`iptv:` ids) run it. A modifier of its
/// own keeps the player's long modifier chain quick to type-check.
struct LiveReconnectDriver: ViewModifier {
    let state: PlayerState
    let session: PlaybackSession

    func body(content: Content) -> some View {
        content.task(id: session.source.url) { await watch() }
    }

    @MainActor private func watch() async {
        guard session.target.id.hasPrefix("iptv:") else { return }
        let started = Date()
        let controller = LiveReconnectController(
            now: { Date().timeIntervalSince(started) },
            isStalled: { state.error != nil },
            reopen: { state.controller?.replay() })
        while !Task.isCancelled {
            controller.noteProgress(positionSeconds: state.position, bufferedSeconds: 0)
            controller.poll()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
