import Foundation
import Observation

enum NavigationScope: Equatable, Sendable {
    case local(owner: String)
    case harbor(owner: String, account: String, profile: String, linked: Bool)
    var owner: String { switch self { case .local(let owner), .harbor(let owner, _, _, _): owner } }
    var key: String {
        let parts: [String]
        switch self {
        case .local(let owner): parts = [owner, "local"]
        case .harbor(let owner, let account, let profile, let linked): parts = [owner, "harbor", account, linked ? "shared" : "profile", linked ? "" : profile]
        }
        // A canonical array avoids delimiter collisions in remote identifiers.
        let data = try! JSONEncoder().encode(parts)
        return "navigation-layout-" + EBookShelf.hash(String(decoding: data, as: UTF8.self))
    }
}

@MainActor protocol NavigationLayoutPersistence {
    func read(_ key: String) throws -> NativeNavigationLayout?
    func write(_ value: NativeNavigationLayout, key: String) throws
}
@MainActor struct KeychainNavigationPersistence: NavigationLayoutPersistence {
    func read(_ key: String) throws -> NativeNavigationLayout? { try KeychainStore().read(key, as: NativeNavigationLayout.self) }
    func write(_ value: NativeNavigationLayout, key: String) throws { try KeychainStore().write(value, key: key) }
}

@MainActor @Observable
final class ScopedNavigationPreferences {
    private let storage: UserDefaults
    private let persistence: any NavigationLayoutPersistence
    private static let migrationOwnerKey = "iphone.nav.migration.owner.v1"
    private(set) var value = NativeNavigationLayout()
    private(set) var scope: NavigationScope?
    private(set) var ready = false
    private(set) var error: String?
    @ObservationIgnored var onEdit: ((NativeNavigationLayout) -> Void)?

    init(storage: UserDefaults = .standard, persistence: (any NavigationLayoutPersistence)? = nil) {
        self.storage = storage; self.persistence = persistence ?? KeychainNavigationPersistence()
        // Do not display or assign the old global sidebar until the account
        // has been restored and its migration owner is known.
    }

    func bind(_ scope: NavigationScope) {
        if self.scope == scope && ready { return }
        if self.scope != scope { value = NativeNavigationLayout() }
        onEdit = nil; ready = false; error = nil; self.scope = scope
        do {
            let next: NativeNavigationLayout
            if let saved = try persistence.read(scope.key) { next = saved }
            else {
                switch scope {
                case .local(let owner):
                    if let marker = storage.object(forKey: Self.migrationOwnerKey), !(marker is String) { throw HarborError(code: "navigation-store") }
                    let migrationOwner = storage.string(forKey: Self.migrationOwnerKey)
                    let legacy: NativeNavigationLayout
                    if migrationOwner == nil || migrationOwner == owner { legacy = try legacyValue() }
                    else { legacy = NativeNavigationLayout() }
                    if hasLegacyValue && (migrationOwner == nil || migrationOwner == owner) {
                        guard legacy.valid else { throw HarborError(code: "navigation-store") }
                        try persistence.write(legacy, key: scope.key)
                        storage.set(owner, forKey: Self.migrationOwnerKey)
                    }
                    next = legacy
                case .harbor(let owner, _, _, _):
                    // Start from this Stremio owner's local choices, never the
                    // previously displayed Harbor account's configuration.
                    next = try persistence.read(NavigationScope.local(owner: owner).key) ?? NativeNavigationLayout()
                }
            }
            guard next.valid else { throw HarborError(code: "navigation-store") }
            value = next; ready = true
        } catch { self.error = "Could not load navigation settings. Saved settings are kept." }
    }

    func reload() { guard let scope else { return }; ready = false; bind(scope) }
    func change(in expected: NavigationScope? = nil, _ edit: (inout NativeNavigationLayout) -> Void) {
        guard ready, let scope, expected == nil || expected == scope else { return }
        var next = value; edit(&next)
        guard next != value else { return }
        do {
            guard next.valid else { throw HarborError(code: "navigation-store") }
            try persistence.write(next, key: scope.key)
            value = next; error = nil; onEdit?(next)
        } catch { self.error = "Could not save navigation settings. Your previous settings are kept." }
    }
    func apply(_ next: NativeNavigationLayout, to expected: NavigationScope) throws {
        guard ready, scope == expected, next.valid else { throw HarborError(code: "account-changed") }
        if value != next { try persistence.write(next, key: expected.key); value = next }
        error = nil
    }
    private var hasLegacyValue: Bool { ["iphone.nav.order", "iphone.nav.hidden", "iphone.nav.names"].contains { storage.object(forKey: $0) != nil } }
    private func legacyValue() throws -> NativeNavigationLayout {
        func ids(_ key: String) throws -> [String] {
            guard let raw = storage.object(forKey: key) else { return [] }
            guard let values = raw as? [String] else { throw HarborError(code: "navigation-store") }
            return values
        }
        let order = try ids("iphone.nav.order"), hidden = try ids("iphone.nav.hidden")
        var renamed: [String: String] = [:]
        if let raw = storage.object(forKey: "iphone.nav.names") {
            guard let names = raw as? [String: String] else { throw HarborError(code: "navigation-store") }
            renamed = names
        }
        let result = NativeNavigationLayout(order: order, hidden: Set(hidden), renamed: renamed)
        guard result.valid else { throw HarborError(code: "navigation-store") }
        return result
    }
}
