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
    private(set) var sharedResume = ResumeStore()
    private(set) var personalResume = ResumeStore()
    private var resumeOwners: (personal: String, shared: String)?
    private let progressStores = PlaybackProgressStoreRegistry()
    let library = LibraryModel()
    let home = HomeContentModel()
    let animeDetection = AnimeLibraryDetection()
    let plugins = HarborPluginSession()
    let readingPlugins = HarborReadingPluginSession()
    let profileContext = AppProfileContext.shared
    private var homeGeneration = 0
    private var started = false
    @ObservationIgnored private var addonRefresh: (id: UUID, task: Task<[Addon], Error>)?
    private var lastAddonRefresh = Date.distantPast
    @ObservationIgnored private var pages: [String: ContentPageModel] = [:]
    private var preparedProfileActivation: UUID?
    @ObservationIgnored private var boundHarborIdentity: HarborProfileSync?
    private(set) var storageReady: Bool {
        get { preparedProfileActivation == profileContext.activationID }
        set { preparedProfileActivation = newValue ? profileContext.activationID : nil }
    }
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
        profileContext.bindProfileAppearances()
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
        if profileContext.ready { try bindHarborIdentity() }
        if storageReady && profileContext.ready && previous == profileContext.binding { return }
        storageReady = false
        if let active = profileContext.profiles.active {
            guard try await selectProfile(active.id, recordSelection: recordSelection) else { throw HarborError(code: "profile-locked") }
        } else { showProfiles = true }
    }
    private(set) var pendingDocument: PendingProfileDocument?
    var personalOwner: String { profileContext.binding?.personalOwner ?? "guest" }
    var settingsOwner: String { profileContext.binding?.settingsOwner ?? "guest" }
    func pageCustomization(_ page: String) -> PageCustomization {
        guard ["home", "anime"].contains(page) else { return PageCustomization(owner: settingsOwner, page: page) }
        let legacy = page == "anime" && profileContext.profiles.active?.desktop.isPrimary == true ? (profileContext.configuration?.dataOwner ?? "guest") : nil
        return PageCustomization.forOwner(settingsOwner, page: page, legacyOwner: legacy, inheritedOwner: profileContext.binding?.sharedSettingsOwner)
    }
    var harborIdentityOwner: String {
        guard let active = profileContext.profiles.active else { return HarborProfileIdentity.unboundOwner }
        return HarborProfileIdentity.owner(active, scope: profileContext.profiles.scope)
    }
    var harborIdentity: HarborProfileSync { HarborProfileSync.forOwner(harborIdentityOwner, profile: ProfilePreferences.forOwner(personalOwner)) }
    var progressOwner: String { profileContext.binding?.progressOwner ?? "guest" }
    var sharesContinueSource: Bool {
        guard let profile = profileContext.profiles.active else { return false }
        return HouseholdProfileRouting(profile: profile, profiles: profileContext.profiles.profiles,
            scope: profileContext.profiles.scope, cwPerProfile: true).privateContinuing
    }
    func applyContinuePreferences() {
        guard profileContext.ready, ProfileSettingsStore.shared.owner == settingsOwner,
              resumeOwners?.personal == personalOwner, resumeOwners?.shared == progressOwner else { return }
        do {
            let preferences = try ProfileSettingsStore.shared.continuePreferences(owner: settingsOwner, sharedOwner: profileContext.householdSettingsOwner)
            let privateMode = preferences.perProfile && sharesContinueSource
            resume = privateMode ? personalResume : sharedResume
            library.setContinueSources(preferences.sources)
            if library.personalOwner == personalOwner { library.setContinuePrivacy(privateMode, migratedScope: profileContext.profiles.scope.key) }
        } catch {
            library.setContinuePrivacy(true); resume = personalResume
            progressError = safeMessage(error); Diagnostics.shared.recordFailure(error)
        }
    }
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
            try await profileContext.retireStremioAccounts()
            try LegacySourceRetirement.run()
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
            if let saved = configuration?.guestAddons {
                addons = saved
                AppGuidePreferences.shared.prepare(hasSavedConfiguration: true)
            } else {
                addons = []
                AppGuidePreferences.shared.prepare(hasSavedConfiguration: false)
            }
            try await setProgressOwner(progressOwner)
            await bindLibrary(nil)
            storageReady = true
            Diagnostics.shared.record(.coreReady)
            if configuration?.guestAddons == nil {
                Task { await initializeDefaultSourceAndHome() }
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
        let shared = sharedResume, personal = personalResume, scope = accountOperationScope
        var failure: Error?
        for store in [shared, personal] {
            do { try await store.load() } catch { failure = error; Diagnostics.shared.recordFailure(error) }
        }
        guard scope == accountOperationScope else { return }
        progressError = failure.map(safeMessage)
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
            TitleArtworkPreferences.shared.reloadPreferences()
        }
        try MetadataPreferences.shared.bind(ProfileSettingsStore.shared)
        _ = pageCustomization("home"); _ = pageCustomization("anime")
        try bindHarborIdentity()
        InterfacePreferences.shared.navigation.bind(.local(owner: settingsOwner))
        StreamingPreferences.forOwner(settingsOwner).bind(.local(owner: settingsOwner))
        pageCustomization("home").bind(.local(owner: settingsOwner)); pageCustomization("anime").bind(.local(owner: settingsOwner))
        harborIdentity.bindCachedLayouts()
        sharedResume = progressStores.store(owner: owner)
        personalResume = progressStores.store(owner: "continue-private-" + binding.personalOwner)
        resumeOwners = (binding.personalOwner, owner)
        applyContinuePreferences()
        await reloadProgress()
    }
    private func bindHarborIdentity() throws {
        let cloud = harborIdentity
        if boundHarborIdentity !== cloud { boundHarborIdentity?.unbindHouseholdContext(); boundHarborIdentity = cloud }
        if try HarborProfileIdentity.migrateLegacy(context: profileContext) { cloud.reload() }
        ProfilePreferences.forOwner(personalOwner).bindIdentitySync(cloud)
        cloud.bindHouseholdContext(profileContext) { [weak self] in
            guard let self else { return }
            self.prepareProfileAppearances()
            Task { [weak self] in
                guard let self else { return }
                guard !self.accountBusy else { self.harborIdentity.requestHouseholdSynchronization(); return }
                do {
                    try await self.refreshSelectedProfile()
                    if self.profileContext.ready { self.harborIdentity.requestHouseholdSynchronization() }
                } catch { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }
            }
        }
        cloud.bindLayoutOwner(settingsOwner, profileID: profileContext.profiles.active?.syncID,
            primary: profileContext.profiles.active?.desktop.isPrimary == true)
    }

    private func bindLibrary(_ session: AccountSession?) async {
        if !library.matchesSession(session, personalOwner: personalOwner, guestOwner: progressOwner) {
            await library.setSession(session, personalOwner: personalOwner, guestOwner: progressOwner, synchronize: false)
        }
        if let binding = profileContext.binding {
            do { try ContinueDismissalStore.shared.migrate(scope: profileContext.profiles.scope.key, existingOwners: profileContext.continuingLegacyOwners()) }
            catch { Diagnostics.shared.recordFailure(error) }
            applyContinuePreferences()
            let scope = accountOperationScope, owner = personalOwner
            await library.bindLocalContinuing(sharedOwner: binding.progressOwner, scope: scope, active: { [weak self] in
                self?.profileContext.ready == true && self?.personalOwner == owner && self?.accountOperationScope == scope
            })
            if resumeOwners?.personal == owner, resumeOwners?.shared == binding.progressOwner {
                library.bindPlaybackProgress(.init(personalOwner: owner, sharedOwner: binding.progressOwner, personal: personalResume, shared: sharedResume))
            }
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
            try await profileContext.retireStremioAccounts()
            let accepted = try await profileContext.select(id, password: password, parentPassword: parentPassword)
            guard accepted else { storageReady = wasReady && profileContext.ready; return false }
            boundHarborIdentity?.unbindHouseholdContext(); boundHarborIdentity = nil
            storageReady = false
            MusicPlayback.shared.stopForAccount(personalOwner)
            let configuration = profileContext.configuration
            addons = configuration?.guestAddons ?? []
            homeGeneration += 1; rows = []; heroes = []; warnings = []; pages = [:]; home.reset()
            error = nil; accountError = nil; lastAddonRefresh = .distantPast
            try await setProgressOwner(progressOwner); await bindLibrary(nil)
            storageReady = true
            if recordSelection { ProfileSelectionClock(scope: profileContext.profiles.scope).recordSelection() }
            automaticProfilePromptPending = false
            Task {
                if configuration?.guestAddons == nil { await initializeDefaultSourceAndHome() }
                else { await loadHome(); await refreshAddons() }
            }
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

    /// First-run catalog discovery must not gate local profiles, the library or
    /// document imports. A late default never replaces an intentional empty list.
    private func initializeDefaultSourceAndHome() async {
        let scope = accountOperationScope
        guard storageReady, profileContext.configuration?.guestAddons == nil else { return }
        do {
            let fallback = try await service.install(HarborService.cinemetaManifest)
            guard !Task.isCancelled, scope == accountOperationScope, storageReady,
                  profileContext.configuration?.guestAddons == nil, addons.isEmpty else { return }
            try persist([fallback])
        } catch is CancellationError { return }
        catch { Diagnostics.shared.recordFailure(error) }
        guard scope == accountOperationScope, storageReady else { return }
        await loadHome()
    }

    /// Refresh the configured manifests directly. This path never contacts an
    /// account API and preserves each instance's URL, enabled state and ordering.
    func refreshAddons(force: Bool = false) async {
        guard storageReady, !accountBusy, force || Date().timeIntervalSince(lastAddonRefresh) > 30 else { return }
        // Opening a detail/player uses the last known manifests immediately.
        // Only the explicit Refresh action waits for provider availability.
        if !force { Task { await refreshAddons(force: true) }; return }
        let scope = accountOperationScope, baseline = addons
        let task: Task<[Addon], Error>, requestID: UUID
        if let existing = addonRefresh { task = existing.task; requestID = existing.id }
        else {
            requestID = UUID()
            let service = service
            task = Task {
                await withTaskGroup(of: (Int, Addon).self) { group in
                    var iterator = baseline.enumerated().makeIterator(), values = baseline
                    func enqueue(_ index: Int, _ addon: Addon) {
                        group.addTask {
                            guard var next = try? await service.install(addon.transportUrl, timeout: 5),
                                  next.manifest["id"] == addon.manifest["id"] else { return (index, addon) }
                            next.enabled = addon.enabled; return (index, next)
                        }
                    }
                    for _ in 0..<3 { if let (index, addon) = iterator.next() { enqueue(index, addon) } }
                    for await (index, addon) in group {
                        values[index] = addon
                        if let (next, item) = iterator.next() { enqueue(next, item) }
                    }
                    return values
                }
            }
            addonRefresh = (requestID, task)
        }
        defer { if addonRefresh?.id == requestID { addonRefresh = nil } }
        do {
            let refreshed = try await task.value
            guard !Task.isCancelled, !accountBusy, scope == accountOperationScope,
                  try JSONValue.encoded(addons) == JSONValue.encoded(baseline) else { return }
            let changed = try JSONValue.encoded(refreshed) != JSONValue.encoded(baseline)
            if changed { try persist(refreshed); pages = [:]; home.reset(); Task { await loadHome() } }
            lastAddonRefresh = Date(); accountError = nil
        } catch is CancellationError { return }
        catch { Diagnostics.shared.recordFailure(error) }
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
        try persist(next, replacing: replacements)
    }

    private func persist(_ next: [Addon], replacing replacements: [String: String] = [:]) throws {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        var configuration = profileContext.configuration ?? HouseholdSourceAccount(account: nil, guestAddons: nil)
        guard configuration.account == nil else { throw HarborError(code: "profile-account-migration") }
        if var archive = configuration.localSource {
            let previous = AccountCollection(addons: addons, records: archive.collection.records)
            archive.collection = AccountCollection(addons: next, records: previous.records(for: next, replacing: replacements))
            configuration.localSource = archive
        }
        configuration.guestAddons = next
        try profileContext.save(configuration)
        addons = next
    }
}

func safeMessage(_ error: Error) -> String {
    if let error = error as? HarborError { return error.localizedDescription }
    return "Harbor no pudo completar la operación."
}
