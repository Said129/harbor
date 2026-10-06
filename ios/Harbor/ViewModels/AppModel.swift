import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    let service = HarborService()
    private(set) var resume = ResumeStore()
    let library = LibraryModel()
    private let keychain = KeychainStore()
    private let accounts = AccountService()
    private var savedAccount: SavedAccount?
    private var homeGeneration = 0
    private var started = false
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
    var showAccount = false
    var user: AccountUser? { savedAccount?.session.user }
    func pageModel(_ kind: String) -> ContentPageModel {
        if let model = pages[kind] { return model }
        let model = ContentPageModel(); pages[kind] = model; return model
    }

    func start() async {
        guard !started else { return }
        started = true
        loading = true
        Diagnostics.shared.record(.startup)
        MetadataPreferences.shared.load()
        do {
            // A Keychain error is not an empty store and must never overwrite it.
            if let account = try keychain.read("account.v1", as: SavedAccount.self) {
                guard account.version == 1 else { throw HarborError(code: "invalid-account-store") }
                savedAccount = account
                addons = account.collection.addons
            }
            else if let saved = try keychain.read("addons.v1", as: [Addon].self) { addons = saved }
            else {
                let fallback = try await service.install(HarborService.cinemetaManifest)
                guard savedAccount == nil else { return }
                try keychain.write([fallback], key: "addons.v1")
                addons = [fallback]
            }
            await setProgressOwner(savedAccount?.session.user.id ?? "guest")
            storageReady = true
            if savedAccount == nil { Task { await library.setSession(nil) } }
            Diagnostics.shared.record(.coreReady)
            if savedAccount != nil {
                do { try await syncAccount() }
                catch { accountError = safeMessage(error); Task { await library.setSession(savedAccount?.session) }; await loadHome() }
            } else { await loadHome() }
        } catch is CancellationError { started = false }
        catch { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }
        loading = false
    }

    func retryStartup() async { started = false; error = nil; await start() }

    func reloadProgress() async {
        do { try await resume.load(); progressError = nil }
        catch { progressError = safeMessage(error); Diagnostics.shared.recordFailure(error) }
    }

    private func setProgressOwner(_ owner: String) async {
        resume = ResumeStore(owner: owner)
        await reloadProgress()
    }

    func loadHome() async {
        homeGeneration += 1
        let generation = homeGeneration
        let selectedAddons = addons
        var enabledIDs = Set(selectedAddons.filter(\.enabled).map(\.id))
        if !selectedAddons.contains(where: { $0.manifest["id"].string == "com.linvo.cinemeta" }) { enabledIDs.insert(HarborService.cinemetaManifest) }
        rows = rows.filter { enabledIDs.contains($0.plan.addon.id) }
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
            if !warnings.isEmpty {
                error = rows.contains(where: { !$0.metas.isEmpty }) ? "Algunos catálogos no han respondido. Los títulos disponibles siguen accesibles." : "No se pudieron actualizar los catálogos. Comprueba la conexión y vuelve a intentarlo."
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
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        try await accept(try await accounts.login(email: email, password: password))
    }

    func signIn(authKey: String) async throws {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        try await accept(try await accounts.session(authKey: authKey))
    }

    private func accept(_ session: AccountSession) async throws {
        let collection = try await accounts.addons(session)
        let next = SavedAccount(session: session, collection: collection)
        // Commit the token and downloaded collection together, only after both
        // requests succeed. A rejected login/sync preserves the previous account.
        try keychain.write(next, key: "account.v1")
        let previousOwner = savedAccount?.session.user.id ?? "guest"
        savedAccount = next
        addons = collection.addons
        Task { await library.setSession(session) }
        storageReady = true
        rows = []; heroes = []; warnings = []; accountError = nil
        homeGeneration += 1; pages = [:]
        if previousOwner != session.user.id { await setProgressOwner(session.user.id) }
        Diagnostics.shared.record(.accountSignedIn, count: addons.count)
        await loadHome()
    }

    func syncAccount() async throws {
        guard !accountBusy, let old = savedAccount else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        var collection = try await accounts.addons(old.session)
        let enabled = Dictionary(old.collection.addons.map { ($0.transportUrl, $0.enabled) }, uniquingKeysWith: { first, _ in first })
        for index in collection.addons.indices {
            collection.addons[index].enabled = enabled[collection.addons[index].transportUrl] ?? true
        }
        let next = SavedAccount(session: old.session, collection: collection)
        try keychain.write(next, key: "account.v1")
        savedAccount = next; addons = collection.addons
        Task { await library.setSession(next.session) }
        warnings = []; accountError = nil
        Diagnostics.shared.record(.accountSynced, count: addons.count)
        await loadHome()
    }

    func signOut() async throws {
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        // Desktop sign-out removes the local session, without revoking other devices.
        let guest: [Addon]
        if let saved = try keychain.read("addons.v1", as: [Addon].self) { guest = saved }
        else { guest = [try await service.install(HarborService.cinemetaManifest)] }
        try keychain.remove("account.v1")
        savedAccount = nil; addons = guest; rows = []; heroes = []; warnings = []; accountError = nil
        homeGeneration += 1; pages = [:]
        Task { await library.setSession(nil) }
        await setProgressOwner("guest")
        Diagnostics.shared.record(.accountSignedOut)
        await loadHome()
    }

    func install(_ url: String) async throws {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        guard !accountBusy else { throw HarborError(code: "account-busy") }
        accountBusy = true
        defer { accountBusy = false }
        let addon = try await service.install(url)
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

    private func saveCollection(_ next: [Addon]) async throws {
        if let account = savedAccount {
            let collection = AccountCollection(addons: next, records: account.collection.records(for: next))
            try await accounts.save(collection, session: account.session)
            let saved = SavedAccount(session: account.session, collection: collection)
            do { try keychain.write(saved, key: "account.v1") }
            catch { throw HarborError(code: "account-local-save-failed") }
            savedAccount = saved; addons = next
        } else { try persist(next) }
    }

    private func persist(_ next: [Addon]) throws {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        if var account = savedAccount {
            account.collection.addons = next
            try keychain.write(account, key: "account.v1")
            savedAccount = account
        } else { try keychain.write(next, key: "addons.v1") }
        addons = next
    }
}

func safeMessage(_ error: Error) -> String {
    if let error = error as? HarborError { return error.localizedDescription }
    return "Harbor no pudo completar la operación."
}
