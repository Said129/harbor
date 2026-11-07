import SwiftUI

/// The player's button for casting to a Roku or a DLNA renderer (Desktop's cast menu). AirPlay keeps its own route picker
/// beside it. The cast controller and its sheet live here so the player's own view stays small.
/// The button is hidden when a renderer could not fetch the source itself (a local file, a loopback host, or a stream that
/// needs request headers).
struct CastButton: View {
    let state: PlayerState
    let session: PlaybackSession
    @State private var controller = CastController()
    @State private var presenting = false

    private var castable: Bool { CastController.canCast(url: session.source.url, headers: session.source.headers) }
    private var casting: Bool { controller.selected != nil }

    var body: some View {
        Group {
            if castable { castControl }
        }
    }

    private var castControl: some View {
        Button { presenting = true } label: {
            Image(systemName: casting ? "tv.fill" : "tv").frame(width: 44, height: 44)
                .foregroundStyle(casting ? HarborTheme.accent : Color.white)
        }
        .accessibilityLabel(DesktopInterfaceText.value("Cast to TV or speaker"))
        .accessibilityIdentifier("player-cast-renderer")
        .sheet(isPresented: $presenting) {
            CastSheet(controller: controller, source: session.source, title: session.media?.name ?? "", startSeconds: state.position, duration: state.duration)
        }
        .onChange(of: casting) { _, isCasting in castingChanged(isCasting) }
        .onDisappear { Task { await controller.stop() } }
    }

    /// While a renderer plays, the local player stays paused; when the cast stops it resumes where the renderer ended.
    private func castingChanged(_ isCasting: Bool) {
        if isCasting {
            if !state.paused { state.controller?.togglePause() }
            return
        }
        guard let seconds = controller.takeResumePosition() else { return }
        Task { _ = try? await state.controller?.seekForResume(seconds * 1_000) }
    }
}
