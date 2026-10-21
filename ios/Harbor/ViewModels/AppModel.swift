import Foundation
import Observation

struct PendingProfileDocument: Identifiable {
    let id = UUID()
    let url: URL
    let profile: String?
}

@MainActor @Observable
final class AppModel {
    let service = HarborService()
    private let continuationMetadataStore = MediaMetadataStore()
    private(set) var resume = ResumeStore()
    let library = LibraryModel()
    let home = HomeContentModel()
    let animeDetection = AnimeLibraryDetection()
    let plugins = HarborPluginSession()
    let profileContext = AppProfileContext.shared
    private let accounts = AccountService()
    private var savedAccount: SavedAccount?
    private var homeGeneration = 0
    private var started = false
    @ObservationIgnored private var addonRefresh: (id: UUID, task: Task<AccountCollection, Error>)?
    private var lastAddonRefresh = Date.distantPast
    @ObservationIgnored private var pages: [String: ContentPageModel] = [:]
    private(set) var storageReady = false
    private(set) var addons: [Addon] = []
    private(set) var rows: [CatalogRow] = []
    private(set) var heroes: [Media] = []
    var loading = false
    var error: String?
    var warnings: [String] = []
    var progressError: String?
    var accountError: String?
    var accountBusy = false
    private(set) var switchingProfile = false
    var showAccount = false
    var showProfiles = false
    private(set) var automaticProfilePromptPending = false
    private var profilesAfterAccount = false
    var choosingProfile: Bool { showProfiles || profilesAfterAccount || profileContext.requiresSelection || switchingProfile }
    func prepareProfileAppearances() {
        for profile in profileContext.profiles.profiles where !profile.desktop.isKid {
            ProfilePreferences.forOwner(profileContext.profiles.appearanceOwner(profile)).bindHousehold(profileContext.profiles, id: profile.id)
        }
    }
    func openProfiles() {
        automaticProfilePromptPending = false
        prepareProfileAppearances()
        if showAccount { profilesAfterAccount = true; showAccount = false }
        else { showProfiles = true }
    }
    func accountDidDismiss() {
        if profilesAfterAccount { profilesAfterAccount = false; showProfiles = true }
    }
    func profileLaunchPreferences() throws -> ProfileLaunchPreferences {
        try ProfileSettingsStore.shared.launchPreferences(sharedOwner: profileContext.householdSettingsOwner)
    }
    func updateProfileLaunchPreferences(_ preferences: ProfileLaunchPreferences) throws {
        guard !accountBusy, storageReady, profileContext.ready,
              preferences.defaultID.isEmpty || preferences.defaultProfile(in: profileContext.profiles.profiles) != nil else { throw HarborError(code: "profile-settings-changed") }
        try ProfileSettingsStore.shared.setLaunchPreferences(preferences, sharedOwner: profileContext.householdSettingsOwner, expectedOwner: settingsOwner)
        if preferences.interval.seconds == nil { automaticProfilePromptPending = false }
    }
    func closeProfiles() async throws {
        if !storageReady {
            guard let active = profileContext.profiles.active, !active.desktop.isKid,
                  try await selectProfile(active.id, recordSelection: false) else { throw HarborError(code: "profile-selection-required") }
        }
        showProfiles = false
    }
    func requestProfilePromptOnReturn() {
        guard storageReady, profileContext.ready, !choosingProfile else { return }
        do {
            automaticProfilePromptPending = try profileLaunchPreferences().promptOnReturn(profiles: profileContext.profiles.profiles,
                lastSelected: ProfileSelectionClock(scope: profileContext.profiles.scope).lastSelected, now: Date().timeIntervalSince1970)
        } catch { Diagnostics.shared.recordFailure(error) }
    }
    @discardableResult func presentDeferredProfilePrompt() -> Bool {
        guard automaticProfilePromptPending, storageReady, profileContext.ready, !accountBusy, !showAccount,
              !choosingProfile, !profileContext.playback.hasActivePlayback else { return false }
        do {
            let due = try profileLaunchPreferences().promptOnReturn(profiles: profileContext.profiles.profiles,
                lastSelected: ProfileSelectionClock(scope: profileContext.profiles.scope).lastSelected, now: Date().timeIntervalSince1970)
            automaticProfilePromptPending = false
            if due { openProfiles() }
            return due
        } catch { automaticProfilePromptPending = false; Diagnostics.shared.recordFailure(error); return false }
    }
    func saveProfile(_ draft: HouseholdProfileDraft) async throws {
        guard !accountBusy, draft.kid == .null else { throw HarborError(code: "profile-editor-permission") }
        let result = try await profileContext.profiles.saveEditor(draft)
        if result.id == profileContext.profiles.state.selectedID { try await refreshSelectedProfile(recordSelection: draft.original == nil) }
    }
    func refreshSelectedProfile(recordSelection: Bool = false) async throws {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        let previous = profileContext.binding
        do { try profileContext.refreshRouting() }
        catch { storageReady = false; throw error }
        prepareProfileAppearances()
        if storageReady && profileContext.ready && previous == profileContext.binding { return }
        storageReady = false
        if let active = profileContext.profiles.active {
            guard try await selectProfile(active.id, recordSelection: recordSelection) else { throw HarborError(code: "profile-locked") }
        } else { showProfiles = true }
    }
    private(set) var pendingDocument: PendingProfileDocument?
    var user: AccountUser? { savedAccount?.session.user }
    var personalOwner: String { profileContext.binding?.personalOwner ?? user?.id ?? "guest" }
    var settingsOwner: String { profileContext.binding?.settingsOwner ?? user?.id ?? "guest" }
    var harborIdentityOwner: String { profileContext.binding?.identityOwner ?? profileContext.sessions.identityOwner ?? "guest" }
    var harborIdentity: ProfilePreferences { ProfilePreferences.forOwner(harborIdentityOwner) }
    var progressOwner: String { profileContext.binding?.progressOwner ?? user?.id ?? "guest" }
    var accountOperationScope: String { profileContext.activationID.uuidString + "|" + (profileContext.profiles.active?.id ?? "locked") }
    var interfaceProfileScope: String { profileContext.profiles.active?.id ?? "unbound" }
    private var documentOwner: String? {
        (profileContext.profiles.active ?? profileContext.profiles.requestedProfile).map { HouseholdProfileScope.hash([profileContext.profiles.scope.key, $0.id]) }
    }
    func openDocument(_ url: URL) {
        guard url.isFileURL, ["epub", "pdf"].contains(url.pathExtension.lowercased()) else { return }
        pendingDocument = PendingProfileDocument(url: url, profile: documentOwner)
    }
    func takePendingDocument() -> URL? {
        guard storageReady, profileContext.ready, !choosingProfile, let pendingDocument,
              pendingDocument.profile == nil || pendingDocument.profile == documentOwner else { return nil }
        self.pendingDocument = nil; return pendingDocument.url
    }
    func continuationMetadata(_ media: Media) async throws -> Media {
        let configuration = MetadataPreferences.shared.configuration()
        let selectedAddons = addons
        let key = try MediaMetadataStore.key(media, owner: library.owner, addons: selectedAddons, configuration: configuration)
        let service = service
        let result = try await continuationMetadataStore.value(for: key) {
            try await service.metadata(media, addons: selectedAddons, configuration: configuration)
        }
        animeDetection.observe(result)
        return result
    }
    func pageModel(_ kind: String) -> ContentPageModel {
        if let model = pages[kind] { return model }
        let model = ContentPageModel(); pages[kind] = model; return model
    }

