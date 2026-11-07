import SwiftUI

/// Desktop's Letterboxd panel (`settings/letterboxd-panel.tsx`): connect in Public or Full mode, choose the catalogs, add lists.
/// Not ported: the review scraper, the stream actions and the film-page panel, which need Desktop pages this app does not have.
struct LetterboxdSettingsView: View {
    private struct CatalogOption: Identifiable {
        let id: String
        let label: String
        let sub: String
        let fullOnly: Bool
    }

    private static let catalogOptions: [CatalogOption] = [
        CatalogOption(id: StremboxdCatalogID.watchlist, label: "Watchlist", sub: "Shows the films you have saved to watch on Letterboxd.", fullOnly: false),
        CatalogOption(id: StremboxdCatalogID.diary, label: "Diary", sub: "Shows everything you have logged, most recent first.", fullOnly: true),
        CatalogOption(id: StremboxdCatalogID.liked, label: "Liked Films", sub: "Shows the films you have hearted on Letterboxd.", fullOnly: false),
        CatalogOption(id: StremboxdCatalogID.friends, label: "Friends", sub: "Shows what the people you follow have been watching lately.", fullOnly: true),
        CatalogOption(id: StremboxdCatalogID.recommended, label: "Recommended for You", sub: "Shows the picks Letterboxd makes from your own viewing history.", fullOnly: true),
        CatalogOption(id: StremboxdCatalogID.popular, label: "Popular This Week", sub: "Shows the films the whole of Letterboxd is watching right now.", fullOnly: false),
        CatalogOption(id: StremboxdCatalogID.top250, label: "Top 250", sub: "Shows the highest rated narrative features of all time.", fullOnly: false),
    ]

    @State private var account: StremboxdAccount
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var busy = false
    @State private var verification: StremboxdVerification?
    @State private var loginError: String?
    @State private var listAddress = ""
    @State private var listBusy = false
    @State private var listError: String?

    @MainActor init(app: AppModel) {
        _account = State(initialValue: StremboxdAccount.forOwner(app.personalOwner))
    }

    private func text(_ key: String, _ variables: [String: String] = [:]) -> String {
        DesktopInterfaceText.value(key, variables: variables)
    }

    private var isFullMode: Bool { account.settings.mode == .full }

