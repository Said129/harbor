import SwiftUI

enum PlayerSettingsPage: String, Identifiable {
    case options, playback, video, audio, subtitles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .options: "Opciones del reproductor"
        case .playback: "Reproducción"
        case .video: "Vídeo"
        case .audio: "Audio"
        case .subtitles: "Subtítulos"
        }
    }
}

struct PlayerSettingsView: View {
    let page: PlayerSettingsPage
    var state: PlayerState? = nil
    @Bindable var preferences = PlaybackPreferences.shared
    @AppStorage("mpvHwdec") private var hardwareDecoding = HardwareDecoding.auto
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("resumePrompt") private var resumePrompt = false

    private let languages = [("Automático", ""), ("Español", "spa,es"), ("Inglés", "eng,en"), ("Japonés", "jpn,ja"), ("Francés", "fra,fre,fr"), ("Alemán", "deu,ger,de"), ("Italiano", "ita,it"), ("Portugués", "por,pt")]
    var body: some View {
        Form {
            switch page {
            case .options:
                Section {
                    ForEach([PlayerSettingsPage.playback, .video, .audio, .subtitles]) { destination in
                        NavigationLink(destination.title) { PlayerSettingsView(page: destination, state: state) }
                    }
                }
                chapters
            case .playback:
                chapters
                Section("Controles") {
                    Toggle("Ocultar controles automáticamente", isOn: $preferences.options.autoHideControls)
                    Toggle("Mantener la pantalla encendida", isOn: $preferences.options.keepScreenAwake)
                    Picker("Salto al retroceder", selection: $preferences.options.seekBackSeconds) {
                        ForEach([5.0, 10, 15, 30, 60], id: \.self) { Text("\(Int($0)) segundos").tag($0) }
                    }
                    Picker("Salto al avanzar", selection: $preferences.options.seekForwardSeconds) {
                        ForEach([5.0, 10, 15, 30, 60], id: \.self) { Text("\(Int($0)) segundos").tag($0) }
                    }
                    Picker("Velocidad inicial", selection: $preferences.options.speed) {
                        ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { Text("\($0.formatted())×").tag($0) }
                    }
                }
                Section("Reanudación") {
                    Toggle("Reanudar la reproducción", isOn: $resumePlayback)
                    Toggle("Preguntar antes de reanudar", isOn: $resumePrompt).disabled(!resumePlayback)
                }
            case .video:
                Section("Reproductor") {
                    Picker("Decodificación de vídeo", selection: $hardwareDecoding) {
                        ForEach(HardwareDecoding.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("settings-hwdec")
                    Picker("Formato de imagen", selection: $preferences.options.fit) {
                        ForEach(VideoFit.allCases) { Text($0.title).tag($0) }
                    }
                    if preferences.options.fit == .zoom { dial("Zoom", value: $preferences.options.zoom, range: 0...1, step: 0.05) }
                }
                Section("Ajustes de imagen") {
                    dial("Brillo", value: $preferences.options.brightness, range: -50...50)
                    dial("Contraste", value: $preferences.options.contrast, range: -50...50)
                    dial("Saturación", value: $preferences.options.saturation, range: -50...50)
                    dial("Gamma", value: $preferences.options.gamma, range: -50...50)
                    dial("Nitidez", value: $preferences.options.sharpen, range: 0...2, step: 0.05)
                    Button("Aclarar películas oscuras") { preferences.options.gamma = 12; preferences.options.brightness = 4 }
                    Button("Colores más vivos") { preferences.options.saturation = 15; preferences.options.contrast = 8 }
                    Button("Descanso visual") { preferences.options.brightness = -4; preferences.options.gamma = -6; preferences.options.saturation = -5 }
                    Button("Restablecer imagen") {
                        preferences.options.brightness = 0; preferences.options.contrast = 0
                        preferences.options.saturation = 0; preferences.options.gamma = 0; preferences.options.sharpen = 0; preferences.options.zoom = 0; preferences.options.fit = .original
                    }
                }
            case .audio:
                if let state {
                    Section("Pistas y volumen") {
                        tracks(state, type: "audio", property: "aid")
                        Toggle("Silenciar", isOn: Binding(get: { state.muted }, set: { state.controller?.set("mute", $0 ? "yes" : "no") }))
                        dial("Volumen", value: Binding(get: { state.volume }, set: { preferences.options.volume = $0 }), range: 0...100, suffix: "%")
                    }
                }
                Section("Idioma y salida") {
                    languagePicker("Idioma preferido", value: $preferences.options.audioLanguage, defaults: "eng,jpn", defaultTitle: "Inglés, japonés")
                    Toggle("Mezclar sonido multicanal a estéreo", isOn: $preferences.options.stereo)
                }
                Section("Sincronización") {
                    dial("Retraso del audio", value: $preferences.options.audioDelay, range: -10...10, step: 0.1, suffix: " s")
                    Button("Restablecer retraso") { preferences.options.audioDelay = 0 }
                }
            case .subtitles:
                if let state {
                    Section("Pistas") {
                        Button("Desactivar") { state.controller?.set("sid", "no") }
                        tracks(state, type: "sub", property: "sid")
                    }
                }
                Section("Selección") {
                    languagePicker("Idioma preferido", value: $preferences.options.subtitleLanguage, defaults: "eng", defaultTitle: "Inglés")
                    Toggle("Desactivar subtítulos por defecto", isOn: $preferences.options.subtitlesOff)
                }
                Section("Sincronización") {
                    dial("Retraso de subtítulos", value: $preferences.options.subtitleDelay, range: -10...10, step: 0.1, suffix: " s")
                }
                Section("Estilo") {
                    Text("Vista previa de subtítulos").font(.system(size: min(40, preferences.options.subtitleSize), weight: preferences.options.subtitleBold ? .bold : .regular))
                        .foregroundStyle(Color(hex: preferences.options.subtitleColor)).opacity(preferences.options.subtitleOpacity)
                        .padding(8).frame(maxWidth: .infinity).background(.black).accessibilityIdentifier("settings-subtitle-preview")
                    Picker("Fondo", selection: $preferences.options.subtitleStyle) {
                        Text("Sombra").tag("shadow"); Text("Contorno").tag("outline"); Text("Barra negra").tag("box")
                    }
                    Picker("Subtítulos con estilo ASS", selection: $preferences.options.subtitleASS) {
                        Text("Original").tag("no"); Text("Redimensionar").tag("scale"); Text("Mi estilo").tag("force")
                    }
                    Toggle("Texto en negrita", isOn: $preferences.options.subtitleBold)
                    dial("Tamaño", value: $preferences.options.subtitleSize, range: 16...120)
                    dial("Opacidad", value: $preferences.options.subtitleOpacity, range: 0.2...1, step: 0.05)
                    dial("Altura desde el borde inferior", value: Binding(get: { 100 - preferences.options.subtitlePosition }, set: { preferences.options.subtitlePosition = 100 - $0 }), range: 0...100, suffix: "%")
                    Picker("Alineación", selection: $preferences.options.subtitleAlignment) {
                        Text("Izquierda").tag("left"); Text("Centro").tag("center"); Text("Derecha").tag("right")
                    }
                    Picker("Color del texto", selection: $preferences.options.subtitleColor) {
                        Text("Blanco").tag("#FFFFFF"); Text("Amarillo").tag("#FFFF00"); Text("Verde").tag("#00FF00")
                    }
                    if preferences.options.subtitleStyle == "outline" {
                        dial("Grosor del contorno", value: $preferences.options.borderSize, range: 1...6)
                        Picker("Color del contorno", selection: $preferences.options.borderColor) {
                            Text("Negro").tag("#000000"); Text("Blanco").tag("#FFFFFF")
                        }
                    }
                    if preferences.options.subtitleStyle == "box" { dial("Opacidad del fondo", value: $preferences.options.boxOpacity, range: 0.2...1, step: 0.05) }
                    Button("Restablecer estilo de subtítulos") {
                        let original = PlaybackOptions()
                        preferences.options.subtitleSize = original.subtitleSize; preferences.options.subtitlePosition = original.subtitlePosition
                        preferences.options.subtitleBold = false; preferences.options.subtitleStyle = original.subtitleStyle
                        preferences.options.subtitleASS = original.subtitleASS; preferences.options.subtitleAlignment = original.subtitleAlignment
                        preferences.options.subtitleColor = original.subtitleColor; preferences.options.borderColor = original.borderColor
                        preferences.options.borderSize = original.borderSize; preferences.options.boxOpacity = original.boxOpacity
                        preferences.options.subtitleOpacity = original.subtitleOpacity; preferences.options.subtitleDelay = 0
                    }
                }
            }
        }.navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var chapters: some View {
        if let state, !state.chapters.isEmpty {
            Section("Capítulos") {
                ForEach(state.chapters) { chapter in
                    Button(chapter.title) { state.controller?.run(["seek", String(chapter.time), "absolute+exact"]) }
                }
            }
        }
    }
    private func tracks(_ state: PlayerState, type: String, property: String) -> some View {
        ForEach(state.tracks.filter { $0.type == type }) { track in
            Button { state.controller?.set(property, String(track.id)) } label: {
                HStack { Text(track.label); Spacer(); if track.selected { Image(systemName: "checkmark") } }
            }
        }
    }

    private func dial(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, suffix: String = "") -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + suffix).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
    private func languagePicker(_ title: String, value: Binding<String>, defaults: String, defaultTitle: String) -> some View {
        Picker(title, selection: value) {
            if !languages.contains(where: { $0.1 == defaults }) { Text(defaultTitle).tag(defaults) }
            ForEach(languages.filter { $0.1 == defaults || !$0.1.split(separator: ",").contains(Substring(defaults)) }, id: \.1) { Text($0.0).tag($0.1) }
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
