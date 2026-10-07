import SwiftUI
import UniformTypeIdentifiers

struct SubtitleTracksView: View {
    let state: PlayerState
    var panel = false
    var embedded = false
    @State private var language: String?
    @State private var source = "all"
    @State private var hideHI = false
    @State private var forcedOnly = false
    @State private var chooseFile = false
    @State private var fileError: String?

    private var tracks: [PlayerState.Track] { state.tracks.filter { $0.type == "sub" } }
    private var groups: [(key: String, title: String, count: Int)] {
        var keys: [String] = []
        var values: [String: (String, Int)] = [:]
        for track in tracks {
            let key = SubtitleLanguages.key(track)
            if let current = values[key] { values[key] = (current.0, current.1 + 1) }
            else { keys.append(key); values[key] = (SubtitleLanguages.label(track), 1) }
        }
        return keys.compactMap { key in values[key].map { (key, $0.0, $0.1) } }
    }
    private var selectedLanguage: String {
        if let language { return language }
        if let track = state.primarySubtitle { return SubtitleLanguages.key(track) }
        return groups.first?.key ?? "all"
    }
    private var visible: [PlayerState.Track] {
        tracks.filter {
            (selectedLanguage == "all" || SubtitleLanguages.key($0) == selectedLanguage) &&
                (source == "all" || (source == "external" ? $0.external : !$0.external)) &&
                (!hideHI || !$0.hearingImpaired) && (!forcedOnly || $0.forced)
        }
    }
    private var disabled: Bool { !state.loaded || state.subtitleChanging }

