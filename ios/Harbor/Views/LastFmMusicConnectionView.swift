import SwiftUI

@MainActor struct LastFmMusicConnectionView: View {
    let service: LastFmMusicService
    let metadata: MusicArtistClient
    @State private var apiKey = ""
    @State private var secret = ""
    @State private var busy = false
    @State private var failed = false
    @State private var operation: Task<Void, Never>?
    @Environment(\.openURL) private var openURL
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        Form {
            Section("Last.fm") {
                Label(text(service.connected ? "music.lastfm.connected" : "music.lastfm.history"), systemImage: service.connected ? "checkmark.circle" : "waveform")
                if let username = service.username { Text(username).textSelection(.enabled) }
                if let url = service.profileURL { Link(text("music.lastfm.viewProfile"), destination: url) }
                Text(text("music.legal.data")).font(.footnote).foregroundStyle(.secondary)
            }
            if service.connected {
                Section {
                    Button(text("music.lastfm.disconnect"), role: .destructive) {
                        do { try service.disconnect(); try metadata.saveAPIKey(""); apiKey = ""; secret = ""; failed = false }
                        catch { failed = true }
                    }.disabled(busy)
                }
            } else {
                credentialsSection
            }
            if service.authorizationURL != nil { finishSection }
            if busy { ProgressView() }
            if failed { Text(DesktopInterfaceText.value("music.connect.failed", variables: ["error": ""]).trimmingCharacters(in: .whitespaces)).foregroundStyle(.orange) }
            if service.storageFailure { Text(text("music.connections.statusError")).foregroundStyle(.orange) }
        }.navigationTitle("Last.fm").navigationBarTitleDisplayMode(.inline)
            .onAppear { if let values = try? service.credentials() { apiKey = values.0; secret = values.1 } }
            .onDisappear { operation?.cancel(); operation = nil }
            .accessibilityIdentifier("music-lastfm-connection")
    }
    private var credentialsSection: some View {
        Section {
            Text(text("music.lastfm.keyHelp")).font(.footnote).foregroundStyle(.secondary)
            SecureField(text("music.lastfm.apiKey"), text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField(text("music.lastfm.secret"), text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
            Link(text("music.lastfm.getKey"), destination: URL(string: "https://www.last.fm/api/account/create")!)
            Link(text("music.lastfm.createAccount"), destination: URL(string: "https://www.last.fm/join")!)
            Button(text("Save")) {
                do { try saveDraft(); failed = false }
                catch { failed = true }
            }.disabled(busy || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if service.hasCredentials { Label(text("music.lastfm.saved"), systemImage: "checkmark") }
            Button(text("music.lastfm.authorize")) {
                busy = true; failed = false
                operation = Task { @MainActor in
                    defer { busy = false }
                    do {
                        try saveDraft()
                        let url = try await service.beginAuthorization()
                        try Task.checkCancellation(); openURL(url)
                    } catch is CancellationError { }
                    catch { failed = true }
                }
            }.disabled(busy || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private var finishSection: some View {
        Section {
            Text(text("music.lastfm.browserPrompt")).font(.footnote)
            Button(text("music.lastfm.finish")) {
                busy = true; failed = false
                operation = Task { @MainActor in
                    defer { busy = false }
                    do { try await service.completeAuthorization(); apiKey = ""; secret = "" }
                    catch is CancellationError { }
                    catch { failed = true }
                }
            }.disabled(busy)
        }
    }
    private func saveDraft() throws {
        guard metadata.scope == service.scope else { throw CancellationError() }
        try service.saveCredentials(apiKey: apiKey, secret: secret)
        try metadata.saveAPIKey(apiKey)
    }
}
