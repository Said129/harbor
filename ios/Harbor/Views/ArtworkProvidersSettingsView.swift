import SwiftUI

/// Desktop's RPDB and Fanart.tv key fields (`library-panel/provider-keys.tsx`). The keys are stored per profile;
/// Desktop has no key validation for either provider, so none is shown here.
struct ArtworkProvidersSettingsView: View {
    @State private var store: ArtworkKeyStore
    @State private var loadFailed = false
    private let owner: String
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    init(owner: String) { self.owner = owner; _store = State(initialValue: ArtworkKeyStore.forOwner(owner)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection(text("Metadata providers"), note: text("Optional keys that unlock TMDB rails, baked-in poster ratings, fanart, and TVDB episode data.")) {
                    ArtworkKeyField(store: store, provider: .rpdb)
                    ArtworkKeyField(store: store, provider: .fanart)
                    if loadFailed { Button(text("Retry")) { load() }.frame(minHeight: 44).accessibilityIdentifier("artwork-keys-reload") }
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Metadata providers")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("artwork-providers-scroll").task { load() }
    }

    private func load() { do { try store.load(); loadFailed = false } catch { loadFailed = true } }
}

private struct ArtworkKeyField: View {
    let store: ArtworkKeyStore
    let provider: ArtworkKeyStore.Provider
    @State private var draft = ""
    @State private var revealed = false
    @State private var error: String?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private var name: String { provider == .rpdb ? "RPDB" : "Fanart.tv" }
    private var summary: String {
        text(provider == .rpdb ? "Paid. Bakes scores into the poster image itself." : "Logos and backdrops where TMDB comes up empty.")
    }
    private var label: String {
        text(provider == .rpdb ? "RPDB · scores baked into posters" : "Fanart.tv · logos and backdrops")
    }
    private var placeholder: String { text(provider == .rpdb ? "rpdb key" : "personal key") }
    private var siteTitle: String { provider == .rpdb ? "ratingposterdb.com" : "fanart.tv/get-an-api-key" }
    private var siteURL: URL? {
        URL(string: provider == .rpdb ? "https://ratingposterdb.com" : "https://fanart.tv/get-an-api-key/")
    }
    private var help: String {
        let lead = provider == .rpdb ? text("Paid plan at") : text("Fills in where TMDB comes up empty (anime, older catalog). Free at")
        let tail = provider == .rpdb
            ? text("Once saved, every poster gets re-rendered with IMDb, Rotten Tomatoes, and Metacritic stamped on it.")
            : text("Use the \"personal\" key, not the project one.")
        return lead + " " + siteTitle + ". " + tail
    }
    private var saved: String { store.key(provider) }
    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dirty: Bool { trimmedDraft != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(label).font(HarborTheme.font(16, weight: .semibold))
                Circle().fill(saved.isEmpty ? Color.secondary.opacity(0.4) : Color.green).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(text(saved.isEmpty ? "Not set" : "Saved")).font(.footnote).foregroundStyle(.secondary)
            }
            Text(summary).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Group {
                    if revealed { TextField(placeholder, text: $draft) } else { SecureField(placeholder, text: $draft) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().submitLabel(.done).onSubmit { save() }
                    .accessibilityIdentifier("artwork-key-" + provider.rawValue)
                if !draft.isEmpty {
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(text(revealed ? "Hide" : "Show"))
                }
            }.padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
            HStack(spacing: 14) {
                Button(text(dirty || saved.isEmpty ? "Save" : "Saved")) { save() }
                    .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!dirty || trimmedDraft.isEmpty)
                    .accessibilityIdentifier("artwork-key-save-" + provider.rawValue)
                if !saved.isEmpty {
                    Button(text("Remove"), role: .destructive) { remove() }.frame(minHeight: 44)
                        .accessibilityIdentifier("artwork-key-remove-" + provider.rawValue)
                }
                Spacer(minLength: 0)
                if let siteURL { Link(siteTitle, destination: siteURL).font(.footnote).underline().frame(minHeight: 44) }
            }
            Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
