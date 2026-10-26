import Foundation
import Observation

@MainActor protocol SimklAccountPersistence {
    func readSimklSession(owner: String) throws -> SimklSession?
    func writeSimklSession(_ session: SimklSession?, owner: String) throws
}
@MainActor struct KeychainSimklAccount: SimklAccountPersistence {
    private func key(_ owner: String) throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "simkl-profile") }
        return "native-simkl-session-v1-" + EBookShelf.hash(owner)
    }
    func readSimklSession(owner: String) throws -> SimklSession? { try KeychainStore().read(key(owner), as: SimklSession.self) }
    func writeSimklSession(_ session: SimklSession?, owner: String) throws {
        let key = try key(owner)
        if let session { try KeychainStore().write(session, key: key) } else { try KeychainStore().remove(key) }
    }
}
@MainActor @Observable final class SimklAccountStore {
    let owner: String
    private let persistence: any SimklAccountPersistence
    private(set) var session: SimklSession?
    private(set) var ready = false
    init(owner: String, persistence: (any SimklAccountPersistence)? = nil) {
        self.owner = owner; self.persistence = persistence ?? KeychainSimklAccount()
    }
    func load() throws {
        let saved = try persistence.readSimklSession(owner: owner)
        guard saved?.valid ?? true else { throw HarborError(code: "simkl-session") }
        session = saved; ready = true
    }
    func set(_ value: SimklSession?) throws {
        guard ready, value?.valid ?? true else { throw HarborError(code: "simkl-session") }
        // Commit before announcing a login/logout; a failed keychain operation
        // must leave the last durable session visible and usable.
        try persistence.writeSimklSession(value, owner: owner); session = value
    }
}
