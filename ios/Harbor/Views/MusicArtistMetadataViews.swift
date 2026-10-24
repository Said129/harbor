import SwiftUI

private struct MusicArtistMetadataKey: EnvironmentKey { static let defaultValue: MusicArtistClient? = nil }
extension EnvironmentValues {
    var musicArtistMetadata: MusicArtistClient? {
        get { self[MusicArtistMetadataKey.self] }
        set { self[MusicArtistMetadataKey.self] = newValue }
    }
}
@MainActor struct MusicGenreArtistsView: View {
    let genre: MusicGenre
    let known: [MusicCatalogArtist]
    let metadata: MusicArtistClient
    let catalog: any MusicCatalogCalling
    @State private var model = MusicArtistRosterModel()
    @State private var next: Task<Void, Never>?
    @AppStorage("uiLanguage") private var language = "es"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MusicCatalogRail(row: .init(id: "genre-artists:" + String(genre.id), title: "music.explore.sceneArtists", titleLiteral: false,
                subtitle: model.rows.contains { $0.listeners != nil } ? "Last.fm · MusicBrainz" : "MusicBrainz", layout: .circles, source: "catalog",
                items: model.rows.map { .artist($0.catalog(locale: Locale(identifier: InterfaceLanguage.resolve(language)))) }), client: catalog)
            if model.loading { ProgressView(DesktopInterfaceText.value("Loading music")).frame(maxWidth: .infinity) }
            if model.failure { Text(DesktopInterfaceText.value("music.error.load")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18) }
            if !model.exhausted || model.failure {
                Button(DesktopInterfaceText.value(model.failure ? "Retry" : "music.library.loadMore")) {
                    next?.cancel(); next = Task { await model.loadNext(known: known, client: metadata) }
                }.buttonStyle(.bordered).disabled(model.loading).frame(maxWidth: .infinity).accessibilityIdentifier("music-genre-artists-more")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("music-genre-artists")
            .task(id: String(genre.id) + "|" + metadata.credentialVersion.uuidString) { await model.load(genre.id, known: known, client: metadata, revision: metadata.credentialVersion) }
            .onDisappear { next?.cancel(); model.cancel() }
    }
}
@MainActor struct MusicRecordingCreditsView: View {
    let track: MusicTrack
    let metadata: MusicArtistClient
    let catalog: any MusicCatalogCalling
    @State private var profile: MusicRecordingProfile?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let profile, !profile.credits.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack { title; Spacer(); sources(profile) }
                        VStack(alignment: .leading, spacing: 10) { title; sources(profile) }
                    }
                    ForEach(Array(profile.credits.enumerated()), id: \.offset) { index, credit in
                        MusicCatalogLink(item: .artist(credit.artist.catalog), client: catalog) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(credit.name).font(.subheadline.weight(.semibold))
                                    Text(role(credit)).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityIdentifier("music-recording-credit-" + String(index))
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("music-recording-credits")
            }
        }.task(id: track.id + "|" + track.title + "|" + track.artist + "|" + metadata.credentialVersion.uuidString) {
            profile = nil
            do {
                let value = try await metadata.recording(track); try Task.checkCancellation(); profile = value
            } catch { }
        }
    }
    private var title: some View { Text(DesktopInterfaceText.value("music.credits.title")).font(.title2.bold()) }
    private func role(_ credit: MusicRecordingProfile.Credit) -> String {
        let roles = ["main artist": "main", "featured artist": "featured", "composer": "composer", "lyricist": "lyricist",
            "producer": "producer", "performer": "performer", "vocal": "performer", "instrument": "performer"]
        let label = roles[credit.role.lowercased()].map { DesktopInterfaceText.value("music.credits." + $0) } ?? credit.role
        return label + ((credit.attributes?.isEmpty == false) ? " · " + (credit.attributes ?? []).joined(separator: ", ") : "")
    }
    private func sources(_ profile: MusicRecordingProfile) -> some View {
        let values = Dictionary(profile.credits.map { ($0.source, $0.sourceUrl) }, uniquingKeysWith: { _, last in last })
        return HStack(spacing: 12) {
            ForEach(values.keys.sorted(), id: \.self) { name in
                if let raw = values[name], let url = URL(string: raw), url.scheme == "https",
                   ["www.deezer.com", "musicbrainz.org"].contains(url.host?.lowercased() ?? "") {
                    Link(destination: url) { Label(name, systemImage: "arrow.up.right") }.font(.caption)
                }
            }
        }
    }
}
@MainActor struct MusicMetadataSettingsView: View {
    let client: MusicArtistClient
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var result: String?
    @State private var failed = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(DesktopInterfaceText.value("music.lastfm.apiKey"), text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("music-lastfm-key")
                    if client.hasAPIKey { Label(DesktopInterfaceText.value("Saved"), systemImage: "checkmark.circle").accessibilityIdentifier("music-lastfm-key-saved") }
                    Button(DesktopInterfaceText.value("Save")) { save(input) }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("music-lastfm-key-save")
                    if client.hasAPIKey { Button(DesktopInterfaceText.value("Remove"), role: .destructive) { save("") }.accessibilityIdentifier("music-lastfm-key-remove") }
                    Link(DesktopInterfaceText.value("Get an API key"), destination: URL(string: "https://www.last.fm/api/account/create")!)
                } header: { Text("Last.fm") } footer: { Text("MusicBrainz · Deezer · Last.fm") }
                if let result { Text(DesktopInterfaceText.value(result)).foregroundStyle(failed ? Color.orange : Color.secondary).accessibilityIdentifier("music-metadata-key-result") }
                else if client.keyFailure { Text(DesktopInterfaceText.value("music.error.load")).foregroundStyle(.orange) }
            }.navigationTitle(DesktopInterfaceText.value("Metadata")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(DesktopInterfaceText.value("Done")) { dismiss() } } }
                .accessibilityIdentifier("music-metadata-settings")
        }
    }
    private func save(_ value: String) {
        do { try client.saveAPIKey(value); input = ""; failed = false; result = value.isEmpty ? "Removed" : "Saved" }
        catch { failed = true; result = "music.error.load" }
    }
}
