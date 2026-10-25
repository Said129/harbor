import Foundation
import Observation

struct HarborRoster: Sendable {
    static let key = "account:profiles"
    let rev: Int64
    let value: JSONValue
    var profiles: [JSONValue] { value["profiles"].array }
    static func document(_ value: JSONValue) throws -> HarborRoster {
        guard value["key"].string == key, let number = value["rev"].numericValue,
              number.isFinite, number >= 0, number.rounded() == number, number < Double(Int64.max),
              case .array(let profiles) = value["value"]["profiles"], !profiles.isEmpty,
              profiles.allSatisfy({ $0["syncId"].string?.isEmpty == false && $0["name"].string != nil }),
              Set(profiles.compactMap { $0["syncId"].string }).count == profiles.count else { throw HarborError(code: "profile-sync-response") }
        return HarborRoster(rev: Int64(number), value: value["value"])
    }
    static func state(_ value: JSONValue) throws -> HarborRoster {
        guard value["rev"].numericValue != nil, case .array(let docs) = value["docs"],
              let doc = docs.first(where: { $0["key"].string == key }) else { throw HarborError(code: "profile-sync-roster") }
        return try document(doc)
    }
    func primary() -> JSONValue? { profiles.first { $0["deletedAt"] == .null && $0["isPrimary"] == .bool(true) && $0["kid"] == .null } }
    func profile(_ id: String) -> JSONValue? { profiles.first { $0["syncId"].string == id && $0["deletedAt"] == .null && $0["kid"] == .null } }
    func applying(_ fields: [String: JSONValue], to id: String) throws -> HarborRoster {
        guard profile(id) != nil, fields.keys.allSatisfy({ ["name", "avatar", "color"].contains($0) }) else { throw HarborError(code: "profile-sync-target") }
        var rows = profiles
        guard let index = rows.firstIndex(where: { $0["syncId"].string == id }) else { throw HarborError(code: "profile-sync-target") }
        var profile = rows[index].objectValue
        for (key, value) in fields { profile[key] = value }
        profile["updatedAt"] = .number(Date().timeIntervalSince1970 * 1_000)
        rows[index] = .object(profile)
        var roster = value.objectValue; roster["profiles"] = .array(rows)
        let result = JSONValue.object(roster)
        guard try JSONEncoder().encode(result).count <= 96 * 1_024 else { throw HarborError(code: "profile-sync-size") }
        return HarborRoster(rev: rev, value: result)
    }
}