    var continuingDetectionSignature: String {
        let configuration = MetadataPreferences.shared.configuration()
        return [library.owner, String(storageReady), EBookShelf.hash(configuration.tmdbKey), configuration.language,
                addons.filter(\.enabled).map(\.id).joined(separator: "|"),
                library.continuing.map { $0.id + $0.modified }.joined(separator: "|")].joined(separator: "|")
    }

    func detectContinuingAnime() async {
        guard storageReady else { return }
        let owner = library.owner
        let records = library.continuing
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<min(3, records.count) {
                group.addTask { @MainActor @Sendable in
                    for index in stride(from: worker, to: records.count, by: 3) {
                        guard !Task.isCancelled, owner == self.library.owner else { return }
                        guard let media = records[index].media else { continue }
                        self.animeDetection.observe(media)
                        if records[index].raw["isAnime"] == .bool(true) || self.animeDetection.identifiers.contains(media.id) { continue }
                        guard media.id.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil else { continue }
                        guard let metadata = try? await self.continuationMetadata(media), !Task.isCancelled, owner == self.library.owner else { continue }
                        await self.animeDetection.detect(metadata)
                    }
                }
            }
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        loading = true
        Diagnostics.shared.record(.startup)
        do {
            try profileContext.prepare()
            let action = try profileLaunchPreferences().launchAction(profiles: profileContext.profiles.profiles,
                selectedID: profileContext.profiles.state.selectedID, selectedUnlocked: profileContext.profiles.active != nil,
                lastSelected: ProfileSelectionClock(scope: profileContext.profiles.scope).lastSelected, now: Date().timeIntervalSince1970)
            switch action {
            case .useDefault(let id):
                guard try await profileContext.select(id) else { throw HarborError(code: "profile-selection-required") }
            case .choose:
                prepareProfileAppearances()
                if profileContext.ready { showProfiles = true }
                else if !profileContext.requiresSelection { throw HarborError(code: "profile-selection-required") }
                loading = false; return
            case .resume: break
            }
            guard profileContext.ready else { throw HarborError(code: "profile-selection-required") }
            let configuration = profileContext.configuration
            if let account = configuration?.account {
                savedAccount = account
                addons = account.collection.addons
                AppGuidePreferences.shared.prepare(hasSavedConfiguration: true)
            }
            else if let saved = configuration?.guestAddons {
                addons = saved
                AppGuidePreferences.shared.prepare(hasSavedConfiguration: true)
            }
            else {
                AppGuidePreferences.shared.prepare(hasSavedConfiguration: false)
                let scope = accountOperationScope
                let fallback = try await service.install(HarborService.cinemetaManifest)
                try Task.checkCancellation()
                guard savedAccount == nil, scope == accountOperationScope else { throw CancellationError() }
                try profileContext.save(HouseholdSourceAccount(account: nil, guestAddons: [fallback]))
                addons = [fallback]
            }
            try await setProgressOwner(progressOwner)
            await bindLibrary(savedAccount?.session)
            storageReady = true
            Diagnostics.shared.record(.coreReady)
            if savedAccount != nil {
                do { try await syncAccount() }
                catch { accountError = safeMessage(error); await loadHome() }
            } else { await loadHome() }
        } catch is CancellationError { started = false }
        catch { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }
        loading = false
    }

