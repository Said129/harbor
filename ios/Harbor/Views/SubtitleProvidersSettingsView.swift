import SwiftUI

/// Desktop's "Subtitle sources" panel (`views/settings/sub-sources-panel.tsx`): one toggle per source, and a key field
/// under each source that needs one (OpenSubtitles takes an optional key). Opened from the subtitle settings screen.
/// The toggles only store the choice for now. The search that reads them is not wired into the player yet.
struct SubtitleProvidersSettingsView: View {
    @State private var store: SubtitleProviderKeyStore
    @AppStorage("subtitleProvider.opensubtitles.enabled") private var openSubtitlesOn = true
    @AppStorage("subtitleProvider.wyzie.enabled") private var wyzieOn = false
    @AppStorage("subtitleProvider.subdl.enabled") private var subdlOn = false
    @AppStorage("subtitleProvider.subsource.enabled") private var subsourceOn = false
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    init(owner: String) { _store = State(initialValue: SubtitleProviderKeyStore.forOwner(owner)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection(text("Built into Harbor"), note: text("Choose where Harbor searches for subtitles. Results from enabled sources appear together, with duplicates removed.")) {
                    HarborSettingsToggle(text("OpenSubtitles"), note: text("Harbor's built-in OpenSubtitles search, on by default. If you install an OpenSubtitles addon, this steps aside automatically so your results are never duplicated."), isOn: $openSubtitlesOn)
                        .accessibilityIdentifier("subtitle-provider-opensubtitles")
                    if openSubtitlesOn {
                        SubtitleProviderKeyField(store: store, provider: .opensubtitles)
                    }
                    HarborSettingsToggle(text("Wyzie"), note: text("A fast community subtitle index. Off by default; turn it on for extra coverage on newer or niche releases."), isOn: $wyzieOn)
                        .accessibilityIdentifier("subtitle-provider-wyzie")
                }
                HarborSettingsSection(text("Needs an API key")) {
                    HarborSettingsToggle(text("SUBDL"), note: text("Search SUBDL for subtitles in multiple languages. Requires an API key."), isOn: $subdlOn)
                        .accessibilityIdentifier("subtitle-provider-subdl")
                    if subdlOn && store.key(.subdl).isEmpty {
                        Text(text("Add an API key to use this source.")).font(.caption).foregroundStyle(.orange)
                    }
                    if subdlOn {
                        SubtitleProviderKeyField(store: store, provider: .subdl)
                    }
                    HarborSettingsToggle(text("Subsource"), note: text("Search the Subsource community database. Requires an API key."), isOn: $subsourceOn)
                        .accessibilityIdentifier("subtitle-provider-subsource")
                    if subsourceOn && store.key(.subsource).isEmpty {
                        Text(text("Add an API key to use this source.")).font(.caption).foregroundStyle(.orange)
                    }
                    if subsourceOn {
                        SubtitleProviderKeyField(store: store, provider: .subsource)
                    }
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Subtitle sources")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("subtitle-providers-scroll")
            .task { try? store.load() }
    }
}

private struct SubtitleProviderKeyField: View {
    let store: SubtitleProviderKeyStore
    let provider: SubtitleProviderKeyStore.Provider
    @State private var draft = ""
    @State private var revealed = false
    @State private var error: String?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private var label: String {
        switch provider {
        case .opensubtitles: "OpenSubtitles API key"
        case .subdl: "SUBDL API key"
        case .subsource: "Subsource API key"
        }
    }

    private var placeholder: String {
        switch provider {
        case .opensubtitles: "Paste your OpenSubtitles API key"
        case .subdl: "Paste your SUBDL API key"
        case .subsource: "Paste your Subsource API key"
        }
    }

    private var help: String {
        switch provider {
        case .opensubtitles: "Searching works without a key. Adding one lets Harbor line subtitles up with the audio on its own."
        case .subdl: "SUBDL returns nothing until a key is saved here."
        case .subsource: "Subsource returns nothing until a key is saved here."
        }
    }

    private var siteTitle: String {
        switch provider {
        case .opensubtitles: "Get a free key at opensubtitles.com"
        case .subdl: "Get a free key at subdl.com"
        case .subsource: "Get your key at subsource.net"
        }
    }

    private var siteURL: URL? {
        switch provider {
        case .opensubtitles: URL(string: "https://www.opensubtitles.com/consumers")
        case .subdl: URL(string: "https://subdl.com/panel/api")
        case .subsource: URL(string: "https://subsource.net")
        }
    }

    private var saved: String { store.key(provider) }
    private var dirty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines) != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text(label)).font(HarborTheme.font(14, weight: .semibold))
            Text(text(help)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Group {
                    if revealed { TextField(text(placeholder), text: $draft) } else { SecureField(text(placeholder), text: $draft) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().submitLabel(.done).onSubmit { save() }
                    .accessibilityIdentifier("subtitle-provider-key-" + provider.rawValue)
                if !draft.isEmpty {
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(text(revealed ? "Hide" : "Show"))
                }
            }.padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
            HStack(spacing: 14) {
                Button(text(dirty || saved.isEmpty ? "Save" : "Saved")) { save() }
                    .buttonStyle(HarborAccountButtonStyle(primary: true))
                    .disabled(!dirty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("subtitle-provider-key-save-" + provider.rawValue)
                if !saved.isEmpty {
                    Button(text("Remove"), role: .destructive) { remove() }.frame(minHeight: 44)
                        .accessibilityIdentifier("subtitle-provider-key-remove-" + provider.rawValue)
                }
                Spacer(minLength: 0)
                if let url = siteURL { Link(text(siteTitle), destination: url).font(.footnote).underline().frame(minHeight: 44) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(14).background(HarborTheme.surface.opacity(0.5), in: .rect(cornerRadius: 12))
        .task(id: saved) { draft = saved }
    }

    private func save() {
        do { try store.set(draft, for: provider); error = nil } catch { self.error = safeMessage(error) }
    }

    private func remove() {
        do { try store.set("", for: provider); draft = ""; error = nil } catch { self.error = safeMessage(error) }
    }
}
