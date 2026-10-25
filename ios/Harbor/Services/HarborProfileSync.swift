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
    private static var models: [String: HarborProfileSync] = [:]
    static func forOwner(_ owner: String, profile: ProfilePreferences) -> HarborProfileSync {
        if let existing = models[owner] { return existing }
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
    @ObservationIgnored private var householdDidChange: (() -> Void)?
    func bindHouseholdContext(_ context: AppProfileContext, didChange: @escaping () -> Void) {
        householdContext = context; householdDidChange = didChange
    }
    func requestHouseholdSynchronization() { if signedIn { scheduleSync() } }
    var watchedBy: HarborWatchedBySync {
        let bucket = HouseholdProfileScope.hash([stored.session == nil ? "local" : "harbor", stored.session?.account ?? ""])
        if let value = watchedByBindings[bucket] { return value }
        let value = HarborWatchedBySync(owner: owner, account: stored.session?.account)
        value.requestSync = { [weak self, weak value] in
            guard let self, let value, self.signedIn, value.account == self.accountID else { return }
            self.scheduleSync()
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
    private weak var profile: ProfilePreferences?
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
    var hasPendingChanges: Bool { stored.pending != nil || householdSync?.hasPendingChanges == true || navigation.hasPendingChanges || services.hasPendingChanges || page("home").hasPendingChanges || page("anime").hasPendingChanges || watchedBy.hasPendingChanges }
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
        guard !server.retired else { throw HarborError(code: "harbor-server-retired") }
        return try await transport(server, path, method, body, token)
    }
    func bindLayoutOwner(_ next: String, profileID: String? = nil, primary: Bool = false) {
        let target = profileID.map { DesktopLayoutProfileTarget(id: $0, primary: primary) }
        guard next != layoutOwner || target != boundLayoutProfile else { return }
        suspendForProfileChange(); boundLayoutOwner = next; boundLayoutProfile = target; selectedID = nil
    }
    /// Keep sessions and durable queues; invalidate late replies from a source
    /// which no longer owns the visible interface and preference bindings.
    func suspendForProfileChange() {
        generation += 1; scheduled?.cancel(); scheduled = nil; busy = false; hydrated = false
        householdSync?.invalidate()
        navigation.unbind(); services.unbind(); page("home").unbind(); page("anime").unbind()
    }
    func reload() {
        guard !busy else { return }
        do { stored = try KeychainStore().read(key, as: Stored.self) ?? Stored(); ready = true; error = nil }
        catch { ready = false; self.error = "No se pudo recuperar la cuenta de Harbor. Los datos guardados se conservan." }
    }
    func signIn(username: String, password: String, server: HarborIdentityServer) async {
        guard ready, !busy else { return }
        busy = true; error = nil; generation += 1; let scope = generation
        defer { if scope == generation { busy = false } }
        do {
            let response = try await send(server, "/identity/api/login", "POST", .object(["username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)), "password": .string(password)]), nil)
            try Task.checkCancellation(); guard scope == generation else { return }
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
                navigation.unbind()
                services.unbind()
                page("home").unbind(); page("anime").unbind()
                page("home").preferences.bind(.local(owner: layoutOwner)); page("anime").preferences.bind(.local(owner: layoutOwner))
                StreamingPreferences.forOwner(layoutOwner).bind(.local(owner: layoutOwner))
                if InterfacePreferences.shared.navigation.scope?.owner == layoutOwner { InterfacePreferences.shared.navigation.bind(.local(owner: layoutOwner)) }
            }
            try await synchronize(scope: scope)
        } catch is CancellationError { return }
        catch { if scope == generation { self.error = safeMessage(error) } }
    }
    func signOut() async {
        guard ready, !busy else { return }
        generation += 1; let session = stored.session
        householdSync?.invalidate()
        scheduled?.cancel(); scheduled = nil
        do {
            // Keep unacknowledged changes bound to their original account for a later login.
            let next = Stored(session: nil, pending: stored.pending, parked: stored.parked); try persist(next); stored = next
            hydrated = false; selectedID = nil; error = nil
            navigation.unbind()
            services.unbind()
            page("home").unbind(); page("anime").unbind()
            page("home").preferences.bind(.local(owner: layoutOwner)); page("anime").preferences.bind(.local(owner: layoutOwner))
            StreamingPreferences.forOwner(layoutOwner).bind(.local(owner: layoutOwner))
            if InterfacePreferences.shared.navigation.scope?.owner == layoutOwner { InterfacePreferences.shared.navigation.bind(.local(owner: layoutOwner)) }
        } catch { self.error = "No se pudo cerrar la sesión. Vuelve a intentarlo."; return }
        if let session { _ = try? await send(session.realm, "/auth/logout", "POST", .object([:]), session.token) }
    }
    func sync() async {
        guard ready, signedIn, !busy else { return }
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
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)); try Task.checkCancellation() } catch { return }
            await self?.sync()
        }
    }
    private func persist(_ value: Stored) throws { try KeychainStore().write(value, key: key) }
    private func request(_ path: String, method: String = "GET", body: JSONValue? = nil, scope: Int) async throws -> JSONValue {
        guard scope == generation, let session = stored.session else { throw HarborError(code: "account-changed") }
        do {
            let value = try await send(session.realm, path, method, body, session.token)
            guard scope == generation, stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
            return value
        } catch let failure as HarborError where failure.code == "http-401" {
            guard scope == generation, stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
            let response = try await send(session.realm, "/identity/api/token/refresh", "POST", .object(["refresh": .string(session.refresh)]), nil)
            guard scope == generation, stored.session?.account == session.account, stored.session?.refresh == session.refresh,
                  let token = response["token"].string, !token.isEmpty, let refresh = response["refresh"].string, !refresh.isEmpty else { throw HarborError(code: "profile-auth-response") }
            var next = stored; next.session?.token = token; next.session?.refresh = refresh
            try persist(next); stored = next
            let value = try await send(session.realm, path, method, body, token)
            guard scope == generation else { throw HarborError(code: "account-changed") }
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
        guard scope == generation, stored.session?.account == account else { throw HarborError(code: "account-changed") }
        let incoming = try HarborLayoutDocument.state(state, key: HarborHouseholdSync.key)
        let previous = context.profiles.state, previousBinding = context.binding
        let activated = try context.activateHarbor(account: account, document: incoming, artworkServer: stored.session?.realm)
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
            guard let self, scope == self.generation, self.stored.session?.account == account else { throw HarborError(code: "account-changed") }
            return try await self.request("/sync/v1/push", method: "POST", body: body, scope: scope)
        }
        guard scope == generation, stored.session?.account == account else { throw HarborError(code: "account-changed") }
        try context.refreshRouting(); context.bindProfileAppearances()
        let changed = activated || context.profiles.state != previous || context.binding != previousBinding
        guard context.ready, let active = context.profiles.active, let binding = context.binding else {
            hydrated = false; selectedID = nil; householdDidChange?(); return nil
        }
        let target = DesktopLayoutProfileTarget(id: active.syncID, primary: active.desktop.isPrimary)
        guard boundLayoutProfile == target, layoutOwner == binding.settingsOwner else {
            hydrated = false; selectedID = nil; householdDidChange?(); scheduleSync(); return nil
        }
        if changed { householdDidChange?() }
        guard let value = context.profiles.state.serverValue, let revision = context.profiles.state.serverRevision else { throw HarborError(code: "household-sync-unhydrated") }
        let roster = HarborRoster(rev: revision, value: value)
        guard roster.profile(active.syncID) != nil else { hydrated = false; scheduleSync(); return nil }
        return replacingRoster(in: state, with: roster)
    }
    private func synchronize(scope: Int) async throws {
        var state = try await request("/sync/v1/state", scope: scope)
        guard scope == generation, let session = stored.session else { return }
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
        guard scope == generation else { return }
        if let pending = stored.pending, pending.account == session.account { roster = try roster.applying(pending.fields, to: pending.syncId) }
        guard let final = roster.profile(selectedID ?? id) else { throw HarborError(code: "profile-sync-target") }
        if householdContext == nil, boundLayoutProfile == nil || boundLayoutProfile?.primary == true { try profile?.adopt(final, accountID: session.account, server: session.realm) }
        navigation.requestSync = { [weak self] in self?.scheduleSync() }
        services.requestSync = { [weak self] in self?.scheduleSync() }
        page("home").requestSync = { [weak self] in self?.scheduleSync() }
        page("anime").requestSync = { [weak self] in self?.scheduleSync() }
        let send: @MainActor (JSONValue) async throws -> JSONValue = { [weak self] body in
            guard let self, scope == self.generation, self.stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
            return try await self.request("/sync/v1/push", method: "POST", body: body, scope: scope)
        }
        try await HarborLayoutSyncBatch.run([
            .init { try await self.navigation.synchronize(state: state, account: session.account, profile: final, send: send) },
            .init { try await self.services.synchronize(state: state, account: session.account, profile: final, send: send) },
            .init { try await self.page("home").synchronize(state: state, account: session.account, profile: final, send: send) },
            .init { try await self.page("anime").synchronize(state: state, account: session.account, profile: final, send: send) },
            .init {
                try await self.watchedBy.synchronize(state: state, send: send) {
                    guard scope == self.generation, self.stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
                }
            },
        ]) {
            guard scope == self.generation, self.stored.session?.account == session.account else { throw HarborError(code: "account-changed") }
        }
    }
}