    private var modeBinding: Binding<StremboxdMode> {
        Binding(get: { account.settings.mode }, set: { (mode: StremboxdMode) in account.update { (value: inout StremboxdSettings) in value.mode = mode } })
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { account.settings.enabled }, set: { (on: Bool) in account.update { (value: inout StremboxdSettings) in value.enabled = on } })
    }

    private var ratingsBinding: Binding<Bool> {
        Binding(get: { account.settings.showRatingsOnPosters }, set: { (on: Bool) in account.setShowRatingsOnPosters(on) })
    }

    private func catalogBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { account.settings.selectedCatalogs.contains(id) }, set: { (on: Bool) in
            account.setCatalog(id, on: on)
            Task { await account.syncPreferences() }
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("desktop-bookmark").resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text("Letterboxd")).font(HarborTheme.font(24, weight: .semibold))
                        Text(text("Bring your Letterboxd watchlist, diary, liked films and lists into Harbor through the Stremboxd bridge."))
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HarborSettingsToggle(text("Enable Letterboxd integration"),
                                     note: text("Turning this on adds your Letterboxd catalogs to the home page and a Letterboxd panel to every film page."),
                                     isOn: enabledBinding)
                    .accessibilityIdentifier("letterboxd-enabled")
                if account.settings.enabled {
                    connectionSection
                    catalogsSection
                    listsSection
                    screenSection
                }
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Letterboxd")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("letterboxd-settings-scroll")
            .task { username = account.settings.username }
    }

    // MARK: Connection

    private var connectionSection: some View {
        HarborSettingsSection("Connection") {
            Text(text("Mode")).font(HarborTheme.font(16, weight: .medium))
            HarborSettingsSegmented(selection: modeBinding, choices: [(text("Public"), StremboxdMode.publicMode), (text("Full"), StremboxdMode.full)])
            Text(modeDescription).font(HarborTheme.font(14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(text("Letterboxd username")).font(HarborTheme.font(16, weight: .medium))
                Text(text("The handle in your profile address, letterboxd.com/your-name.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                TextField(text("your-name"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding(12)
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("letterboxd-username")
            }
            if isFullMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text("Letterboxd password")).font(HarborTheme.font(16, weight: .medium))
                    Text(text("Sent once to Stremboxd to obtain a sign-in token. Harbor never keeps it.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    SecureField(text("Your Letterboxd password"), text: $password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().padding(12)
                        .background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("letterboxd-password")
                    if let loginError = loginError {
                        Text(text(loginError)).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("letterboxd-login-error")
                    }
                }
                if needsCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text("Two-factor authentication code")).font(HarborTheme.font(16, weight: .medium))
                        Text(text("Letterboxd asked for a second step. Enter the six digit code, then connect again.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                        TextField(text("123456"), text: $code).keyboardType(.numberPad).autocorrectionDisabled().padding(12)
                            .background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("letterboxd-code")
                    }
                }
            }
            Button { connect() } label: {
                Text(connectTitle).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(HarborAccountButtonStyle(primary: true))
            .disabled(connectDisabled)
            .accessibilityIdentifier("letterboxd-connect")
            Text(isFullMode ? text("Signs in to Letterboxd and unlocks your diary, friends activity and ratings.") : text("Checks the username against Stremboxd and turns on the catalogs it finds."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let verification = verification { verificationRow(verification) }
            if let session = account.session {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text("Signed in")).font(HarborTheme.font(16, weight: .medium))
                    Text(signedInLine(session)).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(role: .destructive) { account.signOut() } label: {
                        Text(text("Disconnect")).frame(minHeight: 44)
                    }
                    .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("letterboxd-disconnect")
                }
            }
            if let site = StremboxdURL.configure {
                Link(destination: site) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text("About Stremboxd")).font(HarborTheme.font(16, weight: .medium))
                        Text(text("Opens stremboxd.com, the community bridge that reads Letterboxd on Harbor's behalf.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                }
                .accessibilityIdentifier("letterboxd-about")
            }
        }
    }

    private var modeDescription: String {
        if isFullMode {
            return text("Full mode signs in with your Letterboxd password so your diary, friends activity and personal ratings work too. The password goes only to Stremboxd to fetch a token, and Harbor never stores it.")
        }
        return text("Public mode reads your account with nothing but your username. You get your watchlist, liked films, popular this week and the Top 250, and no password is needed.")
    }

    private var connectTitle: String {
        if isFullMode { return needsCode ? text("Verify & connect") : text("Connect") }
        return text("Connect")
    }

    private var connectDisabled: Bool {
        if busy || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return isFullMode && password.isEmpty
    }

    private func signedInLine(_ session: StremboxdSession) -> String {
        var identity = "@" + session.username
        if let displayName = session.displayName, !displayName.isEmpty {
            identity = displayName + " (@" + session.username + ")"
        }
        return identity + ". " + text("Full mode is active, so diary, friends activity and your ratings all work.")
    }

    @ViewBuilder
    private func verificationRow(_ result: StremboxdVerification) -> some View {
        switch result {
        case .connected(let catalogs):
            Label(text("Connected. {n} catalogs are available.", ["n": String(catalogs)]), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).accessibilityIdentifier("letterboxd-verified")
        case .failed(let message):
            Label(text(message), systemImage: "xmark.circle.fill").foregroundStyle(.red).accessibilityIdentifier("letterboxd-verify-error")
        case .httpFailed(let status):
            Label(text("Stremboxd error ({status}).", ["status": String(status)]), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).accessibilityIdentifier("letterboxd-verify-error")
        }
    }

    private func connect() {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        loginError = nil
        verification = nil
        Task {
            if isFullMode {
                let outcome = await account.signIn(username: name, password: password, code: needsCode ? code : nil)
                switch outcome {
                case .signedIn:
                    password = ""
                    code = ""
                    needsCode = false
                    username = account.settings.username
                case .needsCode:
                    needsCode = true
                case .failed(let message):
                    loginError = message
                }
            } else {
                verification = await account.verifyPublic(username: name)
            }
            busy = false
        }
    }

    // MARK: Catalogs and lists

    private var catalogsSection: some View {
        HarborSettingsSection("Catalogs to show") {
            ForEach(Self.catalogOptions) { option in
                let locked = option.fullOnly && account.session == nil
                VStack(alignment: .leading, spacing: 6) {
                    HarborSettingsToggle(text(option.label), note: text(option.sub), isOn: catalogBinding(option.id))
                        .accessibilityIdentifier("letterboxd-catalog-" + option.id)
                    if locked {
                        Text(text("Sign in with Full mode to use this catalog.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(locked)
            }
        }
    }

    private var listsSection: some View {
        HarborSettingsSection("Custom lists") {
            VStack(alignment: .leading, spacing: 8) {
                Text(text("Add a list")).font(HarborTheme.font(16, weight: .medium))
                Text(text("Paste the address of any public Letterboxd list to add it as its own row.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                TextField(text("letterboxd.com/username/list/slug"), text: $listAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding(12)
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("letterboxd-list-address")
                if let listError = listError {
                    Text(listError).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("letterboxd-list-error")
                }
                Button { addList() } label: {
                    Label(text("Add"), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(HarborAccountButtonStyle())
                .disabled(listBusy || listAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("letterboxd-add-list")
            }
            ForEach(account.settings.listRefs, id: \.id) { ref in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ref.name).font(HarborTheme.font(16, weight: .medium))
                        Text(listMeta(ref)).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(role: .destructive) { removeList(ref.id) } label: {
                        Text(text("Remove")).frame(minHeight: 44)
                    }
                    .buttonStyle(HarborAccountButtonStyle())
                }
            }
        }
    }

    private func listMeta(_ ref: StremboxdListRef) -> String {
        let owner = ref.owner ?? ""
        if !owner.isEmpty, let count = ref.filmCount {
            return text("A list by {owner}, {n} films.", ["owner": owner, "n": String(count)])
        }
        if !owner.isEmpty { return text("A list by {owner}.", ["owner": owner]) }
        if let count = ref.filmCount { return text("{n} films.", ["n": String(count)]) }
        return text("A Letterboxd list you added by address.")
    }

    private func addList() {
        let address = listAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        listBusy = true
        listError = nil
        Task {
            do {
                try await account.addList(address)
                listAddress = ""
                await account.syncPreferences()
            } catch {
                listError = text("Could not resolve that Letterboxd list URL.")
            }
            listBusy = false
        }
    }

    private func removeList(_ id: String) {
        account.removeList(id)
        Task { await account.syncPreferences() }
    }

    // MARK: On screen

    private var screenSection: some View {
        HarborSettingsSection("On screen") {
            HarborSettingsToggle(text("Show my rating on movie posters"),
                                 note: text("Puts the score you gave a film in the corner of its poster, wherever Letterboxd has one for you."),
                                 isOn: ratingsBinding)
                .accessibilityIdentifier("letterboxd-ratings")
        }
    }
}
