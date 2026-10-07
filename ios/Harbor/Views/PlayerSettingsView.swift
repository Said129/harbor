import SwiftUI
import UIKit

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
    var icon: String {
        switch self {
        case .options: "nav-settings"
        case .playback: "ui-play-filled"
        case .video: "desktop-image"
        case .audio: "player-audio"
        case .subtitles: "ui-customize-subtitles"
        }
    }
}

struct PlayerSettingsView: View {
    let page: PlayerSettingsPage
    var state: PlayerState? = nil
    var changeSource: (() -> Void)? = nil
    @Bindable var preferences = PlaybackPreferences.shared
    @Bindable private var sources = StreamPreferences.shared
    @AppStorage("mpvHwdec") private var hardwareDecoding = HardwareDecoding.auto
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("resumePrompt") private var resumePrompt = false

    private let languages = [("Automático", ""), ("Español", "spa,es"), ("Inglés", "eng,en"), ("Japonés", "jpn,ja"), ("Francés", "fra,fre,fr"), ("Alemán", "deu,ger,de"), ("Italiano", "ita,it"), ("Portugués", "por,pt")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                switch page {
                case .options: optionsSettings
                case .playback: playbackSettings
                case .video: videoSettings
                case .audio: audioSettings
                case .subtitles: subtitlesSettings
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .font(HarborTheme.font(14)).buttonStyle(HarborAccountButtonStyle())
            .tint(HarborTheme.accent).accessibilityIdentifier("player-settings-scroll")
            .navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var optionsSettings: some View {
        if let changeSource {
            HarborSettingsSection("Fuente") { Button("Cambiar fuente", action: changeSource).accessibilityIdentifier("player-change-source") }
        }
        HarborSettingsSection("Reproducción") {
            ForEach([PlayerSettingsPage.playback, .video, .audio, .subtitles]) { destination in
                NavigationLink { PlayerSettingsView(page: destination, state: state) } label: {
                    HStack(spacing: 12) {
                        Image(destination.icon).resizable().scaledToFit().frame(width: 20, height: 20).foregroundStyle(.secondary)
                        Text(destination.title).font(HarborTheme.font(15, weight: .semibold))
                        Spacer()
                        Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(.secondary)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        chapters
    }

    @ViewBuilder private var playbackSettings: some View {
        chapters
        HarborSettingsSection("Fuentes y calidad") {
            HarborSettingsToggle("Elegir automáticamente la mejor calidad", isOn: $sources.automatic)
            HarborSettingsToggle("Ocultar grabaciones de cámara · CAM / TS / TC", isOn: $sources.excludeCamera)
            HarborSettingsChoice("Calidad máxima", selection: $sources.maximum, choices: [("4K", 2160), ("1080p", 1080), ("720p", 720)])
            HarborSettingsChoice("Calidad mínima", selection: $sources.minimum, choices: [("Todas", 0), ("720p", 720), ("1080p", 1080), ("4K", 2160)])
            Text("Se respetan tus filtros antes de elegir la fuente. Si ninguna los cumple, podrás ajustarlos sin reproducir un enlace excluido.").font(.caption).foregroundStyle(.secondary)
        }
        HarborSettingsSection("Controles") {
            HarborSettingsToggle("Ocultar controles automáticamente", isOn: $preferences.options.autoHideControls)
            HarborSettingsToggle("Mantener la pantalla encendida", isOn: $preferences.options.keepScreenAwake)
            HarborSettingsToggle("Reanudar tras una interrupción de audio", isOn: $preferences.options.resumeAfterInterruption)
            HarborSettingsToggle("Reanudar al volver a la app", isOn: $preferences.options.resumeOnForeground)
            HarborSettingsChoice("Salto al retroceder", selection: $preferences.options.seekBackSeconds, choices: [5.0, 10, 15, 30, 60].map { ("\(Int($0)) segundos", $0) })
            HarborSettingsChoice("Salto al avanzar", selection: $preferences.options.seekForwardSeconds, choices: [5.0, 10, 15, 30, 60].map { ("\(Int($0)) segundos", $0) })
            HarborSettingsChoice("Velocidad inicial", selection: $preferences.options.speed, choices: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map { ("\($0.formatted())×", $0) })
        }
        HarborSettingsSection("Reanudación") {
            HarborSettingsToggle("Reanudar la reproducción", isOn: $resumePlayback)
            HarborSettingsToggle("Preguntar antes de reanudar", isOn: $resumePrompt).disabled(!resumePlayback)
        }
        HarborSettingsSection("Episodios") {
            HarborSettingsToggle("Reproducir automáticamente el siguiente episodio", isOn: $preferences.options.autoPlayNextEpisode)
                .accessibilityIdentifier("settings-auto-next")
            HarborSettingsChoice("Aviso del siguiente episodio", selection: $preferences.options.nextEpisodeLeadSeconds, choices: [("Automático · Harbor", -1.0), ("Sin aviso", 0.0)] + [15.0, 30, 45, 60, 90].map { ("\(Int($0)) segundos antes", $0) })
        }
        HarborSettingsSection("Búfer", note: "Se aplica al abrir el siguiente vídeo. La memoria se adapta al iPhone; el tiempo disponible depende de la fuente y su calidad.") {
            HarborSettingsChoice("Tamaño del búfer", selection: $preferences.options.bufferSize, choices: BufferSize.allCases.map { ($0.title, $0) })
        }
    }

    @ViewBuilder private var videoSettings: some View {
        PlayerSeekBarSettings()
        HarborSettingsSection("Reproductor") {
            HarborSettingsChoice("Decodificación de vídeo", selection: $hardwareDecoding, choices: HardwareDecoding.allCases.map { ($0.title, $0) })
                .accessibilityIdentifier("settings-hwdec")
            HarborSettingsChoice("Formato de imagen", selection: $preferences.options.fit, choices: VideoFit.allCases.map { ($0.title, $0) })
                .accessibilityIdentifier("settings-video-fit")
            if preferences.options.fit == .zoom { dial("Zoom", value: $preferences.options.zoom, range: 0...1, step: 0.05) }
        }
        HarborSettingsSection("Ajustes de imagen") {
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
    }

    @ViewBuilder private var audioSettings: some View {
        if let state {
            HarborSettingsSection("Pistas y volumen") {
                tracks(state, type: "audio", property: "aid")
                HarborSettingsToggle("Silenciar", isOn: Binding(get: { state.muted }, set: { state.controller?.set("mute", $0 ? "yes" : "no") }))
                dial("Volumen", value: Binding(get: { state.volume }, set: { preferences.options.volume = $0 }), range: 0...100, suffix: "%")
            }
        }
        HarborSettingsSection("Idioma y salida") {
            preferredLanguages($preferences.options.audioLanguage)
            HarborSettingsToggle("Mezclar sonido multicanal a estéreo", isOn: $preferences.options.stereo)
        }
        HarborSettingsSection("Sincronización") {
            dial("Retraso del audio", value: $preferences.options.audioDelay, range: -10...10, step: 0.1, suffix: " s")
            Button("Restablecer retraso") { preferences.options.audioDelay = 0 }
        }
    }

    @ViewBuilder private var subtitlesSettings: some View {
        if let state {
            HarborSettingsSection("Pistas de subtítulos") {
                SubtitleTracksView(state: state, panel: true, embedded: true)
            }
            HarborSettingsSection("Temporización") {
                NavigationLink { SubtitleTimingView(state: state) } label: {
                    Label { Text("FPS de subtítulos") } icon: { Image("player-subtitle-fps").resizable().scaledToFit().frame(width: 20, height: 20) }
                }
                if state.subtitleChanging { ProgressView("Aplicando cambio…") }
            }
        }
        HarborSettingsSection("Selección") {
            preferredLanguages($preferences.options.subtitleLanguage)
            HarborSettingsChoice("Idioma de la segunda pista", selection: $preferences.options.secondarySubtitleLanguage, choices: [("No seleccionar automáticamente", "")] + languages.filter { !$0.1.isEmpty })
                .accessibilityIdentifier("settings-secondary-subtitle-language")
            HarborSettingsChoice("Posición de la segunda pista", selection: $preferences.options.secondarySubtitlePlacement, choices: [("Arriba", "top"), ("Abajo", "bottom")])
            HarborSettingsToggle("Desactivar subtítulos por defecto", isOn: $preferences.options.subtitlesOff)
            HarborSettingsToggle("Ocultar indicaciones SDH", isOn: $preferences.options.hideSDH)
        }
        HarborSettingsSection("Sincronización") {
            dial("Retraso de subtítulos", value: $preferences.options.subtitleDelay, range: -10...10, step: 0.1, suffix: " s")
        }
        HarborSettingsSection("Estilo") {
            Text("Vista previa de subtítulos").font(.custom(previewFont, size: min(40, preferences.options.subtitleSize), relativeTo: .body).weight(preferences.options.subtitleBold ? .bold : .regular))
                .kerning(preferences.options.subtitleSpacing)
                .foregroundStyle(Color(hex: preferences.options.subtitleColor)).opacity(preferences.options.subtitleOpacity)
                .padding(8).background(preferences.options.subtitleStyle == "box" ? Color(hex: preferences.options.subtitleBoxColor).opacity(preferences.options.boxOpacity) : .clear)
                .frame(maxWidth: .infinity).padding(.vertical, 12).background(.black).accessibilityIdentifier("settings-subtitle-preview")
            HarborSettingsChoice("Fuente", selection: $preferences.options.subtitleFont, choices: [("Inter · Harbor", "inter"), ("Sistema", "system"), ("Redondeada · Fredoka", "rounded"), ("Serif", "serif"), ("Árabe · Vazirmatn", "arabic")])
            HarborSettingsChoice("Fondo", selection: $preferences.options.subtitleStyle, choices: [("Sombra", "shadow"), ("Contorno", "outline"), ("Barra negra", "box")])
            HarborSettingsChoice("Subtítulos con estilo ASS", selection: $preferences.options.subtitleASS, choices: [("Original", "no"), ("Mi estilo conservando posición", "yes"), ("Redimensionar", "scale"), ("Forzar mi estilo", "force"), ("Eliminar estilos", "strip")])
            HarborSettingsToggle("Texto en negrita", isOn: $preferences.options.subtitleBold)
            dial("Tamaño", value: $preferences.options.subtitleSize, range: 16...120)
            dial("Espaciado de letras", value: $preferences.options.subtitleSpacing, range: 0...12)
            dial("Opacidad", value: $preferences.options.subtitleOpacity, range: 0.2...1, step: 0.05)
            dial("Altura desde el borde inferior", value: Binding(get: { 100 - preferences.options.subtitlePosition }, set: { preferences.options.subtitlePosition = 100 - $0 }), range: 0...100, suffix: "%")
            HarborSettingsChoice("Alineación", selection: $preferences.options.subtitleAlignment, choices: [("Izquierda", "left"), ("Centro", "center"), ("Derecha", "right")])
            ColorPicker("Color del texto", selection: color($preferences.options.subtitleColor), supportsOpacity: false)
            if preferences.options.subtitleStyle == "outline" {
                dial("Grosor del contorno", value: $preferences.options.borderSize, range: 1...6)
                ColorPicker("Color del contorno", selection: color($preferences.options.borderColor), supportsOpacity: false)
            }
            if preferences.options.subtitleStyle == "box" {
                ColorPicker("Color del fondo", selection: color($preferences.options.subtitleBoxColor), supportsOpacity: false)
                dial("Opacidad del fondo", value: $preferences.options.boxOpacity, range: 0...1, step: 0.05)
            }
            Button("Restablecer estilo de subtítulos") {
                let original = PlaybackOptions()
                preferences.options.subtitleSize = original.subtitleSize; preferences.options.subtitlePosition = original.subtitlePosition
                preferences.options.subtitleBold = false; preferences.options.subtitleStyle = original.subtitleStyle
                preferences.options.subtitleASS = original.subtitleASS; preferences.options.subtitleAlignment = original.subtitleAlignment
                preferences.options.subtitleColor = original.subtitleColor; preferences.options.borderColor = original.borderColor
                preferences.options.borderSize = original.borderSize; preferences.options.boxOpacity = original.boxOpacity
                preferences.options.subtitleOpacity = original.subtitleOpacity; preferences.options.subtitleDelay = 0
                preferences.options.subtitleFont = original.subtitleFont; preferences.options.subtitleSpacing = original.subtitleSpacing
                preferences.options.subtitleBoxColor = original.subtitleBoxColor; preferences.options.hideSDH = original.hideSDH
            }
        }
    }

    @ViewBuilder private var chapters: some View {
        if let state, !state.chapters.isEmpty {
            HarborSettingsSection("Capítulos") {
                ForEach(state.chapters) { chapter in
                    Button(chapter.title) { state.controller?.run(["seek", String(chapter.time), "absolute+exact"]) }
                }
            }
        }
    }
    private func tracks(_ state: PlayerState, type: String, property: String) -> some View {
        ForEach(state.tracks.filter { $0.type == type }) { track in
            Button { state.controller?.set(property, String(track.id)) } label: {
                HStack { Text(track.label).fixedSize(horizontal: false, vertical: true); Spacer(); if (property == "sid" ? track.mainSelection == 0 : track.selected) { Image("music-check").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true) } }
            }
            .disabled(type == "sub" && state.subtitleChanging)
        }
    }

    private func dial(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(HarborTheme.font(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + suffix).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
    private func preferredLanguages(_ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HarborSettingsChoice("Primer idioma preferido", selection: languagePriority(value, index: 0), choices: priorityLanguages)
                .accessibilityIdentifier("settings-first-language")
            HarborSettingsChoice("Segundo idioma preferido", selection: languagePriority(value, index: 1), choices: priorityLanguages)
                .accessibilityIdentifier("settings-second-language")
        }
    }
    private var priorityLanguages: [(String, String)] {
        languages.map { ($0.0, String($0.1.split(separator: ",").first ?? "")) }
    }
    private func languagePriority(_ value: Binding<String>, index: Int) -> Binding<String> {
        let canonical = ["es": "spa", "en": "eng", "ja": "jpn", "fre": "fra", "fr": "fra", "ger": "deu", "de": "deu", "it": "ita", "pt": "por"]
        func codes() -> [String] {
            var seen = Set<String>()
            return value.wrappedValue.split(separator: ",").map { canonical[String($0)] ?? String($0) }.filter { seen.insert($0).inserted }
        }
        return Binding(get: { let items = codes(); return index < items.count ? items[index] : "" }, set: { code in
            var items = codes()
            while items.count <= index { items.append("") }
            items[index] = code
            if index == 0 && code.isEmpty { value.wrappedValue = ""; return }
            var seen = Set<String>()
            value.wrappedValue = items.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(2).joined(separator: ",")
        })
    }
    private var previewFont: String {
        switch preferences.options.subtitleFont {
        case "rounded": "Fredoka-Light"
        case "arabic": "Vazirmatn-Regular"
        case "serif": "TimesNewRomanPSMT"
        case "system": "HelveticaNeue"
        default: "Inter-Regular"
        }
    }
    private func color(_ value: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: value.wrappedValue) }, set: { value.wrappedValue = $0.rgbHex })
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var rgbHex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
