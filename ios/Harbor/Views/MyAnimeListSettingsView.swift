import SwiftUI

/// Desktop's MyAnimeList panel (`settings/mal-panel.tsx`): connect with a pasted code, sync watch progress.
/// The lists and the avatar option of that panel are not ported.
struct MyAnimeListSettingsView: View {
    @State private var account: MALAccount
    @State private var connectModel: MALConnectModel
    @State private var connecting = false
    @State private var disconnecting = false
    @State private var loadFailed = false
    @AppStorage("malAutoSync") private var autoSync = true
    @MainActor init(app: AppModel) {
        let account = MALAccount.forOwner(app.personalOwner)
        _account = State(initialValue: account); _connectModel = State(initialValue: MALConnectModel(account: account))
    }
    private func text(_ key: String, _ variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("tracker-mal").resizable().scaledToFit().frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MyAnimeList").font(HarborTheme.font(24, weight: .semibold))
                        Text(text(account.session == nil ? "Not connected" : "Connected")).foregroundStyle(.secondary)
                            .accessibilityIdentifier("mal-connection-state")
                    }
                }
                if let session = account.session {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.userName).font(HarborTheme.font(18, weight: .medium)).accessibilityIdentifier("mal-account-name")
                        Text(text("Authorized {when}", ["when": AniListSettingsView.age(since: session.createdAt)])).font(.caption).foregroundStyle(.secondary)
                    }
                    if let profile = URL(string: "https://myanimelist.net/profile/" + (session.userName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session.userName)) {
                        Link(destination: profile) { Label("myanimelist.net", systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                            .accessibilityIdentifier("mal-profile")
                    }
                    Text(text("Harbor keeps your MyAnimeList watch progress in sync.")).font(.callout).foregroundStyle(.secondary)
                    HarborSettingsToggle(text("Sync watch progress"),
                                         note: text("Finishing an anime episode updates your MyAnimeList progress. Forward only: it never lowers a count you already have."),
                                         isOn: $autoSync).accessibilityIdentifier("mal-auto-sync")
                    if let event = account.lastEvent { Text(Self.summary(event)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("mal-last-sync") }
                    Button(role: .destructive) { disconnecting = true } label: { Text(text("Disconnect")).frame(minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("mal-disconnect")
                } else {
                    Text(text("Bring your anime list into Harbor and update your episode count as you watch. Your existing progress is kept.")).foregroundStyle(.secondary)
                    Button { connecting = true } label: { Text(text("Connect MyAnimeList")).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!account.ready)
                        .accessibilityIdentifier("mal-connect")
                    Link(destination: MALAuth.siteURL) { Label("myanimelist.net", systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                        .accessibilityIdentifier("mal-website")
                }
                if loadFailed { Button(text("Retry")) { load() }.frame(minHeight: 44).accessibilityIdentifier("mal-reload") }
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle("MyAnimeList").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("mal-settings-scroll")
            .task { load(); await account.validate() }
            .sheet(isPresented: $connecting) {
                MALConnectView(model: connectModel).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .confirmationDialog(text("Disconnect from MyAnimeList"), isPresented: $disconnecting, titleVisibility: .visible) {
                Button(text("Disconnect"), role: .destructive) { try? account.set(nil) }
                Button(text("Cancel"), role: .cancel) { }
            } message: {
                Text(text("Disconnect MyAnimeList? Your progress will stop syncing until you reconnect."))
            }
    }

    private func load() {
        do { if !account.ready { try account.load() }; loadFailed = false } catch { loadFailed = true }
    }

    static func summary(_ event: AniListSyncEvent) -> String {
        switch event {
        case .syncing(let title, let episode): return DesktopInterfaceText.value("Syncing to MyAnimeList") + " · " + DesktopInterfaceText.value("{title} · Episode {episode}", variables: ["title": title, "episode": String(episode)])
        case .ok(let title, let episode): return DesktopInterfaceText.value("Synced to MyAnimeList") + " · " + DesktopInterfaceText.value("{title} · Episode {episode}", variables: ["title": title, "episode": String(episode)])
        case .watching(let title): return DesktopInterfaceText.value("Now watching on MyAnimeList") + " · " + title
        case .error(_, let reason):
            return DesktopInterfaceText.value("MyAnimeList sync") + " · " + DesktopInterfaceText.value(reason == .updateNotConfirmed ? "MAL did not confirm the update." : "Couldn't reach MyAnimeList.")
        }
    }
}

/// Desktop's `MalConnectModal`.
private struct MALConnectView: View {
    let model: MALConnectModel
    @State private var code = ""
    @State private var started = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    private func text(_ key: String, _ variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }

    private var heading: String {
        switch model.state {
        case .success: text("Connected")
        case .verifying: text("Verifying")
        default: text("Authorize Harbor on MyAnimeList")
        }
    }

    private func openAuthorization() {
        if let url = model.begin() { openURL(url) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(heading).font(HarborTheme.font(22, weight: .semibold))
                    switch model.state {
                    case .idle:
                        HStack(spacing: 10) { ProgressView(); Text(text("Opening MyAnimeList...")).foregroundStyle(.secondary) }
                    case .needsCode:
                        Text(text("A browser tab opened on MyAnimeList. Approve Harbor there, then copy the code or the page URL and paste it below.")).foregroundStyle(.secondary)
                        TextField(text("Paste the code or page URL"), text: $code, axis: .vertical)
                            .lineLimit(3...6).textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.callout, design: .monospaced))
                            .padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("mal-code")
                        HStack(spacing: 10) {
                            Button { openAuthorization() } label: { Label(text("Open MyAnimeList again"), systemImage: "arrow.up.right.square").frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("mal-open-again")
                            Button { model.submit(code) } label: { Text(text("Connect")).frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("mal-submit-code")
                        }
                    case .verifying:
                        HStack(spacing: 10) { ProgressView(); Text(text("Checking with MyAnimeList...")).foregroundStyle(.secondary) }
                    case .success(let name):
                        Label(name.isEmpty ? text("Connected to MyAnimeList") : text("Connected as {username}", ["username": name]), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).accessibilityIdentifier("mal-authorized")
                    case .failure(let message):
                        VStack(alignment: .leading, spacing: 6) {
                            Text(text("Couldn't connect to MyAnimeList")).font(HarborTheme.font(14, weight: .semibold)).foregroundStyle(.orange)
                            Text(message).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("mal-error")
                        }
                        Button { openAuthorization() } label: { Text(text("Try again")).frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("mal-retry")
                    }
                }.padding(22).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
                .navigationTitle(text("Connect MyAnimeList")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { model.cancel(); dismiss() }.accessibilityIdentifier("mal-cancel") } }
        }.task {
            guard !started else { return }
            started = true; openAuthorization()
        }
        .task(id: model.state) {
            if case .success = model.state { try? await Task.sleep(for: .milliseconds(1_400)); if !Task.isCancelled { dismiss() } }
        }
        .onDisappear { if case .success = model.state { return }; model.cancel() }
    }
}
