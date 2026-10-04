import SwiftUI

private struct PlayerSurface: UIViewControllerRepresentable {
    let source: PlaybackSource
    let startMs: Double
    let state: PlayerState
    func makeUIViewController(context: Context) -> MPVController { MPVController(source: source, state: state, startMs: startMs) }
    func updateUIViewController(_ controller: MPVController, context: Context) {}
    static func dismantleUIViewController(_ controller: MPVController, coordinator: ()) { controller.close() }
}

struct PlayerView: View {
    let session: PlaybackSession
    let resume: ResumeStore
    let title: String
    @State private var state = PlayerState()
    @State private var seek: Double = 0
    @State private var editingSeek = false
    @State private var progressError: String?
    @State private var lastSavedMs: Double = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(source: session.source, startMs: session.startMs, state: state).ignoresSafeArea()
            VStack {
                HStack { Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel("Cerrar reproductor").accessibilityIdentifier("player-close"); Text(title).lineLimit(1); Spacer(); trackMenu("audio", title: "Audio", property: "aid"); trackMenu("sub", title: "Subtítulos", property: "sid") }.padding().background(.black.opacity(0.6))
                Spacer()
                if (state.buffering || !state.loaded) && !state.ended && state.error == nil { ProgressView().tint(.white) }
                if state.ended && state.error == nil { Text("La reproducción ha terminado.").padding().background(.black.opacity(0.6)) }
                if let error = state.error { Text(error).padding().background(.black.opacity(0.8)).accessibilityIdentifier("player-error") }
                if let error = progressError ?? session.storageWarning { Text(error).font(.caption).padding().background(.black.opacity(0.8)) }
                Spacer()
                VStack {
                    Slider(value: Binding(get: { editingSeek ? seek : min(state.position, max(1, state.duration)) }, set: { seek = $0 }), in: 0...max(1, state.duration), onEditingChanged: { editing in
                        editingSeek = editing
                        if !editing { state.controller?.run(["seek", String(seek), "absolute+exact"]) }
                    }).disabled(state.duration <= 0 || !state.loaded)
                    HStack {
                        Text(time(state.position)).monospacedDigit().accessibilityLabel("Tiempo reproducido").accessibilityIdentifier("player-position")
                        Spacer()
                        Button { state.controller?.run(["seek", "-10", "relative"]) } label: { Image(systemName: "gobackward.10") }.frame(width: 44, height: 44)
                        Button {
                            if state.ended { state.controller?.replay() }
                            else { state.controller?.run(["cycle", "pause"]) }
                        } label: { Image(systemName: state.ended ? "arrow.counterclockwise" : state.paused ? "play.fill" : "pause.fill").font(.title) }.frame(width: 56, height: 44)
                        Button { state.controller?.run(["seek", "10", "relative"]) } label: { Image(systemName: "goforward.10") }.frame(width: 44, height: 44)
                        Spacer()
                        Menu("Velocidad") { ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in Button("\(speed.formatted())×") { state.controller?.set("speed", String(speed)) } } }
                        Text(time(state.duration)).monospacedDigit()
                    }.font(.caption)
                }.padding().background(.black.opacity(0.7))
            }.foregroundStyle(.white)
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) }
                catch { return }
                if state.loaded && !state.paused { await checkpoint(exiting: false) }
            }
        }
        .onChange(of: state.paused) { _, paused in if paused { saveCheckpoint(exiting: false) } }
        .onChange(of: state.ended) { _, ended in if ended { saveCheckpoint(exiting: false) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveCheckpoint(exiting: false) } }
        .onDisappear { saveCheckpoint(exiting: true) }
    }

    @MainActor private func snapshot(exiting: Bool) -> ResumeSnapshot? {
        guard session.progressEnabled, state.hasPosition, state.position.isFinite, state.duration.isFinite else { return nil }
        return ResumeSnapshot(positionMs: state.position * 1000, durationMs: state.duration * 1000, timestampMs: UInt64(max(0, Date().timeIntervalSince1970 * 1000)), exiting: exiting)
    }

    @MainActor private func saveCheckpoint(exiting: Bool) {
        guard let value = snapshot(exiting: exiting) else { return }
        Task { await persist(value) }
    }

    @MainActor private func checkpoint(exiting: Bool) async {
        guard let value = snapshot(exiting: exiting), abs(value.positionMs - lastSavedMs) >= 1500 else { return }
        await persist(value)
    }

    @MainActor private func persist(_ value: ResumeSnapshot) async {
        do {
            if try await resume.save(session.target, snapshot: value) {
                lastSavedMs = value.positionMs
                progressError = nil
                Diagnostics.shared.record(.progressSaved)
            }
        } catch {
            progressError = safeMessage(error)
            Diagnostics.shared.recordFailure(error)
        }
    }
    private func trackMenu(_ type: String, title: String, property: String) -> some View {
        Menu {
            if type == "sub" { Button("Desactivar") { state.controller?.set(property, "no") } }
            ForEach(state.tracks.filter { $0.type == type }) { track in
                Button { state.controller?.set(property, String(track.id)) } label: { if track.selected { Label(track.label, systemImage: "checkmark") } else { Text(track.label) } }
            }
        } label: { Image(systemName: type == "audio" ? "waveform" : "captions.bubble").frame(width: 44, height: 44).accessibilityLabel(title) }
    }
    private func time(_ value: Double) -> String {
        guard value.isFinite && value >= 0 && value < Double(Int.max) else { return "0:00" }
        let seconds = Int(value)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
