import SwiftUI

struct SubtitleTimingView: View {
    let state: PlayerState
    @State private var custom = "25"
    @State private var inputError: String?

    private var reason: String? { SubtitleTiming.unavailable(state) }
    private var disabled: Bool { reason != nil || state.subtitleChanging }
    var body: some View {
        Form {
            Section {
                choice("Sin corrección", value: 0)
                if let fps = state.videoFPS {
                    choice("Automático · igualar vídeo (\(SubtitleTiming.format(fps)))", value: fps, automatic: true)
                } else {
                    Text("Automático · igualar vídeo").foregroundStyle(.secondary)
                }
                ForEach(SubtitleTiming.presets) { preset in choice(preset.label, value: preset.value) }
            } header: {
                Label { Text("FPS del archivo de subtítulos") } icon: { Image("player-subtitle-fps").resizable().scaledToFit().frame(width: 20, height: 20) }
            } footer: {
                Text("Elige los FPS para los que se creó el archivo de subtítulos. El ajuste se restablece al cambiar de pista o de vídeo.")
            }
            Section("Personalizado") {
                TextField("FPS entre 1 y 240", text: Binding(get: { custom }, set: { custom = String($0.prefix(16)); inputError = nil }))
                    .keyboardType(.decimalPad).accessibilityIdentifier("subtitle-fps-custom")
                Button("Aplicar") {
                    guard let value = SubtitleTiming.parse(custom) else { inputError = "Introduce unos FPS entre 1 y 240."; return }
                    inputError = nil; state.controller?.applySubtitleFPS(value)
                }.disabled(disabled)
            }
            Section("Información") {
                LabeledContent("FPS del vídeo", value: SubtitleTiming.format(state.videoFPS))
                LabeledContent("FPS del subtítulo", value: (state.subtitleFPS ?? 0) == 0 ? "Sin corrección" : SubtitleTiming.format(state.subtitleFPS))
                if state.subtitleChanging { ProgressView("Aplicando cambio…") }
                if let message = inputError ?? state.subtitleIssue ?? reason { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("subtitle-fps-message") }
            }
        }.navigationTitle("FPS de subtítulos")
    }

    private func choice(_ label: String, value: Double, automatic: Bool = false) -> some View {
        Button { inputError = nil; state.controller?.applySubtitleFPS(value) } label: {
            HStack {
                Text(label)
                Spacer()
                if SubtitleTiming.matches(state.subtitleFPS, value) && (automatic || value == 0 || !SubtitleTiming.matches(state.subtitleFPS, state.videoFPS)) { Image("music-check").accessibilityHidden(true) }
            }
        }.disabled(disabled)
    }
}
