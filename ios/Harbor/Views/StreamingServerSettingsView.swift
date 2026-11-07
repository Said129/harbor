import SwiftUI

/// Desktop's "Remote streaming server" section (`views/settings/player-panel/remote-server-section.tsx`):
/// the address of a streaming server on another machine, the strict policy and a connection test.
struct StreamingServerSettingsView: View {
    @Bindable private var preferences = StremioServerPreferences.shared
    @State private var draft = ""
    @State private var reachable: Bool?
    @State private var outcome: StreamingServerTestOutcome?
    @State private var testing = false
    @FocusState private var addressFocused: Bool
    private let client = StremioServerClient(transport: StremioServerHTTPTransport())
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(text("Remote streaming server")).font(HarborTheme.displayFont(30)).accessibilityAddTraits(.isHeader)
                Text(text("Point Harbor at a streaming server on another machine, like the Stremio service on a home server. P2P streams download and play from that machine instead of this one."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HarborSettingsSection("Connection") {
                    addressRow
                    if !preferences.address.isEmpty {
                        HarborSettingsToggle("Use exclusively (never fall back to local)",
                                             note: "If the remote server is unavailable, stop playback instead of streaming over P2P from this device.",
                                             isOn: $preferences.remoteStreamServerStrict)
                        testRow
                    }
                    if let outcome { resultCard(outcome) }
                }
            }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).buttonStyle(.plain)
            .navigationTitle(text("Remote streaming server")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("streaming-server-settings")
            .onAppear { draft = preferences.remoteStreamServerUrl }
            .task(id: preferences.address) { await probeSaved() }
            .onChange(of: addressFocused) { _, focused in if !focused { commit() } }
    }

    // MARK: Address

    private var addressRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(text("Server address")).font(HarborTheme.font(14, weight: .semibold))
                connectionBadge
            }
            Text(text("The address of the streaming server, including its port.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                addressField
                if !preferences.address.isEmpty {
                    Button(text("Forget")) { forget() }
                        .buttonStyle(HarborAccountButtonStyle())
                        .accessibilityLabel(text("Forget remote streaming server"))
                }
            }
        }
    }

    private var addressField: some View {
        TextField(text("http://192.168.1.50:11470"), text: $draft)
            .focused($addressFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .onSubmit { commit() }
            .accessibilityLabel(text("Server address"))
            .padding(12)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }
    }

    private var connectionBadge: some View {
        let state = StremioServerPolicy.connection(address: preferences.address, reachable: reachable)
        return Text(text(badgeTitle(state))).font(HarborTheme.font(12, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(HarborTheme.surface, in: .capsule)
            .foregroundStyle(badgeColor(state))
            .accessibilityIdentifier("streaming-server-status")
    }

    private func badgeTitle(_ state: StremioServerPolicy.Connection) -> String {
        switch state {
        case .notSet: "Not set"
        case .checking: "Checking"
        case .connected: "Connected"
        case .unreachable: "Unreachable"
        }
    }

    private func badgeColor(_ state: StremioServerPolicy.Connection) -> Color {
        switch state {
        case .connected: .green
        case .unreachable: .red
        case .notSet, .checking: .secondary
        }
    }

    // MARK: Test

    private var testRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(text("Test connection")).font(HarborTheme.font(14, weight: .semibold))
                Text(text("Check whether this device can reach the saved server address.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                Task { await runTest() }
            } label: {
                HStack(spacing: 8) {
                    if testing { ProgressView().controlSize(.small) } else { Image(systemName: "wifi") }
                    Text(text(testing ? "Testing" : "Run test"))
                }
            }
            .buttonStyle(HarborAccountButtonStyle())
            .disabled(testing)
            .accessibilityLabel(text(testing ? "Testing remote streaming server" : "Test remote streaming server"))
            .accessibilityIdentifier("streaming-server-test")
        }.frame(minHeight: 44)
    }

    private func resultCard(_ result: StreamingServerTestOutcome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.ok ? "checkmark" : "xmark")
                .foregroundStyle(result.ok ? Color.green : Color.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(text(result.ok ? "Server reachable" : "Test failed"))
                    .font(HarborTheme.font(16, weight: .medium))
                    .foregroundStyle(result.ok ? HarborTheme.ink : Color.red)
                Text(result.message).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(HarborTheme.surface, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("streaming-server-test-result")
    }

    // MARK: Actions

    /// Desktop's `commit`: the address is normalized when the field loses focus or is submitted.
    private func commit() {
        let normalized = StremioServerPolicy.normalized(draft)
        draft = normalized
        if normalized != preferences.remoteStreamServerUrl { preferences.remoteStreamServerUrl = normalized }
    }

    private func forget() {
        draft = ""
        preferences.remoteStreamServerUrl = ""
    }

    /// Desktop probes the saved address when it changes and only shows the status pill.
    private func probeSaved() async {
        let base = preferences.address
        reachable = nil
        outcome = nil
        guard !base.isEmpty else { return }
        let health = await client.health(base: base)
        guard base == preferences.address else { return }
        reachable = StreamingServerTestOutcome(health).ok
    }

    /// Desktop's "Run test": the same probe, with the result card shown.
    private func runTest() async {
        let base = preferences.address
        guard !base.isEmpty, !testing else { return }
        testing = true
        outcome = nil
        let health = await client.health(base: base)
        testing = false
        guard base == preferences.address else { return }
        let result = StreamingServerTestOutcome(health)
        outcome = result
        reachable = result.ok
    }
}

/// The result card of Desktop's test: the outcome of the health probe, with Desktop's message.
struct StreamingServerTestOutcome: Equatable {
    let ok: Bool
    let message: String

    init(_ health: StremioServerPolicy.Health) {
        switch health {
        case .reachable(let milliseconds):
            ok = true
            message = DesktopInterfaceText.value("The server responded in {ms} ms.", variables: ["ms": String(milliseconds)])
        case .badStatus(let status):
            ok = false
            message = DesktopInterfaceText.value("The server answered with status {status}. Is that a streaming server?", variables: ["status": String(status)])
        case .unreachable:
            ok = false
            message = DesktopInterfaceText.value("Could not reach the server within 1.5 seconds. Check the address and that the server machine is online.")
        }
    }
}
