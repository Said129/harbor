import SwiftUI

struct EBookNarrationBar: View {
    let narrator: EBookNarrator
    let start: () -> Void
    let options: () -> Void
    private var label: String { narrator.loading ? "Cancel Edge TTS generation" : narrator.speaking ? narrator.paused ? "Resume narration" : "Pause narration" : "Read chapter with Edge TTS" }
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Button(action: options) { Image(systemName: "waveform").frame(width: 44, height: 44) }
                    .accessibilityLabel(DesktopInterfaceText.value("Voice")).accessibilityIdentifier("ebook-narration-options")
                Button {
                    if narrator.loading { narrator.stop() }
                    else if narrator.speaking { narrator.togglePause() }
                    else { start() }
                } label: { Image(systemName: narrator.loading ? "xmark" : narrator.speaking && !narrator.paused ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(DesktopInterfaceText.value(label)).accessibilityIdentifier("ebook-narration-play")
                if narrator.loading {
                    ProgressView(value: Double(narrator.progress), total: 100).accessibilityLabel(DesktopInterfaceText.value("Preparing narration audio"))
                    Text("\(narrator.progress)%").font(.caption.monospacedDigit()).accessibilityIdentifier("ebook-narration-progress")
                } else if narrator.duration > 0 {
                    Text(time(narrator.position)).font(.caption2.monospacedDigit())
                    Slider(value: Binding(get: { narrator.position }, set: { narrator.seek($0) }), in: 0...max(0.01, narrator.duration))
                        .accessibilityLabel(DesktopInterfaceText.value("Audio position")).accessibilityIdentifier("ebook-narration-seek")
                    Text("−" + time(max(0, narrator.duration - narrator.position))).font(.caption2.monospacedDigit())
                } else { Spacer(minLength: 0) }
                if narrator.speaking || narrator.previewID != nil {
                    Button { narrator.stop() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel(DesktopInterfaceText.value("Stop")).accessibilityIdentifier("ebook-narration-stop")
                }
            }
            if let notice = narrator.notice { Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("ebook-narration-error") }
        }
    }
    private func time(_ value: Double) -> String { let seconds = max(0, Int(value.isFinite ? value : 0)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

struct EBookNarrationView: View {
    let narrator: EBookNarrator
    let fallback: String
    @Binding var voice: String
    @Binding var deviceVoice: String
    @Binding var provider: String
    @Binding var speed: Double
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var language = ""
    private var available: [EBookNarrationVoice] { provider == "device" ? EBookNarrator.deviceVoices : narrator.voices }
    private var selected: String { provider == "device" ? deviceVoice : voice }
    private var filtered: [EBookNarrationVoice] {
        available.filter { item in
            (language.isEmpty || item.locale.components(separatedBy: "-")[0] == language) && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (item.name + " " + item.locale + " " + item.gender + " " + item.id).localizedStandardContains(query))
        }
    }
    private var languages: [String] { Array(Set(available.map { $0.locale.components(separatedBy: "-")[0] })).sorted() }
    private var selectedLanguage: String { (available.first { $0.id == selected } ?? available.first)?.locale.components(separatedBy: "-").first ?? "" }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(DesktopInterfaceText.value("Voice"), selection: $provider) {
                        Text("Edge TTS").tag("edge")
                        Text(DesktopInterfaceText.value("Device voice")).tag("device")
                    }.accessibilityIdentifier("ebook-narration-provider")
                    HStack {
                        Text(DesktopInterfaceText.value("Playback speed")); Spacer()
                        Text(speed, format: .number.precision(.fractionLength(2))).monospacedDigit(); Text("×")
                    }
                    Slider(value: $speed, in: 0.5...2, step: 0.05).accessibilityLabel(DesktopInterfaceText.value("Playback speed")).accessibilityIdentifier("ebook-narration-speed")
                    Picker(DesktopInterfaceText.value("Language"), selection: $language) {
                        Text(DesktopInterfaceText.value("All")).tag("")
                        ForEach(languages, id: \.self) { id in Text(Locale.current.localizedString(forLanguageCode: id) ?? id).tag(id) }
                    }.accessibilityIdentifier("ebook-narration-language")
                }
                Section(DesktopInterfaceText.value("Voice")) {
                    if narrator.loadingVoices, provider == "edge" { ProgressView().accessibilityIdentifier("ebook-narration-voices-loading") }
                    if narrator.voiceFailure, provider == "edge" {
                        Button(DesktopInterfaceText.value("Retry")) { Task { await narrator.loadVoices() } }.accessibilityIdentifier("ebook-narration-voices-retry")
                    }
                    ForEach(filtered) { item in
                        HStack(spacing: 12) {
                            Button {
                                narrator.stop(); if provider == "device" { deviceVoice = item.id } else { voice = item.id }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) { Text(item.label); Text(item.locale + (item.gender.isEmpty ? "" : " · " + DesktopInterfaceText.value(item.gender))).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(minLength: 4)
                                    if selected == item.id { Image(systemName: "checkmark").accessibilityLabel(DesktopInterfaceText.value("Selected")) }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityValue(selected == item.id ? DesktopInterfaceText.value("Selected") : "").accessibilityIdentifier("ebook-narration-voice-" + item.id)
                            Button { narrator.preview(item, device: provider == "device", fallback: fallback) } label: {
                                Group {
                                    if narrator.previewID == item.id, narrator.loading { ProgressView() }
                                    else { Image(systemName: narrator.previewID == item.id ? "stop.fill" : "play.fill") }
                                }.frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel(DesktopInterfaceText.value(narrator.previewID == item.id ? "Stop" : "Preview voice")).accessibilityIdentifier("ebook-narration-preview-" + item.id)
                        }
                    }
                    if filtered.isEmpty { Text(DesktopInterfaceText.value("No results")).foregroundStyle(.secondary) }
                }
                if let notice = narrator.notice { Section { Text(notice).foregroundStyle(.secondary) } }
                Section {
                    Button(DesktopInterfaceText.value("Clear narration cache")) { Task { await narrator.clearCache() } }.accessibilityIdentifier("ebook-narration-cache-clear")
                    NavigationLink(DesktopInterfaceText.value("Licenses")) { ScrollView { Text(notices).font(.caption).textSelection(.enabled).padding() }.navigationTitle(DesktopInterfaceText.value("Licenses")) }
                }
            }
            .searchable(text: $query, prompt: DesktopInterfaceText.value("Search voices"))
            .navigationTitle(DesktopInterfaceText.value("Voice"))
            .safeAreaInset(edge: .bottom) { HStack { Spacer(); Button(DesktopInterfaceText.value("Done")) { dismiss() }.buttonStyle(.borderedProminent).accessibilityIdentifier("ebook-narration-done") }.padding().background(.bar) }
            .task { language = selectedLanguage; await narrator.loadVoices() }
            .onChange(of: provider) { _, _ in narrator.stop(); query = ""; language = selectedLanguage }
            .onChange(of: selected) { _, _ in language = selectedLanguage }
            .onChange(of: speed) { _, value in narrator.setSpeed(value) }
            .onDisappear { if narrator.previewID != nil { narrator.stop() } }
        }
    }
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "EBookNarrationNotices", withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
