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
    private struct Session: Codable { let id: String; let username: String; let handle: String?; var token: String; var refresh: String }
    private struct Pending: Codable { let account: String; let syncId: String; var version: UUID; var fields: [String: JSONValue] }
    private struct Stored: Codable { var session: Session?; var pending: Pending?; var parked: [String: Pending]? }
    private static var models: [String: HarborProfileSync] = [:]
    static func forOwner(_ owner: String, profile: ProfilePreferences) -> HarborProfileSync {
        if let existing = models[owner] { return existing }
        let value = HarborProfileSync(owner: owner, profile: profile); models[owner] = value; return value
    }
    private let key: String
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
    var username: String? { stored.session?.username }
    var accountID: String? { stored.session?.id }
    var handle: String? { stored.session?.handle }
    var hasPendingChanges: Bool { stored.pending != nil }
    private init(owner: String, profile: ProfilePreferences) {
        key = "harbor-identity-" + EBookShelf.hash(owner); self.profile = profile
        reload()
    }
    func reload() {
        guard !busy else { return }
        do { stored = try KeychainStore().read(key, as: Stored.self) ?? Stored(); ready = true; error = nil }
        catch { ready = false; self.error = "No se pudo recuperar la cuenta de Harbor. Los datos guardados se conservan." }
    }
    func signIn(username: String, password: String) async {
        guard ready, !busy else { return }
        busy = true; error = nil; generation += 1; let scope = generation
        defer { if scope == generation { busy = false } }
        do {
            let response = try await HTTPClient().harbor("/identity/api/login", method: "POST", body: .object(["username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)), "password": .string(password)]))
            try Task.checkCancellation(); guard scope == generation else { return }
            guard let token = response["token"].string, !token.isEmpty, let refresh = response["refresh"].string, !refresh.isEmpty,
                  let id = response["user"]["id"].string, !id.isEmpty, let name = response["user"]["username"].string else { throw HarborError(code: "profile-auth-response") }
            let session = Session(id: id, username: name, handle: response["user"]["handle"].string, token: token, refresh: refresh)
            var parked = stored.parked ?? [:]
            if let pending = stored.pending, pending.account != id { parked[pending.account] = pending }
            let pending = stored.pending?.account == id ? stored.pending : parked.removeValue(forKey: id)
            let next = Stored(session: session, pending: pending, parked: parked)
            try persist(next); stored = next; selectedID = nil; hydrated = false
            try await synchronize(scope: scope)
        } catch is CancellationError { return }
        catch { if scope == generation { self.error = safeMessage(error) } }
    }
    func signOut() async {
        guard ready, !busy else { return }
        generation += 1; let token = stored.session?.token
        scheduled?.cancel(); scheduled = nil
        do {
            // Keep unacknowledged changes bound to their original account for a later login.
            let next = Stored(session: nil, pending: stored.pending, parked: stored.parked); try persist(next); stored = next
            hydrated = false; selectedID = nil; error = nil
        } catch { self.error = "No se pudo cerrar la sesión. Vuelve a intentarlo."; return }
        if let token { _ = try? await HTTPClient().harbor("/auth/logout", method: "POST", body: .object([:]), token: token) }
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
        guard hydrated, let session = stored.session, let id = selectedID else { return }
        var fields: [String: JSONValue] = [:]
        if before.name != after.name { fields["name"] = .string(String(after.name.prefix(32))) }
        if before.color != after.color { fields["color"] = .string("#" + after.color) }
        if before.avatar != after.avatar || before.photo != after.photo || before.remoteAvatar != after.remoteAvatar || before.initialsAvatar != after.initialsAvatar {
            // Desktop's roster only transmits portable bundled avatar paths.
            fields["avatar"] = after.photo == nil ? .string("/avatars/\(after.avatar).webp") : .null
        }
        guard !fields.isEmpty else { return }
        var pending = stored.pending?.account == session.id && stored.pending?.syncId == id ? stored.pending : nil
        if pending == nil { pending = Pending(account: session.id, syncId: id, version: UUID(), fields: [:]) }
        for (name, value) in fields { pending?.fields[name] = value }
        pending?.version = UUID()
        do { var next = stored; next.pending = pending; try persist(next); stored = next; error = nil }
        catch { self.error = "No se pudieron guardar los cambios para sincronizar. Vuelve a intentarlo."; return }
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
            let value = try await HTTPClient().harbor(path, method: method, body: body, token: session.token)
            guard scope == generation, stored.session?.id == session.id else { throw HarborError(code: "account-changed") }
            return value
        } catch let failure as HarborError where failure.code == "http-401" {
            let response = try await HTTPClient().harbor("/identity/api/token/refresh", method: "POST", body: .object(["refresh": .string(session.refresh)]))
            guard scope == generation, stored.session?.id == session.id, stored.session?.refresh == session.refresh,
                  let token = response["token"].string, !token.isEmpty, let refresh = response["refresh"].string, !refresh.isEmpty else { throw HarborError(code: "profile-auth-response") }
            var next = stored; next.session?.token = token; next.session?.refresh = refresh
            try persist(next); stored = next
            let value = try await HTTPClient().harbor(path, method: method, body: body, token: token)
            guard scope == generation else { throw HarborError(code: "account-changed") }
            return value
        }
    }
    private func synchronize(scope: Int) async throws {
        var roster = try HarborRoster.state(try await request("/sync/v1/state", scope: scope))
        guard scope == generation, let session = stored.session else { return }
        let target = stored.pending?.account == session.id ? stored.pending?.syncId : selectedID
        if let target, roster.profile(target) == nil { hydrated = false; throw HarborError(code: "profile-sync-target") }
        guard let remote = target.flatMap({ roster.profile($0) }) ?? roster.primary(), let id = remote["syncId"].string else { hydrated = false; throw HarborError(code: "profile-sync-target") }
        selectedID = id; hydrated = true
        if let pending = stored.pending, pending.account == session.id {
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
        guard scope == generation else { return }
        if let pending = stored.pending, pending.account == session.id { roster = try roster.applying(pending.fields, to: pending.syncId) }
        guard let final = roster.profile(selectedID ?? id) else { throw HarborError(code: "profile-sync-target") }
        try profile?.adopt(final, accountID: session.id)
    }
}