@MainActor @Observable
final class HarborProfileSync {
    private struct Session: Codable {
        let id: String; let username: String; let handle: String?; var token: String; var refresh: String
        var server: HarborIdentityServer?
        var realm: HarborIdentityServer { server ?? .original }
        var account: String { realm.account(id) }
    }
    private struct Pending: Codable { let account: String; let syncId: String; var version: UUID; var fields: [String: JSONValue] }
    private struct Stored: Codable { var session: Session?; var pending: Pending?; var parked: [String: Pending]? }
    static func identityRecordAccount(_ raw: JSONValue) throws -> String? {
        guard case .object = raw, try JSONEncoder().encode(raw).count <= 512 * 1_024 else { throw HarborError(code: "profile-identity-migration") }
        let value = try JSONDecoder().decode(Stored.self, from: JSONEncoder().encode(raw))
        if let session = value.session {
            guard !session.id.isEmpty, session.id.utf8.count <= 256, !session.username.isEmpty,
                  session.username.utf8.count <= 256, !session.token.isEmpty, session.token.utf8.count <= 32 * 1_024,
                  !session.refresh.isEmpty, session.refresh.utf8.count <= 32 * 1_024 else { throw HarborError(code: "profile-identity-migration") }
        }
        return value.session?.account
    }
    private static var models: [String: HarborProfileSync] = [:]
    static func forOwner(_ owner: String, profile: ProfilePreferences) -> HarborProfileSync {
        if let existing = models[owner] { existing.profile = profile; return existing }
        let value = HarborProfileSync(owner: owner, profile: profile); models[owner] = value; return value
    }
    private let key: String
    private let owner: String
    @ObservationIgnored private let transport: @MainActor (HarborIdentityServer, String, String, JSONValue?, String?) async throws -> JSONValue
    private var boundLayoutOwner: String?
    private var boundLayoutProfile: DesktopLayoutProfileTarget?
    private var layoutOwner: String { boundLayoutOwner ?? owner }
    @ObservationIgnored private var navigationBindings: [String: HarborNavigationSync] = [:]
    @ObservationIgnored private var serviceBindings: [String: HarborStreamingSync] = [:]
    @ObservationIgnored private var pageBindings: [String: HarborPageSync] = [:]
    @ObservationIgnored private var watchedByBindings: [String: HarborWatchedBySync] = [:]
    @ObservationIgnored private weak var householdContext: AppProfileContext?
    @ObservationIgnored private var householdSync: HarborHouseholdSync?
    @ObservationIgnored private var householdLayouts: HarborHouseholdLayoutSync?
    @ObservationIgnored private var householdDidChange: (() -> Void)?
    @ObservationIgnored private var bindingActive = true
    func bindHouseholdContext(_ context: AppProfileContext, didChange: @escaping () -> Void) {
        bindingActive = true; householdContext = context; householdDidChange = didChange
    }
    func unbindHouseholdContext() {
        suspendForProfileChange(); bindingActive = false
        householdContext = nil; householdDidChange = nil
    }
    private var isCurrentBinding: Bool {
        guard bindingActive else { return false }
        guard let context = householdContext else { return true }
        guard context.ready, let active = context.profiles.active, !active.desktop.isKid else { return false }
        return !HarborProfileIdentity.validOwner(owner) || HarborProfileIdentity.owner(active, scope: context.profiles.scope) == owner
    }
    private var cachedHouseholdAccount: String? {
        guard let context = householdContext, context.ready, case .harbor(let account) = context.profiles.scope,
              context.sessions.activeHarborAccount == account else { return nil }
        return account
    }
    func requestHouseholdSynchronization() { if signedIn { scheduleSync() } }
    var watchedBy: HarborWatchedBySync {
        let cacheOwner = householdContext?.binding?.identityOwner ?? owner
        let account = householdContext == nil ? stored.session?.account : cachedHouseholdAccount
        let bucket = HouseholdProfileScope.hash([cacheOwner, account == nil ? "local" : "harbor", account ?? ""])
        let value = watchedByBindings[bucket] ?? HarborWatchedBySync.forOwner(cacheOwner, account: account)
        if isCurrentBinding, signedIn, value.account == accountID {
            value.requestSync = { [weak self, weak value] in
                guard let self, let value, self.isCurrentBinding, self.signedIn, value.account == self.accountID else { return }
                self.scheduleSync()
            }
        }
        watchedByBindings[bucket] = value; return value
    }
    func page(_ page: String) -> HarborPageSync {
        let key = EBookShelf.hash(String(decoding: try! JSONEncoder().encode([layoutOwner, page]), as: UTF8.self))
        if let value = pageBindings[key] { return value }
        let value = HarborPageSync(preferences: PageCustomization.forOwner(layoutOwner, page: page))
        pageBindings[key] = value; return value
    }
    var navigation: HarborNavigationSync {
        if let value = navigationBindings[layoutOwner] { return value }
        let preferences = InterfacePreferences.shared
        let ids = Set(HarborSection.allCases.map(\.rawValue)).subtracting(["search"])
        let value = HarborNavigationSync(owner: layoutOwner, preferences: preferences.navigation, defaultOrder: preferences.defaultNavigationOrder, knownIDs: ids)
        navigationBindings[layoutOwner] = value; return value
    }
    var services: HarborStreamingSync {
        if let value = serviceBindings[layoutOwner] { return value }
        let value = HarborStreamingSync(owner: layoutOwner, preferences: StreamingPreferences.forOwner(layoutOwner))
        serviceBindings[layoutOwner] = value; return value
    }
    @ObservationIgnored private weak var profile: ProfilePreferences?
    private var stored = Stored()
    private var generation = 0
    private var selectedID: String?
    private var scheduled: Task<Void, Never>?
    var busy = false
    private(set) var hydrated = false
    private(set) var ready = false
    var error: String?
    var signedIn: Bool { stored.session != nil }
    var server: HarborIdentityServer? { stored.session?.realm }
    var serverRetired: Bool { server?.retired == true }
    var username: String? { stored.session?.username }
    var accountID: String? { stored.session?.account }
    var handle: String? { stored.session?.handle }
    var hasPendingChanges: Bool { stored.pending != nil || householdSync?.hasPendingChanges == true || householdLayouts?.hasPendingChanges == true || navigation.hasPendingChanges || services.hasPendingChanges || page("home").hasPendingChanges || page("anime").hasPendingChanges || watchedBy.hasPendingChanges }
    init(owner: String, profile: ProfilePreferences,
         serverTransport: @escaping @MainActor (HarborIdentityServer, String, String, JSONValue?, String?) async throws -> JSONValue = { server, path, method, body, token in
             try await HTTPClient().harbor(path, server: server, method: method, body: body, token: token)
         }) {
        self.owner = owner
        self.transport = serverTransport
        key = "harbor-identity-" + EBookShelf.hash(owner); self.profile = profile
        reload()
    }
    convenience init(owner: String, profile: ProfilePreferences,
                     transport: @escaping @MainActor (String, String, JSONValue?, String?) async throws -> JSONValue) {
        self.init(owner: owner, profile: profile, serverTransport: { _, path, method, body, token in
            try await transport(path, method, body, token)
        })
    }
    private func send(_ server: HarborIdentityServer, _ path: String, _ method: String, _ body: JSONValue?, _ token: String?) async throws -> JSONValue {
        guard isCurrentBinding else { throw HarborError(code: "account-changed") }
        guard !server.retired else { throw HarborError(code: "harbor-server-retired") }
        return try await transport(server, path, method, body, token)
    }
    func bindLayoutOwner(_ next: String, profileID: String? = nil, primary: Bool = false) {
        let target = profileID.map { DesktopLayoutProfileTarget(id: $0, primary: primary) }
        guard next != layoutOwner || target != boundLayoutProfile else { return }
        suspendForProfileChange(); boundLayoutOwner = next; boundLayoutProfile = target; selectedID = nil
    }
    func bindCachedLayouts() {
        guard ready, bindingActive, let account = cachedHouseholdAccount, let context = householdContext,
              context.binding?.settingsOwner == layoutOwner,
              context.profiles.active?.syncID == boundLayoutProfile?.id else { return }
        do {
            try HarborHouseholdLayoutSync.bindCached(account: account, context: context,
                active: .init(navigation: navigation, services: services, home: page("home"), anime: page("anime")))
        } catch { self.error = "No se pudieron recuperar algunos ajustes guardados. Los datos anteriores se conservan." }
    }
    private func bindSavedLayouts() {
        if cachedHouseholdAccount != nil { bindCachedLayouts(); return }
        page("home").preferences.bind(.local(owner: layoutOwner)); page("anime").preferences.bind(.local(owner: layoutOwner))
        StreamingPreferences.forOwner(layoutOwner).bind(.local(owner: layoutOwner))
        if InterfacePreferences.shared.navigation.scope?.owner == layoutOwner { InterfacePreferences.shared.navigation.bind(.local(owner: layoutOwner)) }
    }
    /// Keep sessions and durable queues; invalidate late replies from a source
    /// which no longer owns the visible interface and preference bindings.
    func suspendForProfileChange() {
        generation += 1; scheduled?.cancel(); scheduled = nil; busy = false; hydrated = false
        householdSync?.invalidate()
        householdLayouts?.invalidate()
        for binding in navigationBindings.values { binding.unbind() }
        for binding in serviceBindings.values { binding.unbind() }
        for binding in pageBindings.values { binding.unbind() }
    }
    func reload() {
        guard !busy else { return }
        guard owner != HarborProfileIdentity.unboundOwner else { bindingActive = false; ready = false; return }
        do {
            if let raw = try KeychainStore().read(key, as: JSONValue.self) {
                _ = try Self.identityRecordAccount(raw)
                stored = try JSONDecoder().decode(Stored.self, from: JSONEncoder().encode(raw))
            } else { stored = Stored() }
            ready = true; error = nil
        }
        catch { ready = false; self.error = "No se pudo recuperar la cuenta de Harbor. Los datos guardados se conservan." }
    }
    func signIn(username: String, password: String, server: HarborIdentityServer) async {
        guard ready, !busy, isCurrentBinding else { return }
        busy = true; error = nil; generation += 1; let scope = generation
        defer { if scope == generation { busy = false } }
        do {
            let response = try await send(server, "/identity/api/login", "POST", .object(["username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)), "password": .string(password)]), nil)
            try Task.checkCancellation(); guard isCurrentBinding, scope == generation else { return }
            guard let token = response["token"].string, !token.isEmpty, let refresh = response["refresh"].string, !refresh.isEmpty,
                  let id = response["user"]["id"].string, !id.isEmpty, let name = response["user"]["username"].string else { throw HarborError(code: "profile-auth-response") }
            let session = Session(id: id, username: name, handle: response["user"]["handle"].string, token: token, refresh: refresh, server: server)
            let account = session.account
            var parked = stored.parked ?? [:]
            if let pending = stored.pending, pending.account != account { parked[pending.account] = pending }
            let pending = stored.pending?.account == account ? stored.pending : parked.removeValue(forKey: account)
            let next = Stored(session: session, pending: pending, parked: parked)
            let changedAccount = stored.session?.account != account
            try persist(next); stored = next; selectedID = nil; hydrated = false
            if changedAccount {
                householdSync?.invalidate(); householdSync = nil
                householdLayouts?.invalidate(); householdLayouts = nil
                navigation.unbind()
                services.unbind()
                page("home").unbind(); page("anime").unbind()
                bindSavedLayouts()
            }
            try await synchronize(scope: scope)
        } catch is CancellationError { return }
        catch { if scope == generation { self.error = safeMessage(error) } }
    }
    func signOut() async {
        guard ready, !busy, isCurrentBinding else { return }
        generation += 1; let session = stored.session
        householdSync?.invalidate()
        householdLayouts?.invalidate(); householdLayouts = nil
        scheduled?.cancel(); scheduled = nil
        do {
            // Keep unacknowledged changes bound to their original account for a later login.
            let next = Stored(session: nil, pending: stored.pending, parked: stored.parked); try persist(next); stored = next
            hydrated = false; selectedID = nil; error = nil
            navigation.unbind()
            services.unbind()
            page("home").unbind(); page("anime").unbind()
            bindSavedLayouts()
        } catch { self.error = "No se pudo cerrar la sesión. Vuelve a intentarlo."; return }
        if let session { _ = try? await send(session.realm, "/auth/logout", "POST", .object([:]), session.token) }
    }
    func sync() async {
        guard ready, signedIn, !busy, isCurrentBinding else { return }
        busy = true; let scope = generation; error = nil
        defer { if scope == generation { busy = false } }
        do { try await synchronize(scope: scope) }
        catch is CancellationError { return }
        catch { if scope == generation { self.error = safeMessage(error) } }
    }
    func enqueue(before: MobileProfile, after: MobileProfile) {
        if householdContext != nil {
            if signedIn && !busy { scheduleSync() }
            return
        }
        guard hydrated, let session = stored.session, let id = selectedID else { return }
        var fields: [String: JSONValue] = [:]
        if before.name != after.name { fields["name"] = .string(String(after.name.prefix(32))) }
        if before.color != after.color { fields["color"] = .string("#" + after.color) }
        if before.avatar != after.avatar || before.photo != after.photo || before.remoteAvatar != after.remoteAvatar || before.initialsAvatar != after.initialsAvatar {
            // Desktop's roster only transmits portable bundled avatar paths.
            fields["avatar"] = after.photo == nil ? .string("/avatars/\(after.avatar).webp") : .null
        }
        guard !fields.isEmpty else { return }
        var pending = stored.pending?.account == session.account && stored.pending?.syncId == id ? stored.pending : nil
        if pending == nil { pending = Pending(account: session.account, syncId: id, version: UUID(), fields: [:]) }
        for (name, value) in fields { pending?.fields[name] = value }
        pending?.version = UUID()
        do { var next = stored; next.pending = pending; try persist(next); stored = next; error = nil }
        catch { self.error = "No se pudieron guardar los cambios para sincronizar. Vuelve a intentarlo."; return }
        scheduleSync()
    }
    private func scheduleSync() {
        guard isCurrentBinding else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)); try Task.checkCancellation() } catch { return }
            await self?.sync()
        }
    }
    private func persist(_ value: Stored) throws { try KeychainStore().write(value, key: key) }
    private func request(_ path: String, method: String = "GET", body: JSONValue? = nil, scope: Int) async throws -> JSONValue {
        guard isCurrentBinding, scope == generation, let session = stored.session else { throw HarborError(code: "account-changed") }
        do {
            let value = try await send(session.realm, path, method, body, session.token)
            guard isCurrentBinding, scope == generation, stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
            return value
        } catch let failure as HarborError where failure.code == "http-401" {
            guard isCurrentBinding, scope == generation, stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
            let response = try await send(session.realm, "/identity/api/token/refresh", "POST", .object(["refresh": .string(session.refresh)]), nil)
            guard isCurrentBinding, scope == generation, stored.session?.account == session.account, stored.session?.refresh == session.refresh,
                  let token = response["token"].string, !token.isEmpty, let refresh = response["refresh"].string, !refresh.isEmpty else { throw HarborError(code: "profile-auth-response") }
            var next = stored; next.session?.token = token; next.session?.refresh = refresh
            try persist(next); stored = next
            let value = try await send(session.realm, path, method, body, token)
            guard isCurrentBinding, scope == generation else { throw HarborError(code: "account-changed") }
            return value
        }
    }
    private func flushPendingAppearance(_ initial: HarborRoster, account: String, scope: Int) async throws -> HarborRoster {
        var roster = initial
        if let pending = stored.pending, pending.account == account {
            guard roster.profile(pending.syncId) != nil else { throw HarborError(code: "profile-sync-target") }
            var acknowledged = false
            for _ in 0..<3 {
                let changed = try roster.applying(pending.fields, to: pending.syncId)
                let write: JSONValue = .object(["key": .string(HarborRoster.key), "baseRev": .integer(roster.rev), "value": changed.value])
                let response = try await request("/sync/v1/push", method: "POST", body: .object(["writes": .array([write])]), scope: scope)
                guard case .array(let results) = response["results"], results.count == 1, let result = results.first,
                      result["key"] == .null || result["key"].string == HarborRoster.key else { throw HarborError(code: "profile-sync-response") }
                if result["ok"] == .bool(true) {
                    guard let revision = result["rev"].numericValue, revision > Double(roster.rev), revision < Double(Int64.max), revision.rounded() == revision else { throw HarborError(code: "profile-sync-response") }
                    roster = HarborRoster(rev: Int64(revision), value: changed.value)
                    var next = stored
                    if next.pending?.version == pending.version { next.pending = nil }
                    try persist(next); stored = next; acknowledged = true
                    if let alias = pending.fields["name"]?.string, !alias.isEmpty {
                        _ = try? await request("/social/me/profile", method: "PATCH", body: .object(["alias": .string(alias)]), scope: scope)
                    }
                    break
                }
                let current = try HarborRoster.document(result["current"])
                guard current.rev >= roster.rev else { throw HarborError(code: "profile-sync-response") }
                roster = current
            }
            guard acknowledged else { throw HarborError(code: "profile-sync-conflict") }
        }
        return roster
    }
    private func replacingRoster(in state: JSONValue, with roster: HarborRoster) -> JSONValue {
        var fields = state.objectValue
        fields["docs"] = .array(state["docs"].array.filter { $0["key"].string != HarborRoster.key }
            + [.object(["key": .string(HarborRoster.key), "rev": .integer(roster.rev), "value": roster.value])])
        fields["rev"] = .integer(max((try? HarborLayoutDocument.revision(state["rev"])) ?? 0, roster.rev))
        return .object(fields)
    }
    private func synchronizedHouseholdState(_ state: JSONValue, account: String, scope: Int) async throws -> JSONValue? {
        guard let context = householdContext else { return state }
        guard isCurrentBinding, scope == generation, stored.session?.account == account else { throw HarborError(code: "account-changed") }
        let incoming = try HarborLayoutDocument.state(state, key: HarborHouseholdSync.key)
        let previous = context.profiles.state, previousBinding = context.binding
        let activated = try context.activateHarbor(account: account, document: incoming, artworkServer: stored.session?.realm,
            identityOwner: HarborProfileIdentity.validOwner(owner) ? owner : nil)
        if activated { householdDidChange?() }
        if householdSync?.account != account || householdSync?.profiles !== context.profiles {
            householdSync?.invalidate(); householdSync = HarborHouseholdSync(account: account, profiles: context.profiles)
        }
        guard let engine = householdSync else { throw HarborError(code: "household-unavailable") }
        let requestSync: () -> Void = { [weak self, weak engine] in
            guard let self, let engine, self.accountID == engine.account, self.signedIn else { return }
            self.scheduleSync()
        }
        engine.requestSync = requestSync
        context.profiles.didCommit = { [weak self, weak engine] in
            if self?.busy == false, engine?.hasPendingChanges == true { requestSync() }
        }
        try await engine.synchronize(state: state) { [weak self] body in
            guard let self, self.isCurrentBinding, scope == self.generation, self.stored.session?.account == account else { throw HarborError(code: "account-changed") }
            return try await self.request("/sync/v1/push", method: "POST", body: body, scope: scope)
        }
        guard isCurrentBinding, scope == generation, stored.session?.account == account else { throw HarborError(code: "account-changed") }
        try context.refreshRouting(); context.bindProfileAppearances()
        let changed = activated || context.profiles.state != previous || context.binding != previousBinding
        guard context.ready, let active = context.profiles.active, let binding = context.binding else {
            hydrated = false; selectedID = nil; householdDidChange?(); return nil
        }
        let target = DesktopLayoutProfileTarget(id: active.syncID, primary: active.desktop.isPrimary)
        guard boundLayoutProfile == target, layoutOwner == binding.settingsOwner else {
            hydrated = false; selectedID = nil; householdDidChange?(); scheduleSync(); return nil
        }
        if changed && !activated { householdDidChange?() }
        guard let value = context.profiles.state.serverValue, let revision = context.profiles.state.serverRevision else { throw HarborError(code: "household-sync-unhydrated") }
        let roster = HarborRoster(rev: revision, value: value)
        guard roster.profile(active.syncID) != nil else { hydrated = false; scheduleSync(); return nil }
        return replacingRoster(in: state, with: roster)
    }
    private func synchronize(scope: Int) async throws {
        var state = try await request("/sync/v1/state", scope: scope)
        guard isCurrentBinding, scope == generation, let session = stored.session else { return }
        // Finish the earlier client's durable appearance queue before handing
        // account:profiles to the full roster writer; there is only one writer.
        if stored.pending?.account == session.account {
            let updated = try await flushPendingAppearance(HarborRoster.state(state), account: session.account, scope: scope)
            state = replacingRoster(in: state, with: updated)
        }
        guard let prepared = try await synchronizedHouseholdState(state, account: session.account, scope: scope) else { return }
        state = prepared
        var roster = try HarborRoster.state(state)
        let target = selectedID
        if let target, roster.profile(target) == nil { hydrated = false; throw HarborError(code: "profile-sync-target") }
        let selected: JSONValue?
        if let boundLayoutProfile { selected = boundLayoutProfile.resolve(in: roster) }
        else { selected = target.flatMap { roster.profile($0) } ?? roster.primary() }
        guard let remote = selected, let id = remote["syncId"].string else { hydrated = false; throw HarborError(code: "profile-sync-target") }
        selectedID = id; hydrated = true
        guard isCurrentBinding, scope == generation else { return }
        if let pending = stored.pending, pending.account == session.account { roster = try roster.applying(pending.fields, to: pending.syncId) }
        guard let final = roster.profile(selectedID ?? id) else { throw HarborError(code: "profile-sync-target") }
        if householdContext == nil, boundLayoutProfile == nil || boundLayoutProfile?.primary == true { try profile?.adopt(final, accountID: session.account, server: session.realm) }
        navigation.requestSync = { [weak self] in self?.scheduleSync() }
        services.requestSync = { [weak self] in self?.scheduleSync() }
        page("home").requestSync = { [weak self] in self?.scheduleSync() }
        page("anime").requestSync = { [weak self] in self?.scheduleSync() }
        let send: @MainActor (JSONValue) async throws -> JSONValue = { [weak self] body in
            guard let self, self.isCurrentBinding, scope == self.generation, self.stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
            return try await self.request("/sync/v1/push", method: "POST", body: body, scope: scope)
        }
        let check: @MainActor () throws -> Void = {
            guard self.isCurrentBinding, scope == self.generation, self.stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
        }
        var steps: [HarborLayoutSyncBatch.Step]
        if let context = householdContext {
            if householdLayouts?.account != session.account { householdLayouts?.invalidate(); householdLayouts = HarborHouseholdLayoutSync(account: session.account) }
            guard let layouts = householdLayouts else { throw HarborError(code: "household-unavailable") }
            let active = HarborHouseholdLayoutSync.Active(navigation: navigation, services: services, home: page("home"), anime: page("anime"))
            steps = [.init {
                try await layouts.synchronize(state: state, context: context, active: active,
                    requestSync: { [weak self] in self?.scheduleSync() }, send: send, check: check)
            }]
        } else {
            // The legacy facade also works before an AppModel has bound the
            // global navigation instance (for example immediately after login).
            if navigation.preferences.scope?.owner != layoutOwner { navigation.preferences.bind(.local(owner: layoutOwner)) }
            steps = [
                .init { try await self.navigation.synchronize(state: state, account: session.account, profile: final, send: send) },
                .init { try await self.services.synchronize(state: state, account: session.account, profile: final, send: send) },
                .init { try await self.page("home").synchronize(state: state, account: session.account, profile: final, send: send) },
                .init { try await self.page("anime").synchronize(state: state, account: session.account, profile: final, send: send) },
            ]
        }
        steps.append(.init {
                try await self.watchedBy.synchronize(state: state, send: send) {
                    guard self.isCurrentBinding, scope == self.generation, self.stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
                }
        })
        try await HarborLayoutSyncBatch.run(steps, check: check)
    }
}
