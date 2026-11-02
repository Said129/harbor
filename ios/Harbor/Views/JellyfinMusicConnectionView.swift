import SwiftUI

@MainActor struct JellyfinMusicConnectionView: View {
    let service: JellyfinMusicService
    let changed: @MainActor () -> Void
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Jellyfin") {
                Text(DesktopInterfaceText.value(service.statusKey)).foregroundStyle(.secondary)
                if let account = service.account {
                    Text(account.serverName).font(.headline)
                    Text(DesktopInterfaceText.value("music.connect.connected", variables: ["account": account.userName]))
                }
                Text(["search", "browse", "play", "library"].map { DesktopInterfaceText.value("music.connections.capability." + $0) }.joined(separator: " / "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if service.configured {
                Section {
                    Button(DesktopInterfaceText.value("music.connect.disconnect"), role: .destructive) {
                        do { try service.disconnect(); changed() } catch { showFailure() }
                    }.accessibilityIdentifier("music-jellyfin-disconnect")
                }
            } else {
                Section {
                    TextField(DesktopInterfaceText.value("Server URL"), text: $address, prompt: Text("https://jellyfin.local"))
                        .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("music-jellyfin-address")
                    TextField(DesktopInterfaceText.value("Username"), text: $username).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("music-jellyfin-username")
                    SecureField(DesktopInterfaceText.value("Password"), text: $password).textContentType(.password)
                        .accessibilityIdentifier("music-jellyfin-password")
                    Button { connect() } label: {
                        HStack { if busy { ProgressView() }; Text(DesktopInterfaceText.value(busy ? "music.connect.connecting" : "music.connect.action")) }
                    }.disabled(busy || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("music-jellyfin-connect")
                }.disabled(busy)
            }
            if let failure { Section { Text(failure).foregroundStyle(.orange).accessibilityIdentifier("music-jellyfin-failure") } }
        }.navigationTitle("Jellyfin").scrollDismissesKeyboard(.interactively)
            .onDisappear { operation?.cancel(); operation = nil; if busy { service.cancelPending() }; busy = false; password = ""; username = ""; address = "" }
            .accessibilityIdentifier("music-jellyfin-connection")
    }
    private func showFailure() { failure = DesktopInterfaceText.value("Music is unavailable right now.") }
    private func connect() {
        guard !busy else { return }; busy = true; failure = nil
        operation = Task {
            defer { busy = false; password = ""; operation = nil }
            do {
                try await service.connect(address: address, username: username, password: password)
                try Task.checkCancellation(); try service.validate()
                username = ""; address = ""; changed()
            } catch is CancellationError { }
            catch { if !Task.isCancelled, (try? service.validate()) != nil { showFailure() } }
        }
    }
}