    func retryStartup() async {
        ProfileSettingsStore.shared.reloadIfUnavailable()
        storageReady = false; profileContext.reload(); started = false; error = nil; await start()
    }

    func reloadProgress() async {
        do { try await resume.load(); progressError = nil }
        catch { progressError = safeMessage(error); Diagnostics.shared.recordFailure(error) }
    }

    private func setProgressOwner(_ owner: String) async throws {
        guard let binding = profileContext.binding else { throw HarborError(code: "profile-settings") }
        if let active = profileContext.profiles.active {
            ProfilePreferences.forOwner(binding.personalOwner).bindHousehold(profileContext.profiles, id: active.id)
        }
        let migrateLegacy: Bool
        switch profileContext.profiles.scope {
        case .local: migrateLegacy = profileContext.profiles.profiles.contains { $0.legacyOwner == binding.identityOwner }
        case .harbor: migrateLegacy = false
        }
        if ProfileSettingsStore.shared.owner != binding.settingsOwner {
            try ProfileSettingsStore.shared.activate(owner: binding.settingsOwner, sharedOwner: binding.sharedSettingsOwner, migrateLegacy: migrateLegacy,
                legacyTMDB: { try KeychainStore().read("metadata.tmdb.v1", as: String.self) })
            InterfacePreferences.shared.reloadPreferences(); ThemePreferences.shared.reloadPreferences()
            PlaybackPreferences.shared.reloadPreferences(); StreamPreferences.shared.reloadPreferences()
            MetadataPreferences.shared.reloadPreferences(); MusicPlayback.shared.reloadPreferences()
        }
        try MetadataPreferences.shared.bind(ProfileSettingsStore.shared)
        harborIdentity.cloud.bindLayoutOwner(settingsOwner)
        InterfacePreferences.shared.navigation.bind(.local(owner: settingsOwner))
        StreamingPreferences.forOwner(settingsOwner).bind(.local(owner: settingsOwner))
        resume = ResumeStore(owner: owner)
        await reloadProgress()
    }

    private func bindLibrary(_ session: AccountSession?) async {
        if !library.matchesSession(session, personalOwner: personalOwner, guestOwner: progressOwner) {
            await library.setSession(session, personalOwner: personalOwner, guestOwner: progressOwner, synchronize: false)
        }
        Task { await library.sync() }
    }

