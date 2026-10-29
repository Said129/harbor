import SwiftUI

@MainActor struct MusicServerConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: MusicServerConnectionModel
    @State private var operation: Task<Void, Never>?
    let onChange: @MainActor () -> Void
    init(service: SubsonicMusicService, onChange: @escaping @MainActor () -> Void) {
        _model = State(initialValue: MusicServerConnectionModel(service: service)); self.onChange = onChange
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(text("music.connections.server")).font(.headline).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("music-server-title")
                Spacer(minLength: 12)
                Button(text("Close")) { dismiss() }.frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 20)
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "server.rack").font(.title2).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Navidrome").font(.headline)
                            Text(text(model.statusKey)).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("music-server-status")
                            if let pair = model.service.pairing {
                                Text(text("music.connect.connected", variables: ["account": pair.username])).font(.subheadline).lineLimit(2)
                            }
                        }
                    }.padding(.vertical, 6)
                    Text(["search", "browse", "play", "library"].map { text("music.connections.capability." + $0) }.joined(separator: " / "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.service.configured {
                    Section {
                        Button(text("music.connect.disconnect"), role: .destructive) { if model.disconnect() { onChange() } }
                            .accessibilityIdentifier("music-server-disconnect")
                    }
                } else {
                    Section {
                        TextField(text("Server URL"), text: $model.address, prompt: Text("https://navidrome.local"))
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("music-server-address")
                        TextField(text("Username"), text: $model.username).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("music-server-username")
                        SecureField(text("Password"), text: $model.password).textContentType(.password)
                            .accessibilityIdentifier("music-server-password")
                        Button { connect() } label: {
                            HStack {
                                if model.busy { ProgressView().accessibilityHidden(true) }
                                Text(text(model.busy ? "music.connect.connecting" : "music.connect.action"))
                            }
                        }.disabled(model.busy || model.incomplete).accessibilityIdentifier("music-server-connect")
                    }.disabled(model.busy)
                }
                if let failure = model.failure {
                    Section {
                        Text(failure).font(.subheadline).foregroundStyle(.orange).textSelection(.enabled)
                            .accessibilityIdentifier("music-server-failure")
                        if !model.service.configured { Button(text("Retry")) { connect() }.disabled(model.incomplete || model.busy) }
                        Button(text("Close")) { model.dismissFailure() }
                    }
                }
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("music-server-connection")
        }.onDisappear { operation?.cancel(); operation = nil; model.close() }
    }
    private func text(_ key: String, variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }
    private func connect() {
        operation?.cancel(); operation = Task { if await model.connect() { onChange() } }
    }
}