    private var sections: some View {
        Group {
            Section("Idiomas y fuentes") {
                Picker("Idioma", selection: Binding(get: { selectedLanguage }, set: { language = $0 })) {
                    Text("Todos los idiomas · \(tracks.count)").tag("all")
                    ForEach(groups, id: \.key) { group in Text("\(group.title) · \(group.count)").tag(group.key) }
                }
                Picker("Fuente", selection: $source) {
                    Text("Todas · \(tracks.count)").tag("all")
                    Text("Integradas · \(tracks.filter { !$0.external }.count)").tag("embedded")
                    Text("Externas · \(tracks.filter { $0.external }.count)").tag("external")
                }
                Toggle("Mostrar pistas HI/SDH", isOn: Binding(get: { !hideHI }, set: { hideHI = !$0 }))
                Toggle("Sólo subtítulos forzados", isOn: $forcedOnly)
            }
            Section("Pista principal") {
                if let primary = state.primarySubtitle, !visible.contains(where: { $0.id == primary.id }) {
                    row(primary, selected: true)
                    Text("La pista seleccionada no coincide con estos filtros.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Desactivar") { state.controller?.selectSubtitle("no") }.disabled(disabled || state.primarySubtitle == nil)
                if tracks.isEmpty { Text("No hay pistas de subtítulos disponibles.").foregroundStyle(.secondary) }
                else if visible.isEmpty { Text("Ninguna pista coincide con estos filtros.").foregroundStyle(.secondary) }
                ForEach(visible) { track in
                    Button { state.controller?.selectSubtitle(String(track.id)) } label: { row(track, selected: track.mainSelection == 0) }
                        .disabled(disabled)
                        .contextMenu {
                            if !track.isImageSubtitle {
                                Button(track.mainSelection == 1 ? "Quitar segunda pista" : "Mostrar como segunda pista") { state.controller?.selectSubtitle(track.mainSelection == 1 ? "no" : String(track.id), secondary: true) }
                                    .disabled(disabled || track.mainSelection == 0)
                            }
                        }
                }
            }
            Section {
                if let track = state.secondarySubtitle { row(track, selected: true) }
                Button("Desactivar segunda pista") { state.controller?.selectSubtitle("no", secondary: true) }.disabled(disabled || state.secondarySubtitle == nil)
                ForEach(visible.filter { !$0.isImageSubtitle && $0.mainSelection != 0 }) { track in
                    Button { state.controller?.selectSubtitle(String(track.id), secondary: true) } label: { row(track, selected: track.mainSelection == 1) }.disabled(disabled)
                }
            } header: { Text("Segunda pista") } footer: { Text("Los subtítulos secundarios de texto se muestran junto a la pista principal, arriba o abajo según tu preferencia.") }
            Section {
                Button { fileError = nil; chooseFile = true } label: { Label("Cargar desde Archivos", image: "music-folder-open") }.disabled(disabled)
                    .accessibilityIdentifier("subtitle-import-file")
                if let message = state.subtitleImportMessage { Text(message).foregroundStyle(HarborTheme.accent) }
                if let message = fileError ?? state.subtitleIssue { Text(message).foregroundStyle(.secondary) }
            } footer: { Text("Archivos .srt, .ass, .ssa, .vtt o .sub, hasta 8 MB. El original se conserva en Archivos.") }
        }
    }
    var body: some View {
        Group {
            if panel { customPanel } else { sections }
        }
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.plainText, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { state.controller?.importLocalSubtitle(url) }
            case .failure: fileError = "No se pudo abrir el archivo seleccionado."
            }
        }
        .onChange(of: groups.map(\.key)) { _, keys in if let language, language != "all", !keys.contains(language) { self.language = nil } }
        .onChange(of: state.subtitleImportMessage) { _, message in if message != nil { language = "all"; source = "all" } }
    }
    @ViewBuilder private var customPanel: some View {
        if embedded { panelContent }
        else { ScrollView { panelContent.padding(18) }.background(HarborTheme.background) }
    }
    private var panelContent: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HarborPill(title: state.primarySubtitle == nil ? "Desactivados" : "Activados", selected: state.primarySubtitle != nil) {
                        if state.primarySubtitle != nil { state.controller?.selectSubtitle("no") }
                        else if let first = visible.first ?? tracks.first { state.controller?.selectSubtitle(String(first.id)) }
                    }.disabled(disabled)
                    Spacer()
                    if !embedded {
                        NavigationLink { PlayerSettingsView(page: .subtitles) } label: { Image("ui-customize-subtitles").resizable().scaledToFit().frame(width: 23, height: 23).frame(width: 44, height: 44) }.accessibilityLabel("Preferencias de subtítulos")
                    }
                }
                ScrollView(.horizontal) { HStack(spacing: 6) {
                    HarborPill(title: "Todos  \(tracks.count)", selected: source == "all") { source = "all" }
                    HarborPill(title: "Integrados  \(tracks.filter { !$0.external }.count)", selected: source == "embedded") { source = "embedded" }
                    HarborPill(title: "Externos  \(tracks.filter(\.external).count)", selected: source == "external") { source = "external" }
                    HarborPill(title: "HI / SDH", selected: !hideHI) { hideHI.toggle() }
                    HarborPill(title: "Forzados", selected: forcedOnly) { forcedOnly.toggle() }
                } }.scrollIndicators(.hidden)
                Text("IDIOMAS").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.secondary)
                ScrollView(.horizontal) { HStack(spacing: 6) {
                    HarborPill(title: "Todos  \(tracks.count)", selected: selectedLanguage == "all") { language = "all" }
                    ForEach(groups, id: \.key) { group in HarborPill(title: "\(group.title)  \(group.count)", selected: selectedLanguage == group.key) { language = group.key } }
                } }.scrollIndicators(.hidden)
                if let primary = state.primarySubtitle, !visible.contains(where: { $0.id == primary.id }) { row(primary, selected: true).padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10)); Text("La pista seleccionada no coincide con los filtros.").font(.caption).foregroundStyle(.secondary) }
                if tracks.isEmpty { Text("No hay pistas de subtítulos disponibles.").foregroundStyle(.secondary) }
                else if visible.isEmpty { Text("Ninguna pista coincide con los filtros.").foregroundStyle(.secondary) }
                ForEach(visible) { track in
                    Button { state.controller?.selectSubtitle(String(track.id)) } label: { row(track, selected: track.mainSelection == 0).padding(12).background(track.mainSelection == 0 ? HarborTheme.surface : HarborTheme.surface.opacity(0.35), in: .rect(cornerRadius: 10)) }.buttonStyle(.plain).disabled(disabled)
                }
                DisclosureGroup("Segunda pista") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Desactivar segunda pista") { state.controller?.selectSubtitle("no", secondary: true) }.disabled(disabled || state.secondarySubtitle == nil)
                        ForEach(visible.filter { !$0.isImageSubtitle && $0.mainSelection != 0 }) { track in Button { state.controller?.selectSubtitle(String(track.id), secondary: true) } label: { row(track, selected: track.mainSelection == 1).padding(10).background(HarborTheme.surface.opacity(0.4), in: .rect(cornerRadius: 9)) }.buttonStyle(.plain).disabled(disabled) }
                    }.padding(.top, 10)
                }
                Divider()
                Button { fileError = nil; chooseFile = true } label: { Label("Cargar desde Archivos", image: "music-folder-open").frame(minHeight: 44) }.disabled(disabled).accessibilityIdentifier("subtitle-import-file")
                if let message = state.subtitleImportMessage { Text(message).font(.caption).foregroundStyle(HarborTheme.accent) }
                if let message = fileError ?? state.subtitleIssue { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
    }

    private func row(_ track: PlayerState.Track, selected: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title.isEmpty || track.title == track.language ? (track.external ? "Subtítulo externo" : "Pista integrada \(track.id)") : track.title).lineLimit(2)
                Text(details(track)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            if selected { Image("music-check").accessibilityHidden(true) }
        }.frame(minHeight: 44).accessibilityElement(children: .combine)
    }
    private func details(_ track: PlayerState.Track) -> String {
        var parts = [SubtitleLanguages.label(track), state.importedSubtitleIDs.contains(track.id) ? "Importado" : track.external ? "Externo" : "Integrado"]
        if !track.codec.isEmpty { parts.append(track.codec.uppercased()) }
        if track.forced { parts.append("Forzado") }
        if track.hearingImpaired { parts.append("HI/SDH") }
        if track.defaultTrack { parts.append("Predeterminado") }
        if track.isImageSubtitle { parts.append("Subtítulo de imagen") }
        return parts.joined(separator: " · ")
    }
}
