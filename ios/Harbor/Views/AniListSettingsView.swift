import SwiftUI

/// Desktop's AniList panel (`settings/anilist-panel.tsx`): connect with a pasted code, sync watch progress.
/// The lists, comments and avatar options of that panel are not ported.
struct AniListSettingsView: View {
    @State private var account: AniListAccount
    @State private var connectModel: AniListConnectModel
    @State private var connecting = false
    @State private var disconnecting = false
    @State private var loadFailed = false
    @AppStorage("anilistAutoSync") private var autoSync = true
    @MainActor init(app: AppModel) {
        let account = AniListAccount.forOwner(app.personalOwner)
        _account = State(initialValue: account); _connectModel = State(initialValue: AniListConnectModel(account: account))
    }
    private func text(_ key: String, _ variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("tracker-anilist").resizable().scaledToFit().frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AniList").font(HarborTheme.font(24, weight: .semibold))
                        Text(text(account.session == nil ? "Not connected" : "Connected")).foregroundStyle(.secondary)
                            .accessibilityIdentifier("anilist-connection-state")
                    }
                }
                if let session = account.session {
                    HStack(spacing: 12) {
                        if let avatar = session.avatar {
                            Artwork(url: avatar, maxPixels: 160, showsPlaceholder: false).frame(width: 44, height: 44).clipShape(.circle).accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.userName).font(HarborTheme.font(18, weight: .medium)).accessibilityIdentifier("anilist-account-name")
                            Text(text("Authorized {when}", ["when": Self.age(since: session.createdAt)])).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let profile = URL(string: "https://anilist.co/user/" + (session.userName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session.userName)) {
                        Link(destination: profile) { Label("anilist.co", systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                            .accessibilityIdentifier("anilist-profile")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(text("Tracking what you watch")).font(HarborTheme.font(13, weight: .semibold)).foregroundStyle(.secondary)
                        HarborSettingsToggle(text("Sync watch progress"),
                                             note: text("Finishing an anime episode updates your AniList progress. Forward only: it never lowers a count you already have."),
                                             isOn: $autoSync).accessibilityIdentifier("anilist-auto-sync")
                    }
                    if let event = account.lastEvent { Text(Self.summary(event)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("anilist-last-sync") }
                    Button(role: .destructive) { disconnecting = true } label: { Text(text("Disconnect")).frame(minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("anilist-disconnect")
                } else {
                    Text(text("Browse your anime lists in Harbor and update your episode progress as you watch. Sign in to AniList to connect.")).foregroundStyle(.secondary)
                    Button { connecting = true } label: { Text(text("Connect AniList")).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!account.ready)
                        .accessibilityIdentifier("anilist-connect")
                    Link(destination: AniListAuth.siteURL) { Label("anilist.co", systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                        .accessibilityIdentifier("anilist-website")
                }
                if loadFailed { Button(text("Retry")) { load() }.frame(minHeight: 44).accessibilityIdentifier("anilist-reload") }
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle("AniList").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("anilist-settings-scroll")
            .task { load(); await account.validate() }
            .sheet(isPresented: $connecting) {
                AniListConnectView(model: connectModel).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .confirmationDialog(text("Disconnect from AniList"), isPresented: $disconnecting, titleVisibility: .visible) {
                Button(text("Disconnect"), role: .destructive) { try? account.set(nil) }
                Button(text("Cancel"), role: .cancel) { }
            } message: {
                Text(text("Disconnect AniList? Your lists will stop showing on the Anime page until you reconnect."))
            }
    }

    private func load() {
        do { if !account.ready { try account.load() }; loadFailed = false } catch { loadFailed = true }
    }

    /// Desktop's `sessionAge`.
    static func age(since createdAt: Double, now: Date = Date()) -> String {
        let days = Int((now.timeIntervalSince1970 * 1_000 - createdAt) / 86_400_000)
        if days < 1 { return DesktopInterfaceText.value("today") }
        if days < 30 { return DesktopInterfaceText.value(days == 1 ? "{n} day ago" : "{n} days ago", variables: ["n": String(days)]) }
        let months = days / 30
        return DesktopInterfaceText.value(months == 1 ? "{n} month ago" : "{n} months ago", variables: ["n": String(months)])
    }

    static func summary(_ event: AniListSyncEvent) -> String {
        switch event {
        case .syncing(let title, let episode): return DesktopInterfaceText.value("Syncing to AniList") + " · " + DesktopInterfaceText.value("{title} · Episode {episode}", variables: ["title": title, "episode": String(episode)])
        case .ok(let title, let episode): return DesktopInterfaceText.value("Synced to AniList") + " · " + DesktopInterfaceText.value("{title} · Episode {episode}", variables: ["title": title, "episode": String(episode)])
        case .watching(let title): return DesktopInterfaceText.value("Now watching on AniList") + " · " + title
        case .error(_, let reason):
            return DesktopInterfaceText.value("AniList sync") + " · " + DesktopInterfaceText.value(reason == .updateNotConfirmed ? "AniList did not confirm the update." : "Couldn't reach AniList.")
        }
    }
}

/// Desktop's `AnilistConnectModal`.
private struct AniListConnectView: View {
    let model: AniListConnectModel
    @State private var code = ""
    @State private var started = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    private func text(_ key: String, _ variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }

    private var heading: String {
        switch model.state {
        case .success: text("Connected")
        case .verifying: text("Verifying")
        default: text("Authorize Harbor on AniList")
        }
    }

    private func openAuthorization() {
        if let url = AniListAuth.authorizeURL() { openURL(url) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(heading).font(HarborTheme.font(22, weight: .semibold))
                    switch model.state {
                    case .idle:
                        HStack(spacing: 10) { ProgressView(); Text(text("Opening AniList...")).foregroundStyle(.secondary) }
                    case .needsCode:
                        Text(text("A browser tab opened on AniList. Approve Harbor there, then copy the text it shows and paste it below.")).foregroundStyle(.secondary)
                        TextField(text("Paste the text from AniList"), text: $code, axis: .vertical)
                            .lineLimit(3...6).textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.callout, design: .monospaced))
                            .padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("anilist-code")
                        HStack(spacing: 10) {
                            Button { openAuthorization() } label: { Label(text("Open AniList again"), systemImage: "arrow.up.right.square").frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("anilist-open-again")
                            Button { model.submit(code) } label: { Text(text("Connect")).frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("anilist-submit-code")
                        }
                    case .verifying:
                        HStack(spacing: 10) { ProgressView(); Text(text("Checking with AniList...")).foregroundStyle(.secondary) }
                    case .success(let name):
                        Label(name.isEmpty ? text("Connected to AniList") : text("Connected as {username}", ["username": name]), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).accessibilityIdentifier("anilist-authorized")
                    case .failure(let message):
                        VStack(alignment: .leading, spacing: 6) {
                            Text(text("Couldn't connect to AniList")).font(HarborTheme.font(14, weight: .semibold)).foregroundStyle(.orange)
                            Text(message).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("anilist-error")
                        }
                        Button { model.begin(); openAuthorization() } label: { Text(text("Try again")).frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("anilist-retry")
                    }
                }.padding(22).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
                .navigationTitle(text("Connect AniList")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { model.cancel(); dismiss() }.accessibilityIdentifier("anilist-cancel") } }
        }.task {
            guard !started else { return }
            started = true; model.begin(); openAuthorization()
        }
        .task(id: model.state) {
            if case .success = model.state { try? await Task.sleep(for: .milliseconds(1_400)); if !Task.isCancelled { dismiss() } }
        }
        .onDisappear { if case .success = model.state { return }; model.cancel() }
    }
}
