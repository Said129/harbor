import Foundation
import Observation

@MainActor protocol MALSessionPersistence {
    func readMALSession(owner: String) throws -> MALSession?
    func writeMALSession(_ session: MALSession?, owner: String) throws
}

@MainActor struct KeychainMALAccount: MALSessionPersistence {
    private func key(_ owner: String) throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "mal-profile") }
        return "native-mal-session-v1-" + EBookShelf.hash(owner)
    }
    func readMALSession(owner: String) throws -> MALSession? { try KeychainStore().read(key(owner), as: MALSession.self) }
    func writeMALSession(_ session: MALSession?, owner: String) throws {
        let key = try key(owner)
        if let session { try KeychainStore().write(session, key: key) } else { try KeychainStore().remove(key) }
    }
}

/// The MyAnimeList account of one profile (Desktop's `lib/mal/session.ts`, `validate.ts` and `auth.ts` refresh).
@MainActor @Observable final class MALAccount {
    private static var accounts: [String: MALAccount] = [:]
    static func forOwner(_ owner: String) -> MALAccount {
        if let saved = accounts[owner] { return saved }
        let account = MALAccount(owner: owner); accounts[owner] = account; return account
    }
    /// Desktop's `malAutoSync` setting, on unless switched off.
    static var autoSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: "malAutoSync") == nil || UserDefaults.standard.bool(forKey: "malAutoSync")
    }

    let owner: String
    private let persistence: any MALSessionPersistence
    private(set) var session: MALSession?
    private(set) var ready = false
    private(set) var lastEvent: AniListSyncEvent?
    private var refreshing: Task<String?, Never>?
    private var validating = false

    init(owner: String, persistence: (any MALSessionPersistence)? = nil) {
        self.owner = owner; self.persistence = persistence ?? KeychainMALAccount()
    }

    func load() throws {
        let saved = try persistence.readMALSession(owner: owner)
        guard saved?.valid ?? true else { throw HarborError(code: "mal-session") }
        session = saved; ready = true
    }

    func set(_ value: MALSession?) throws {
        guard ready, value?.valid ?? true else { throw HarborError(code: "mal-session") }
        // Commit before announcing a login or logout: a failed Keychain write leaves the last session in place.
        try persistence.writeMALSession(value, owner: owner)
        session = value
        if value == nil { lastEvent = nil }
    }

    func record(_ event: AniListSyncEvent) { lastEvent = event }

    /// Desktop's `ensureRefreshed`: one refresh at a time. Returns the new access token, or nil when MyAnimeList
    /// refused the refresh token (the session is then dropped) or could not be reached (the session is kept).
    func refresh(transport: any MALTransport = MALHTTPTransport()) async -> String? {
        if let refreshing { return await refreshing.value }
        guard let current = session else { return nil }
        let task = Task { () -> String? in
            do {
                if let next = try await MALAuth.refreshed(current, transport: transport) {
                    guard self.session?.accessToken == current.accessToken else { return self.session?.accessToken }
                    try? self.set(next)
                    return next.accessToken
                }
                if self.session?.accessToken == current.accessToken { try? self.set(nil) }
                return nil
            } catch { return nil }
        }
        refreshing = task
        let result = await task.value
        refreshing = nil
        return result
    }

    /// Desktop's `validateMalSession`: a token MyAnimeList answers 401 to is refreshed, or the session dropped.
    func validate(transport: any MALTransport = MALHTTPTransport()) async {
        guard let current = session, !validating else { return }
        validating = true; defer { validating = false }
        do { _ = try await MALClient(transport: transport).request("/users/@me", token: current.accessToken) }
        catch let error as MALAPIError where error.status == 401 { _ = await refresh(transport: transport) }
        catch { }
    }
}

/// Desktop's `useMal` connect states.
@MainActor @Observable final class MALConnectModel {
    enum State: Equatable { case idle, needsCode, verifying, success(String), failure(String) }
    private(set) var state = State.idle
    let account: MALAccount
    private let transport: any MALTransport
    private var verifier: String?
    private var task: Task<Void, Never>?

    init(account: MALAccount, transport: any MALTransport = MALHTTPTransport()) {
        self.account = account; self.transport = transport
    }

    /// A fresh challenge each time, so only the newest code from the page is accepted. The view opens the address.
    func begin() -> URL? {
        task?.cancel(); task = nil
        let challenge = MALAuth.makeVerifier()
        verifier = challenge; state = .needsCode
        return MALAuth.authorizeURL(verifier: challenge)
    }

    func submit(_ pasted: String) {
        task?.cancel()
        state = .verifying
        let transport = transport, challenge = verifier
        task = Task { [weak self] in
            do {
                let session = try await MALAuth.session(from: pasted, verifier: challenge, transport: transport)
                try Task.checkCancellation()
                guard let self else { return }
                try self.account.set(session)
                self.verifier = nil
                self.state = .success(session.userName)
            } catch is CancellationError {
            } catch let error as TrackerUserError {
                self?.state = .failure(error.message)
            } catch {
                self?.state = .failure("Couldn't connect to MyAnimeList.")
            }
        }
    }

    func cancel() { task?.cancel(); task = nil; verifier = nil; state = .idle }
}