    @discardableResult func selectProfile(_ id: String, password: String? = nil, parentPassword: String? = nil, recordSelection: Bool = true) async throws -> Bool {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        let wasReady = storageReady
        accountBusy = true; switchingProfile = true; showAccount = false; error = nil
        addonRefresh?.task.cancel(); addonRefresh = nil
        defer { accountBusy = false; switchingProfile = false }
        do {
            let accepted = try await profileContext.select(id, password: password, parentPassword: parentPassword)
            guard accepted else { storageReady = wasReady && profileContext.ready; return false }
            storageReady = false
            MusicPlayback.shared.stopForAccount(personalOwner)
            let configuration = profileContext.configuration
            savedAccount = configuration?.account
            if let account = savedAccount { addons = account.collection.addons }
            else if let saved = configuration?.guestAddons { addons = saved }
            else {
                let scope = accountOperationScope
                let fallback = try await service.install(HarborService.cinemetaManifest)
                try Task.checkCancellation()
                guard scope == accountOperationScope else { throw HarborError(code: "account-cancelled") }
                try profileContext.save(HouseholdSourceAccount(account: nil, guestAddons: [fallback])); addons = [fallback]
            }
            homeGeneration += 1; rows = []; heroes = []; warnings = []; pages = [:]; home.reset()
            error = nil; accountError = nil; lastAddonRefresh = .distantPast
            try await setProgressOwner(progressOwner); await bindLibrary(savedAccount?.session)
            storageReady = true
            if recordSelection { ProfileSelectionClock(scope: profileContext.profiles.scope).recordSelection() }
            automaticProfilePromptPending = false
            Task { await loadHome(); await refreshAddons() }
            return true
        } catch {
            // A failed account binding stays hidden; never expose the previous
            // profile's in-memory library under the newly selected identity.
            self.error = safeMessage(error); storageReady = false; throw error
        }
    }

    func loadHome() async {
        ArtworkRefresh.shared.retryFailedImages()
        homeGeneration += 1
        let generation = homeGeneration
        let selectedAddons = addons
        var enabledIDs = Set(selectedAddons.filter(\.enabled).map(\.id))
        if !selectedAddons.contains(where: { $0.manifest["id"].string == "com.linvo.cinemeta" }) { enabledIDs.insert(HarborService.cinemetaManifest) }
        rows = rows.filter { enabledIDs.contains($0.plan.addon.id) && !$0.plan.isPlaybackHistoryCatalog }
        if rows.isEmpty { heroes = [] }
        loading = true
        error = nil
        defer { if generation == homeGeneration { loading = false } }
        do {
            let providers = try await service.catalogProviders(selectedAddons)
            let result = try await service.catalogs(providers, previous: rows, onRow: { [weak self] row in
                guard let self, generation == self.homeGeneration else { return }
                if let index = self.rows.firstIndex(where: { $0.id == row.id }) { self.rows[index] = row }
                else { self.rows.append(row) }
                self.rows.sort { $0.plan.addonPriority == $1.plan.addonPriority ? $0.id < $1.id : $0.plan.addonPriority < $1.plan.addonPriority }
            })
            guard generation == homeGeneration else { return }
            warnings = result.1
            rows = result.0
            Diagnostics.shared.record(.catalogsLoaded, count: rows.count)
            if !warnings.isEmpty && !rows.contains(where: { !$0.metas.isEmpty }) {
                error = "No se pudieron actualizar los catálogos. Comprueba la conexión y vuelve a intentarlo."
            }
            await enrichHeroes(generation: generation)
        } catch is CancellationError { return }
        catch {
            guard generation == homeGeneration else { return }
            self.error = safeMessage(error); Diagnostics.shared.recordFailure(error)
        }
    }

