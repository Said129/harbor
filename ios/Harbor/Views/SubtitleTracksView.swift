import SwiftUI
import UniformTypeIdentifiers

struct SubtitleTracksView: View {
    let state: PlayerState
    var embedded = false
    @State private var language: String?
    @State private var source = "all"
    @State private var hideHI = false
    @State private var forcedOnly = false
    @State private var chooseFile = false
    @State private var fileError: String?
    @State private var panelWidth: CGFloat = 0

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

    var body: some View {
        Group {
            if embedded { panelContent }
            else { ScrollView { panelContent.padding(18) }.background(HarborTheme.background) }
        }.font(HarborTheme.font(14)).foregroundStyle(HarborTheme.ink)
            .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.plainText, .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { state.controller?.importLocalSubtitle(url) }
                case .failure: fileError = "No se pudo abrir el archivo seleccionado."
                }
            }
            .onChange(of: groups.map(\.key)) { _, keys in if let language, language != "all", !keys.contains(language) { self.language = nil } }
            .onChange(of: state.subtitleImportMessage) { _, message in if message != nil { language = "all"; source = "all" } }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    if state.primarySubtitle != nil { state.controller?.selectSubtitle("no") }
                    else { state.controller?.selectSubtitle("auto") }
                } label: {
                    HStack(spacing: 8) {
                        selectionCircle(state.primarySubtitle != nil)
                        Text(text(state.primarySubtitle == nil ? "Off" : "On")).font(HarborTheme.font(13, weight: .semibold))
                    }.padding(.horizontal, 12).frame(minHeight: 44)
                        .background(HarborTheme.surface, in: .rect(cornerRadius: 6))
                }.buttonStyle(.plain).disabled(disabled).accessibilityIdentifier("subtitle-on-off")
                Text(String(tracks.count)).font(HarborTheme.font(12)).monospacedDigit().foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !embedded {
                    NavigationLink { SubtitleTimingView(state: state) } label: {
                        Image("player-subtitle-fps").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44)
                    }.disabled(SubtitleTiming.unavailable(state) != nil || state.subtitleChanging)
                        .accessibilityLabel(text("Subtitle FPS"))
                    NavigationLink { PlayerSettingsView(page: .subtitles) } label: {
                        Image("ui-customize-subtitles").resizable().scaledToFit().frame(width: 23, height: 23).frame(width: 44, height: 44)
                    }.accessibilityLabel(text("Subtitle appearance"))
                }
            }
            if let secondary = state.secondarySubtitle {
                HStack(spacing: 10) {
                    Text(text("2nd")).font(HarborTheme.font(10, weight: .bold)).foregroundStyle(HarborTheme.accent)
                    HarborLanguageFlag(code: SubtitleLanguages.key(secondary))
                    Text(SubtitleLanguages.label(secondary)).font(HarborTheme.font(13)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button { state.controller?.selectSubtitle("no", secondary: true) } label: {
                        Image("music-close").resizable().scaledToFit().frame(width: 12, height: 12).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).disabled(disabled).accessibilityLabel(text("Stop showing as second subtitle"))
                }.padding(.leading, 12).background(HarborTheme.accent.opacity(0.1), in: .rect(cornerRadius: 6))
            }
            if panelWidth >= 560 {
                HStack(alignment: .top, spacing: 16) {
                    languageButtons(vertical: true).frame(width: 128)
                    Divider()
                    trackContent.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                languageButtons(vertical: false)
                trackContent
            }
            Divider()
            Button { fileError = nil; chooseFile = true } label: {
                HStack(spacing: 8) {
                    Image("music-folder-open").resizable().scaledToFit().frame(width: 16, height: 16)
                    Text(text("Load file")).font(HarborTheme.font(13, weight: .semibold))
                }.frame(minHeight: 44)
            }.buttonStyle(.plain).disabled(disabled).accessibilityIdentifier("subtitle-import-file")
            if let message = state.subtitleImportMessage {
                HStack(spacing: 12) {
                    selectionCircle(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message).font(HarborTheme.font(13, weight: .semibold)).lineLimit(2)
                        Text(text("Imported and now playing")).font(HarborTheme.font(11)).foregroundStyle(HarborTheme.accent)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HarborTheme.accent.opacity(0.1), in: .rect(cornerRadius: 10))
            }
            if let message = fileError ?? state.subtitleIssue { Text(message).font(HarborTheme.font(12)).foregroundStyle(.secondary) }
        }.background {
            GeometryReader { proxy in
                Color.clear.onAppear { panelWidth = proxy.size.width }.onChange(of: proxy.size.width) { _, width in panelWidth = width }
            }
        }.accessibilityIdentifier("subtitle-original-panel")
    }

    @ViewBuilder private func languageButtons(vertical: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("Languages").uppercased()).font(HarborTheme.font(10, weight: .bold)).tracking(1.6).foregroundStyle(.secondary)
            if vertical {
                VStack(alignment: .leading, spacing: 4) { languageChoices }
            } else {
                ScrollView(.horizontal) { HStack(spacing: 6) { languageChoices } }.scrollIndicators(.hidden)
            }
        }
    }
    private var languageChoices: some View {
        Group {
            languageButton("all", title: text("All languages"), count: tracks.count)
            ForEach(groups, id: \.key) { group in languageButton(group.key, title: group.title, count: group.count) }
        }
    }
    private func languageButton(_ key: String, title: String, count: Int) -> some View {
        Button { language = key } label: {
            HStack(spacing: 8) {
                if key != "all" { HarborLanguageFlag(code: key) }
                Text(title).font(HarborTheme.font(12, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let primary = state.primarySubtitle, SubtitleLanguages.key(primary) == key { Circle().fill(HarborTheme.accent).frame(width: 6, height: 6) }
                Text(String(count)).font(HarborTheme.font(11)).monospacedDigit().foregroundStyle(.secondary)
            }.padding(.horizontal, 10).frame(minHeight: 44)
                .background(selectedLanguage == key ? HarborTheme.surface : .clear, in: .rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(HarborTheme.ink.opacity(selectedLanguage == key ? 0.08 : 0), lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selectedLanguage == key ? [.isSelected] : [])
    }

    private var trackContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    filter("All", count: tracks.count, selected: source == "all") { source = "all" }
                    filter("Embedded", count: tracks.filter { !$0.external }.count, selected: source == "embedded") { source = "embedded" }
                    filter("External", count: tracks.filter(\.external).count, selected: source == "external") { source = "external" }
                    filter("HI", selected: !hideHI, accented: true) { hideHI.toggle() }
                    filter("Forced", selected: forcedOnly, accented: true) { forcedOnly.toggle() }
                }
            }.scrollIndicators(.hidden)
            if let primary = state.primarySubtitle, !visible.contains(where: { $0.id == primary.id }) { trackRow(primary) }
            if tracks.isEmpty { Text(text("No subtitles found.")).foregroundStyle(.secondary).padding(.vertical, 12) }
            else if visible.isEmpty { Text(text("No tracks match these filters. Try toggling HI/SDH or Forced.")).foregroundStyle(.secondary).padding(.vertical, 12) }
            ForEach(visible) { track in trackRow(track) }
        }
    }

    private func filter(_ original: String, count: Int? = nil, selected: Bool, accented: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text(original)).font(HarborTheme.font(12, weight: .semibold))
                if let count { Text(String(count)).font(HarborTheme.font(11)).monospacedDigit() }
            }.padding(.horizontal, 11).frame(minHeight: 44)
                .foregroundStyle(selected && accented ? HarborTheme.background : HarborTheme.ink.opacity(selected ? 1 : 0.6))
                .background(selected ? (accented ? HarborTheme.accent : HarborTheme.surface) : .clear, in: .capsule)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func trackRow(_ track: PlayerState.Track) -> some View {
        let selected = track.mainSelection == 0
        let secondary = track.mainSelection == 1
        return HStack(alignment: .center, spacing: 0) {
            Button { state.controller?.selectSubtitle(String(track.id)) } label: {
                HStack(alignment: .top, spacing: 10) {
                    selectionCircle(selected).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title(track)).font(HarborTheme.font(13, weight: .semibold)).lineLimit(2)
                        Text(details(track)).font(HarborTheme.font(10)).foregroundStyle(.secondary).lineLimit(3)
                        if !tags(track).isEmpty {
                            Text(tags(track).joined(separator: " · ").uppercased()).font(HarborTheme.font(9, weight: .bold))
                                .tracking(0.7).foregroundStyle(track.hearingImpaired || track.isImageSubtitle ? Color.yellow : HarborTheme.ink.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 10).frame(minHeight: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(disabled).accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("subtitle-track-\(track.id)")
            if !selected && !track.isImageSubtitle {
                Button { state.controller?.selectSubtitle(secondary ? "no" : String(track.id), secondary: true) } label: {
                    Text(text("2nd")).font(HarborTheme.font(11, weight: .bold)).frame(width: 44, height: 44)
                        .background(secondary ? HarborTheme.surface : .clear, in: .rect(cornerRadius: 6))
                }.buttonStyle(.plain).disabled(disabled).accessibilityLabel(text(secondary ? "Stop showing as second subtitle" : "Show as second subtitle"))
                    .accessibilityIdentifier("subtitle-second-\(track.id)")
            }
            Text(String((tracks.firstIndex { $0.id == track.id } ?? 0) + 1)).font(HarborTheme.font(11)).monospacedDigit()
                .foregroundStyle(selected ? HarborTheme.accent : HarborTheme.ink.opacity(0.5)).padding(.trailing, 10)
        }.background(selected || secondary ? HarborTheme.surface : HarborTheme.surface.opacity(0.25), in: .rect(cornerRadius: 6))
    }
    private func selectionCircle(_ selected: Bool) -> some View {
        Circle().fill(selected ? HarborTheme.accent : HarborTheme.ink.opacity(0.1)).frame(width: 16, height: 16)
            .overlay {
                if selected { Image("subtitle-check").resizable().scaledToFit().frame(width: 9, height: 9).foregroundStyle(HarborTheme.background) }
            }.accessibilityHidden(true)
    }
    private func title(_ track: PlayerState.Track) -> String {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && title != track.language { return title }
        if track.external { return text("External subtitle") }
        return [text("Embedded") + " \(track.id)", track.codec.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private func details(_ track: PlayerState.Track) -> String {
        let source = state.importedSubtitleIDs.contains(track.id) ? "Imported" : track.external ? "External" : "Embedded"
        return [SubtitleLanguages.label(track).uppercased(), text(source), track.codec.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private func tags(_ track: PlayerState.Track) -> [String] {
        var result: [String] = []
        if track.hearingImpaired { result.append(text("Hearing impaired")) }
        if track.forced { result.append(text("Forced")) }
        if track.defaultTrack { result.append(text("Default")) }
        if track.isImageSubtitle { result.append(text("Position and size only")) }
        return result
    }
    private func text(_ original: String) -> String { DesktopInterfaceText.value(original) }
}
