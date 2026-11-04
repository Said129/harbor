import SwiftUI

/// Desktop's "Debrid services" tab of the streaming sources panel. Keys are
/// stored in the Keychain for this profile only and are never shown again.
@MainActor struct DebridSettingsView: View {
    private enum Status: Equatable {
        case checking, active(days: Int?), expired, failed(String)
    }
    /// The profile's shared client, so a key saved here serves the next playback.
    private let client: DebridClient
    @State private var drafts: [DebridProvider: String] = [:]
    @State private var status: [DebridProvider: Status] = [:]
    @State private var saved: DebridProvider?
    @State private var failure: String?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    /// The scope is the active profile's; a locked app has none and never offers this page.
    init(app: AppModel, scope: PluginExecutionScope) {
        client = DebridClientCache.shared.client(for: scope) { [weak app] in
            app?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(text("Debrid services")).font(HarborTheme.displayFont(30)).accessibilityAddTraits(.isHeader)
                Text(text("Real-Debrid, TorBox, AllDebrid, Premiumize, Debrid-Link. Cached streams play direct. Keys stay local."))
                    .font(.subheadline).foregroundStyle(.secondary)
                if client.keyFailure || failure != nil {
                    Text(failure ?? text("Retry")).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("debrid-error")
                }
                ForEach(DebridProvider.allCases) { provider in field(provider) }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Debrid services")).navigationBarTitleDisplayMode(.inline)
            .task { for provider in client.providers { await check(provider) } }
            .accessibilityIdentifier("debrid-settings")
    }

    private func field(_ provider: DebridProvider) -> some View {
        let draft = Binding(get: { drafts[provider] ?? "" }, set: { drafts[provider] = $0; if saved == provider { saved = nil } })
        let page = provider.keyPage
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text(provider.keyLabel)).font(.headline)
                Spacer(minLength: 8)
                badge(provider)
            }
            HStack(spacing: 10) {
                SecureField(client.hasKey(provider) ? "••••••••••" : text(provider.placeholder), text: draft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.password)
                    .padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                    .accessibilityLabel(text(provider.keyLabel)).accessibilityIdentifier("debrid-key-" + provider.rawValue)
                Button(text(saved == provider ? "Saved" : "Save")) { save(provider) }
                    .buttonStyle(HarborAccountButtonStyle()).disabled((drafts[provider] ?? "").isEmpty)
                    .accessibilityIdentifier("debrid-save-" + provider.rawValue)
                if client.hasKey(provider) {
                    Button(text("Remove"), role: .destructive) { remove(provider) }
                        .accessibilityIdentifier("debrid-remove-" + provider.rawValue)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(text("Get yours at"))
                    if let url = URL(string: page.url) { Link(page.label, destination: url) }
                }
                Text(text(provider.note))
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func badge(_ provider: DebridProvider) -> some View {
        switch status[provider] {
        case .checking: ProgressView().controlSize(.small)
        case .active(let days):
            Label(days.map { DesktopInterfaceText.value("{n}d left", variables: ["n": String($0)]) } ?? text("Active"), systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .expired: Label(text("Expired"), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        case .failed(let code): Text(code).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("debrid-status-" + provider.rawValue)
        case nil: EmptyView()
        }
    }

    private func save(_ provider: DebridProvider) {
        do {
            try client.saveKey(drafts[provider] ?? "", for: provider)
            drafts[provider] = ""; saved = provider; failure = nil
            Task { await check(provider) }
        } catch { failure = safeMessage(error) }
    }
    private func remove(_ provider: DebridProvider) {
        do { try client.saveKey("", for: provider); drafts[provider] = ""; status[provider] = nil; saved = nil; failure = nil }
        catch { failure = safeMessage(error) }
    }
    /// An account lookup only; Harbor never adds or removes anything on the account.
    private func check(_ provider: DebridProvider) async {
        guard client.hasKey(provider) else { return }
        status[provider] = .checking
        do {
            switch try await client.account(provider) {
            case .success(let account):
                if !account.premium { status[provider] = .expired }
                else {
                    let days = account.premiumUntil.map { Calendar.current.dateComponents([.day], from: .now, to: Date(timeIntervalSince1970: $0)).day ?? 0 }
                    status[provider] = (days ?? 1) < 0 ? .expired : .active(days: days.map { max(0, $0) })
                }
            case .failure(let code, _): status[provider] = .failed(code)
            }
        } catch is CancellationError { }
        catch { status[provider] = .failed("network-error") }
    }
}