    private func enrichHeroes(generation: Int) async {
        var seen = Set<String>()
        let candidates = rows.flatMap(\.metas).filter { ($0.type == "movie" || $0.type == "series") && seen.insert($0.identity).inserted }
        heroes = Array(candidates.prefix(5))
        let selected = heroes
        await withTaskGroup(of: (Int, Media).self) { group in
            for (index, media) in selected.enumerated() {
                let service = service; let addons = addons
                group.addTask { (index, (try? await service.metadata(media, addons: addons)) ?? media) }
            }
            for await (index, media) in group {
                guard generation == homeGeneration, index < heroes.count else { continue }
                heroes[index] = media
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        guard !accountBusy, profileContext.ready else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        let scope = accountOperationScope
        try await accept(try await accounts.login(email: email, password: password), scope: scope)
    }

    func signIn(authKey: String) async throws {
        guard !accountBusy, profileContext.ready else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        let scope = accountOperationScope
        try await accept(try await accounts.session(authKey: authKey), scope: scope)
    }

    private func accept(_ session: AccountSession, scope: String) async throws {
        let collection = try await accounts.addons(session)
        try Task.checkCancellation()
        guard scope == accountOperationScope else { throw HarborError(code: "account-cancelled") }
        let next = SavedAccount(session: session, collection: collection)
        // Commit the token and downloaded collection together, only after both
        // requests succeed. A rejected login/sync preserves the previous account.
        let previousProgressOwner = progressOwner, previousIdentityOwner = harborIdentityOwner
        try profileContext.save(HouseholdSourceAccount(account: next, guestAddons: profileContext.configuration?.guestAddons), explicitAuthenticationChange: true)
        ProfilePreferences.forOwner(previousIdentityOwner).cloud.suspendForProfileChange()
        savedAccount = next
        addons = collection.addons
        await bindLibrary(session)
        storageReady = true
        rows = []; heroes = []; warnings = []; accountError = nil
        homeGeneration += 1; pages = [:]; home.reset()
        if previousProgressOwner != progressOwner { try await setProgressOwner(progressOwner) }
        Diagnostics.shared.record(.accountSignedIn, count: addons.count)
        await loadHome()
    }

    func syncAccount() async throws {
        guard !accountBusy, let old = savedAccount else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        let scope = accountOperationScope
        var collection = try await accounts.addons(old.session)
        let enabled = Dictionary(old.collection.addons.map { ($0.transportUrl, $0.enabled) }, uniquingKeysWith: { first, _ in first })
        for index in collection.addons.indices {
            collection.addons[index].enabled = enabled[collection.addons[index].transportUrl] ?? true
        }
        let next = SavedAccount(session: old.session, collection: collection)
        try Task.checkCancellation()
        guard scope == accountOperationScope else { throw HarborError(code: "account-cancelled") }
        try profileContext.save(HouseholdSourceAccount(account: next, guestAddons: profileContext.configuration?.guestAddons))
        savedAccount = next; addons = collection.addons
        lastAddonRefresh = Date()
        await bindLibrary(next.session)
        warnings = []; accountError = nil
        Diagnostics.shared.record(.accountSynced, count: addons.count)
        await loadHome()
    }

    func refreshAddons(force: Bool = false) async {
        guard storageReady, !accountBusy, let old = savedAccount, force || Date().timeIntervalSince(lastAddonRefresh) > 30 else { return }
        let scope = accountOperationScope
        let task: Task<AccountCollection, Error>
        let requestID: UUID
        if let existing = addonRefresh { task = existing.task; requestID = existing.id }
        else {
            let accounts = accounts
            requestID = UUID()
            task = Task { try await accounts.addons(old.session, timeout: 5) }
            addonRefresh = (requestID, task)
        }
        defer { if addonRefresh?.id == requestID { addonRefresh = nil } }
        do {
            var collection = try await task.value
            guard !Task.isCancelled, !accountBusy, scope == accountOperationScope, savedAccount?.session.authKey == old.session.authKey else { return }
            let enabled = Dictionary(addons.map { ($0.id, $0.enabled) }, uniquingKeysWith: { first, _ in first })
            for index in collection.addons.indices { collection.addons[index].enabled = enabled[collection.addons[index].id] ?? true }
            let changed = addons.count != collection.addons.count || zip(addons, collection.addons).contains { $0.0.id != $0.1.id || $0.0.manifest != $0.1.manifest }
            let next = SavedAccount(session: old.session, collection: collection)
            try profileContext.save(HouseholdSourceAccount(account: next, guestAddons: profileContext.configuration?.guestAddons))
            savedAccount = next; addons = collection.addons; lastAddonRefresh = Date(); accountError = nil
            if changed { pages = [:]; home.reset(); Task { await loadHome() } }
        } catch is CancellationError { return }
        catch {
            guard scope == accountOperationScope else { return }
            accountError = "No se pudieron actualizar los addons de la cuenta. Se conservan los últimos guardados; vuelve a actualizar las fuentes."
        }
    }

    func signOut() async throws {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        // Desktop sign-out removes the local session, without revoking other devices.
        let guest: [Addon]
        let scope = accountOperationScope
        if let saved = profileContext.configuration?.guestAddons { guest = saved }
        else { guest = [try await service.install(HarborService.cinemetaManifest)] }
        try Task.checkCancellation()
        guard scope == accountOperationScope else { throw HarborError(code: "account-cancelled") }
        let previousIdentityOwner = harborIdentityOwner
        try profileContext.save(HouseholdSourceAccount(account: nil, guestAddons: guest), explicitAuthenticationChange: true)
        ProfilePreferences.forOwner(previousIdentityOwner).cloud.suspendForProfileChange()
        savedAccount = nil; addons = guest; rows = []; heroes = []; warnings = []; accountError = nil
        homeGeneration += 1; pages = [:]; home.reset()
        await bindLibrary(nil)
        try await setProgressOwner(progressOwner)
        Diagnostics.shared.record(.accountSignedOut)
        await loadHome()
    }

    func install(_ url: String, expectedManifestID: String? = nil) async throws {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        let owner = accountOperationScope
        accountBusy = true
        defer { accountBusy = false }
        let addon = try await service.install(url)
        try Task.checkCancellation()
        guard owner == accountOperationScope else { throw HarborError(code: "account-cancelled") }
        if let expectedManifestID, addon.manifest["id"].string != expectedManifestID { throw HarborError(code: "addon-reconfigure-mismatch") }
        let next = addons.filter { $0.transportUrl != addon.transportUrl } + [addon]
        try await saveCollection(next)
        Diagnostics.shared.record(.addonInstalled, count: addons.count)
        await loadHome()
    }

    func setEnabled(_ addon: Addon, _ enabled: Bool) throws {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        var next = addons
        guard let index = next.firstIndex(where: { $0.id == addon.id }) else { return }
        next[index].enabled = enabled
        try persist(next)
    }

    func reconfigure(_ id: String, url: String) async throws -> Addon {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        let owner = accountOperationScope
        accountBusy = true
        defer { accountBusy = false }
        let replacement = try await service.install(url)
        try Task.checkCancellation()
        guard owner == accountOperationScope else { throw HarborError(code: "account-cancelled") }
        let next = try AddonReplacement.apply(replacement, replacing: id, in: addons)
        try await saveCollection(next, replacing: [replacement.id: id])
        Diagnostics.shared.record(.addonInstalled, count: addons.count)
        Task { await loadHome() }
        return next.first { $0.id == replacement.id } ?? replacement
    }

    func remove(_ offsets: IndexSet) async throws {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        try await saveCollection(addons.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
        await loadHome()
    }

    func move(_ offsets: IndexSet, to destination: Int) async throws {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        let moving = addons.enumerated().filter { offsets.contains($0.offset) }.map(\.element)
        var remaining = addons.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertion, remaining.count)))
        try await saveCollection(remaining)
        await loadHome()
    }

