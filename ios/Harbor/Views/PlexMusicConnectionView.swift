import SwiftUI

@MainActor struct PlexMusicConnectionView: View {
    let service: PlexMusicService
    let changed: @MainActor () -> Void
    @State private var address = ""
    @State private var token = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Plex") {
                Text(DesktopInterfaceText.value(service.statusKey)).foregroundStyle(.secondary)
                if let account = service.account { Text(account.server ?? account.origin).font(.headline) }
                Text(["search", "browse", "play", "library"].map { DesktopInterfaceText.value("music.connections.capability." + $0) }.joined(separator: " / "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if service.configured {
                Section {
                    Button(DesktopInterfaceText.value("music.connect.disconnect"), role: .destructive) {
                        do { try service.disconnect(); changed() } catch { showFailure() }
                    }.accessibilityIdentifier("music-plex-disconnect")
                }
            } else {
                Section {
                    TextField(DesktopInterfaceText.value("Server URL"), text: $address, prompt: Text("https://plex.local:32400"))
                        .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("music-plex-address")
                    SecureField(DesktopInterfaceText.value("Access token"), text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("music-plex-token")
                    Text(DesktopInterfaceText.value("music.mobile.plex.discovery")).font(.footnote).foregroundStyle(.secondary)
                    Button { connect() } label: {
                        HStack { if busy { ProgressView() }; Text(DesktopInterfaceText.value(busy ? "music.connect.connecting" : "music.connect.action")) }
                    }.disabled(busy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("music-plex-connect")
                }.disabled(busy)
            }
            if let failure { Section { Text(failure).foregroundStyle(.orange).accessibilityIdentifier("music-plex-failure") } }
        }.navigationTitle("Plex").scrollDismissesKeyboard(.interactively)
            .onDisappear { operation?.cancel(); operation = nil; if busy { service.cancelPending() }; busy = false; token = ""; address = "" }
            .accessibilityIdentifier("music-plex-connection")
    }
    private func showFailure() { failure = DesktopInterfaceText.value("Music is unavailable right now.") }
    private func connect() {
        guard !busy else { return }; busy = true; failure = nil
        operation = Task {
            defer { busy = false; token = ""; operation = nil }
            do {
                try await service.connect(address: address, token: token)
                try Task.checkCancellation(); try service.validate(); address = ""; changed()
            } catch is CancellationError { }
            catch { if !Task.isCancelled, (try? service.validate()) != nil { showFailure() } }
        }
    }
}
