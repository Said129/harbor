import SwiftUI

/// Settings > Watch Together: the relay URL (Desktop's "Harbor Relay" section, without deploy or health checks, which
/// need the Cloudflare API) and the two toggles. `togetherShareCursors` is stored only, since cursors are not shown.
struct TogetherSettingsView: View {
    @State private var preferences = TogetherPreferences.shared
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text(DesktopInterfaceText.value("Only enter URLs for relays you operate or trust. A relay only carries Watch Together sync messages (play, pause, seek). Nothing else passes through it."))
                    .font(.footnote)
            }
            currentRelaySection
            publicRelaySection
            customRelaySection
            optionsSection
        }
        .navigationTitle(DesktopInterfaceText.value("Watch Together"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var currentRelaySection: some View {
        Section {
            if preferences.relayURL.isEmpty {
                Text(DesktopInterfaceText.value("Watch Together needs a relay."))
            } else {
                Text(preferences.relayURL)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    preferences.setRelayURL("")
                } label: {
                    Text(DesktopInterfaceText.value("Change"))
                }
                Text(DesktopInterfaceText.value("Clears the saved URL so you can point Harbor at another relay."))
                    .font(.footnote)
            }
        } header: {
            Text(DesktopInterfaceText.value("Harbor Relay"))
        }
    }

    @ViewBuilder private var publicRelaySection: some View {
        Section {
            Text(DesktopInterfaceText.value("A relay we run. Nothing to set up, and it stays current on its own."))
                .font(.footnote)
            Button {
                preferences.setRelayURL(TogetherProtocol.publicRelayURL)
            } label: {
                Text(DesktopInterfaceText.value("Use Harbor's public relay"))
            }
        } header: {
            Text(DesktopInterfaceText.value("Harbor's public relay"))
        }
    }

    @ViewBuilder private var customRelaySection: some View {
        Section {
            Text(DesktopInterfaceText.value("Enter an existing relay URL:"))
            TextField(DesktopInterfaceText.value("wss://your-relay.workers.dev"), text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Text(DesktopInterfaceText.value("Use the wss:// scheme, not https://."))
                .font(.footnote)
            if let error = error {
                Text(DesktopInterfaceText.value(error))
                    .foregroundStyle(.red)
            }
            Button {
                saveDraft()
            } label: {
                Text(DesktopInterfaceText.value("Save"))
            }
            .disabled(draft.togetherTrimmed.isEmpty)
        } header: {
            Text(DesktopInterfaceText.value("Use an existing relay"))
        }
    }

    @ViewBuilder private var optionsSection: some View {
        Section {
            Toggle(DesktopInterfaceText.value("Show cursors"), isOn: Binding(
                get: { preferences.shareCursors },
                set: { preferences.setShareCursors($0) }
            ))
            Toggle(DesktopInterfaceText.value("Guests pick their own source"), isOn: Binding(
                get: { preferences.guestsPick },
                set: { preferences.setGuestsPick($0) }
            ))
        } footer: {
            Text(DesktopInterfaceText.value("Prompts guests to choose instead of auto-matching"))
        }
    }

    private func saveDraft() {
        let value = draft.togetherTrimmed
        guard TogetherRelay.hasWebSocketScheme(value) else {
            error = "Use the wss:// scheme, not https://."
            return
        }
        error = nil
        preferences.setRelayURL(value)
        draft = ""
    }
}
