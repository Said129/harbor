import Foundation
import Observation

@MainActor protocol TraktAccountPersistence {
    func read(owner: String) throws -> TraktSession?
    func write(_ session: TraktSession?, owner: String) throws
}
@MainActor private struct KeychainTraktAccount: TraktAccountPersistence {
    private func key(_ owner: String) throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "trakt-owner") }
        return "native-trakt-session-v1-" + EBookShelf.hash(owner)
    }
    func read(owner: String) throws -> TraktSession? { try KeychainStore().read(key(owner), as: TraktSession.self) }
    func write(_ session: TraktSession?, owner: String) throws {
        let key = try key(owner)
        if let session { try KeychainStore().write(session, key: key) } else { try KeychainStore().remove(key) }
    }
}
@MainActor @Observable final class TraktAccountStore {
    private static var stores: [String: TraktAccountStore] = [:]
    static func forOwner(_ owner: String) -> TraktAccountStore {
        if let saved = stores[owner] { return saved }
        let store = TraktAccountStore(owner: owner); stores[owner] = store; return store
    }
    let owner: String
    private let persistence: any TraktAccountPersistence
    private(set) var session: TraktSession?
    private(set) var ready = false
    private(set) var identity = UUID()
    @ObservationIgnored private var refreshing: (id: UUID, identity: UUID, token: String, task: Task<TraktSession, Error>)?
    init(owner: String, persistence: (any TraktAccountPersistence)? = nil) { self.owner = owner; self.persistence = persistence ?? KeychainTraktAccount() }
    func load() throws {
        var value = try persistence.read(owner: owner)
        guard value?.valid ?? true else { throw HarborError(code: "trakt-session") }
        if var legacy = value, legacy.trackingID == nil {
            legacy.trackingID = UUID(); try persistence.write(legacy, owner: owner); value = legacy
        }
        if value != session { identity = UUID() }; session = value; ready = true
    }
    func set(_ value: TraktSession?) throws {
        guard ready, value?.valid ?? true else { throw HarborError(code: "trakt-session") }
        var next = value
        if next?.trackingID == nil { next?.trackingID = UUID() }
        try persistence.write(next, owner: owner); session = next; identity = UUID()
    }
    private func allows(_ identity: UUID, token: String, active: TraktClient.Active? = nil) -> Bool {
        ready && self.identity == identity && session?.accessToken == token && (active?() ?? true)
    }
    private func renew(_ captured: TraktSession, identity: UUID, client: TraktClient, active: @escaping TraktClient.Active) async throws -> TraktSession {
        guard self.identity == identity, active(), let current = session else { throw CancellationError() }
        if current.accessToken != captured.accessToken { return current }
        if let refreshing, refreshing.identity == identity, refreshing.token == captured.accessToken { return try await refreshing.task.value }
        let id = UUID()
        let task = Task<TraktSession, Error> {
            let reply = try await client.reply(.refresh(captured.refreshToken), current: { [weak self] in
                await self?.allows(identity, token: captured.accessToken, active: active) ?? false
            }, accept: { [weak self] in await self?.allows(identity, token: captured.accessToken) ?? false })
            // A refresh can rotate the secret while its profile leaves the
            // foreground. Preserve that rotation only in the same still-owned
            // account; an explicit disconnect/replacement invalidates it.
            var next = try TraktSession(reply.value(), username: captured.username)
            next.trackingID = captured.trackingID
            guard self.allows(identity, token: captured.accessToken) else { throw CancellationError() }
            try self.persistence.write(next, owner: self.owner); self.session = next; return next
        }
        refreshing = (id, identity, captured.accessToken, task)
        defer { if refreshing?.id == id { refreshing = nil } }
        return try await task.value
    }
    func response(_ endpoint: TraktEndpoint, client: TraktClient = .shared, active: @escaping TraktClient.Active) async throws -> JSONValue {
        guard endpoint.authenticated, ready, session != nil, active() else { throw HarborError(code: "trakt-not-connected") }
        let identity = identity
        for attempt in 0...1 {
            guard self.identity == identity, active(), let captured = session else { throw CancellationError() }
            let lease: TraktClient.Lease = { [weak self] in await self?.allows(identity, token: captured.accessToken, active: active) ?? false }
            do {
                var reply = try await client.reply(endpoint, token: captured.accessToken, current: lease)
                if reply.status == 401 && attempt == 0 {
                    _ = try await renew(captured, identity: identity, client: client, active: active); continue
                }
                if reply.status == 429 {
                    try await client.pause(reply.retryDelay)
                    reply = try await client.reply(endpoint, token: captured.accessToken, current: lease)
                }
                guard self.identity == identity, active() else { throw CancellationError() }; return try reply.value()
            } catch is CancellationError {
                if attempt == 0, self.identity == identity, active(), session?.accessToken != captured.accessToken { continue }
                throw CancellationError()
            }
        }
        throw TraktAPIError(status: 401)
    }
}