    private func saveCollection(_ next: [Addon], replacing replacements: [String: String] = [:]) async throws {
        if let account = savedAccount {
            let scope = accountOperationScope
            let fresh = try await accounts.addons(account.session)
            try Task.checkCancellation()
            guard scope == accountOperationScope else { throw HarborError(code: "account-cancelled") }
            let merged = account.collection.merging(next, into: fresh.addons)
            let collection = AccountCollection(addons: merged, records: fresh.records(for: merged, replacing: replacements))
            try await accounts.save(collection, session: account.session)
            try Task.checkCancellation()
            guard scope == accountOperationScope else { throw HarborError(code: "account-cancelled") }
            let saved = SavedAccount(session: account.session, collection: collection)
            do { try profileContext.save(HouseholdSourceAccount(account: saved, guestAddons: profileContext.configuration?.guestAddons)) }
            catch { throw HarborError(code: "account-local-save-failed") }
            savedAccount = saved; addons = merged; lastAddonRefresh = Date()
        } else { try persist(next) }
    }

    private func persist(_ next: [Addon]) throws {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        if var account = savedAccount {
            account.collection.addons = next
            try profileContext.save(HouseholdSourceAccount(account: account, guestAddons: profileContext.configuration?.guestAddons))
            savedAccount = account
        } else { try profileContext.save(HouseholdSourceAccount(account: nil, guestAddons: next)) }
        addons = next
    }
}

func safeMessage(_ error: Error) -> String {
    if let error = error as? HarborError { return error.localizedDescription }
    return "Harbor no pudo completar la operación."
}
