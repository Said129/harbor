import Foundation

struct ContinueDismissalState: Codable, Sendable {
    var version = 1
    var documents: [String: [String: ContinueDismissal]] = [:]
    var migrations: Set<String> = []
    var valid: Bool {
        version == 1 && documents.count <= 256 && migrations.count <= 256
            && migrations.allSatisfy { !$0.isEmpty && $0.utf8.count <= 512 }
            && documents.allSatisfy { owner, values in
                !owner.isEmpty && owner.utf8.count <= 512 && values.count <= 2_000
                    && values.allSatisfy { !$0.key.isEmpty && $0.key.utf8.count <= 4_096 && $0.value.valid }
            }
    }
}
@MainActor protocol ContinueDismissalPersistence {
    func read() throws -> ContinueDismissalState?
    func write(_ value: ContinueDismissalState) throws
    func legacy(_ owner: String) throws -> [String: ContinueDismissal]
}
@MainActor private struct KeychainContinueDismissals: ContinueDismissalPersistence {
    func read() throws -> ContinueDismissalState? { try KeychainStore().read("private-continue-dismissals-v1", as: ContinueDismissalState.self) }
    func write(_ value: ContinueDismissalState) throws { try KeychainStore().write(value, key: "private-continue-dismissals-v1") }
    func legacy(_ owner: String) throws -> [String: ContinueDismissal] {
        guard let value = try KeychainStore().read(LibraryPresentation.key(owner: owner), as: LibraryPresentation.self) else { return [:] }
        guard value.valid else { throw HarborError(code: "continue-dismissals-read") }; return value.dismissed
    }
}

/// The old shared choices seed only profiles that exist at the first migration.
/// An explicit empty private document is a newer choice and must survive it.
@MainActor final class ContinueDismissalStore {
    static let shared = ContinueDismissalStore()
    private let persistence: any ContinueDismissalPersistence
    private var state: ContinueDismissalState?
    init(persistence: (any ContinueDismissalPersistence)? = nil) { self.persistence = persistence ?? KeychainContinueDismissals() }
    private func loaded() throws -> ContinueDismissalState {
        if let state { return state }
        let value = try persistence.read() ?? .init()
        guard value.valid else { throw HarborError(code: "continue-dismissals-read") }; state = value; return value
    }
    private func commit(_ value: ContinueDismissalState) throws {
        guard value.valid, try JSONEncoder().encode(value).count <= 8 * 1_024 * 1_024 else { throw HarborError(code: "continue-dismissals-write") }
        try persistence.write(value); state = value
    }
    func migrate(scope: String, existingOwners: [String: String]) throws {
        var next = try loaded()
        guard !next.migrations.contains(scope) else { return }
        guard !scope.isEmpty, scope.utf8.count <= 512, !existingOwners.isEmpty else { throw HarborError(code: "continue-dismissals-migration") }
        for (personal, legacy) in existingOwners where next.documents[personal] == nil {
            next.documents[personal] = try persistence.legacy(legacy)
        }
        next.migrations.insert(scope); try commit(next)
    }
    func values(owner: String) throws -> [String: ContinueDismissal] { try loaded().documents[owner] ?? [:] }
    func requireMigration(scope: String) throws {
        guard try loaded().migrations.contains(scope) else { throw HarborError(code: "continue-dismissals-migration") }
    }
    func change(owner: String, _ edit: (inout [String: ContinueDismissal]) -> Void) throws -> [String: ContinueDismissal] {
        var next = try loaded(), values = next.documents[owner] ?? [:]
        edit(&values); next.documents[owner] = values; try commit(next); return values
    }
}
