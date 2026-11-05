import Foundation
import Observation

@MainActor protocol AniListSessionPersistence {
    func readAniListSession(owner: String) throws -> AniListSession?
    func writeAniListSession(_ session: AniListSession?, owner: String) throws
}

@MainActor struct KeychainAniListAccount: AniListSessionPersistence {
    private func key(_ owner: String) throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "anilist-profile") }
        return "native-anilist-session-v1-" + EBookShelf.hash(owner)
    }
    func readAniListSession(owner: String) throws -> AniListSession? { try KeychainStore().read(key(owner), as: AniListSession.self) }
    func writeAniListSession(_ session: AniListSession?, owner: String) throws {
        let key = try key(owner)
        if let session { try KeychainStore().write(session, key: key) } else { try KeychainStore().remove(key) }
    }
}

/// The AniList account of one profile (Desktop's `lib/anilist/session.ts` and `validate.ts`).
@MainActor @Observable final class AniListAccount {
    private static var accounts: [String: AniListAccount] = [:]
    static func forOwner(_ owner: String) -> AniListAccount {
        if let saved = accounts[owner] { return saved }
        let account = AniListAccount(owner: owner); accounts[owner] = account; return account
    }
    /// Desktop's `anilistAutoSync` setting, on unless switched off.
    static var autoSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: "anilistAutoSync") == nil || UserDefaults.standard.bool(forKey: "anilistAutoSync")
    }

    let owner: String
    private let persistence: any AniListSessionPersistence
    private(set) var session: AniListSession?
    private(set) var ready = false
    /// The last sync Desktop would show in its toast.
    private(set) var lastEvent: AniListSyncEvent?
    private var validating = false

    init(owner: String, persistence: (any AniListSessionPersistence)? = nil) {
        self.owner = owner; self.persistence = persistence ?? KeychainAniListAccount()
    }

    func load() throws {
        let saved = try persistence.readAniListSession(owner: owner)
        guard saved?.valid ?? true else { throw HarborError(code: "anilist-session") }
        session = saved; ready = true
    }

    func set(_ value: AniListSession?) throws {
        guard ready, value?.valid ?? true else { throw HarborError(code: "anilist-session") }
        // Commit before announcing a login or logout: a failed Keychain write leaves the last session in place.
        try persistence.writeAniListSession(value, owner: owner)
        session = value
        if value == nil { lastEvent = nil }
    }

    func record(_ event: AniListSyncEvent) { lastEvent = event }

    /// Desktop's `validateAnilistSession`: refresh the avatar, and drop a session AniList no longer accepts.
    func validate(transport: any AniListTransport = AniListHTTPTransport()) async {
        guard let current = session, !validating else { return }
        validating = true; defer { validating = false }
        do {
            let viewer = try await AniListClient(transport: transport).viewer(token: current.accessToken)
            guard session?.accessToken == current.accessToken else { return }
            if let avatar = viewer.avatar, avatar != current.avatar {
                var refreshed = current; refreshed.avatar = avatar
                try? set(refreshed)
            }
        } catch let error as AniListAPIError where error.isAuthenticationError {
            if session?.accessToken == current.accessToken { try? set(nil) }
        } catch { }
    }
}

/// Desktop's `useAnilist` connect states.
@MainActor @Observable final class AniListConnectModel {
    enum State: Equatable { case idle, needsCode, verifying, success(String), failure(String) }
    private(set) var state = State.idle
    let account: AniListAccount
    private let transport: any AniListTransport
    private var task: Task<Void, Never>?

    init(account: AniListAccount, transport: any AniListTransport = AniListHTTPTransport()) {
        self.account = account; self.transport = transport
    }

    /// The view opens AniList's authorize page; the person then pastes the code it shows.
    func begin() { task?.cancel(); task = nil; state = .needsCode }

    func submit(_ pasted: String) {
        task?.cancel()
        state = .verifying
        let transport = transport
        task = Task { [weak self] in
            do {
                let session = try await AniListAuth.session(from: pasted, transport: transport)
                try Task.checkCancellation()
                guard let self else { return }
                try self.account.set(session)
                self.state = .success(session.userName)
            } catch is CancellationError {
            } catch let error as AniListUserError {
                self?.state = .failure(error.message)
            } catch let error as AniListAPIError {
                self?.state = .failure("AniList HTTP \(error.status): \(error.body.prefix(200))")
            } catch {
                self?.state = .failure("Couldn't connect to AniList.")
            }
        }
    }

    func cancel() { task?.cancel(); task = nil; state = .idle }
}
