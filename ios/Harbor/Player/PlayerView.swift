import SwiftUI

private struct PlayerSurface: UIViewControllerRepresentable {
    let source: PlaybackSource
    let state: PlayerState
    func makeUIViewController(context: Context) -> MPVController { MPVController(source: source, state: state) }
    func updateUIViewController(_ controller: MPVController, context: Context) {}
    static func dismantleUIViewController(_ controller: MPVController, coordinator: ()) { controller.close() }
}

struct PlayerView: View {
    let source: PlaybackSource
    let title: String
    @State private var state = PlayerState()
    @State private var seek: Double = 0
    @State private var editingSeek = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(source: source, state: state).ignoresSafeArea()
            VStack {
                HStack { Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }; Text(title).lineLimit(1); Spacer(); trackMenu("audio", title: "Audio", property: "aid"); trackMenu("sub", title: "Subtítulos", property: "sid") }.padding().background(.black.opacity(0.6))
                Spacer()
                if state.buffering || !state.loaded && state.error == nil { ProgressView().tint(.white) }
                if let error = state.error { Text(error).padding().background(.black.opacity(0.8)) }
                Spacer()
                VStack {
                    Slider(value: Binding(get: { editingSeek ? seek : min(state.position, max(1, state.duration)) }, set: { seek = $0 }), in: 0...max(1, state.duration), onEditingChanged: { editing in
                        editingSeek = editing
                        if !editing { state.controller?.run(["seek", String(seek), "absolute+exact"]) }
                    }).disabled(state.duration <= 0)
                    HStack {
                        Text(time(state.position)).monospacedDigit()
                        Spacer()
                        Button { state.controller?.run(["seek", "-10", "relative"]) } label: { Image(systemName: "gobackward.10") }.frame(width: 44, height: 44)
                        Button { state.controller?.run(["cycle", "pause"]) } label: { Image(systemName: state.paused ? "play.fill" : "pause.fill").font(.title) }.frame(width: 56, height: 44)
                        Button { state.controller?.run(["seek", "10", "relative"]) } label: { Image(systemName: "goforward.10") }.frame(width: 44, height: 44)
                        Spacer()
                        Menu("Velocidad") { ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in Button("\(speed.formatted())×") { state.controller?.set("speed", String(speed)) } } }
                        Text(time(state.duration)).monospacedDigit()
                    }.font(.caption)
                }.padding().background(.black.opacity(0.7))
            }.foregroundStyle(.white)
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
        guard value.isFinite && value >= 0 else { return "0:00" }
        let seconds = Int(value)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
