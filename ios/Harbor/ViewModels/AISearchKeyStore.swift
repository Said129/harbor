import Foundation
import Observation

/// The OpenRouter, Groq and Jina keys of one profile, kept in the Keychain (Desktop's `aiSearchKey`, `aiGroqKey` and `jinaKey`).
@MainActor @Observable final class AISearchKeyStore {
    enum Key: String, CaseIterable, Sendable { case openRouter, groq, jina }

    private static var stores: [String: AISearchKeyStore] = [:]
    static func forOwner(_ owner: String) -> AISearchKeyStore {
        if let saved = stores[owner] { return saved }
        let store = AISearchKeyStore(owner: owner); stores[owner] = store; return store
    }

    let owner: String
    private(set) var keys: [String: String] = [:]
    private(set) var ready = false

    init(owner: String) { self.owner = owner }

    private func storageKey() throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "ai-search-keys-profile") }
        return "native-ai-search-keys-v1-" + EBookShelf.hash(owner)
    }

    func load() throws {
        keys = try KeychainStore().read(storageKey(), as: [String: String].self) ?? [:]
        ready = true
    }

    func key(_ key: Key) -> String { keys[key.rawValue] ?? "" }

    /// An empty value removes the key. Keys are short single-line tokens.
    func set(_ value: String, for key: Key) throws {
        guard ready else { throw HarborError(code: "ai-search-keys-unavailable") }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 256, !trimmed.contains(where: \.isNewline) else { throw HarborError(code: "ai-search-key-invalid") }
        var next = keys
        next[key.rawValue] = trimmed.isEmpty ? nil : trimmed
        // Commit before announcing: a failed Keychain write leaves the last saved keys in place.
        let storage = try storageKey()
        if next.isEmpty { try KeychainStore().remove(storage) } else { try KeychainStore().write(next, key: storage) }
        keys = next
    }
}

/// Desktop's AI search choices that are not secrets: `aiSearchProvider`, `aiSearchModel` and `aiWebSearch`. Kept on this device in UserDefaults.
struct AISearchPreferences: Equatable, Sendable {
    /// Desktop defaults: provider "openrouter" (`defaults.ts`), model "" (the default model), web context off.
    static let serviceKey = "harbor.aiSearch.service"
    static let modelKey = "harbor.aiSearch.model"
    static let webSearchKey = "harbor.aiSearch.webSearch"

    var service: AISearchService = .openrouter
    var model = ""
    var webSearch = false

    static func load(_ defaults: UserDefaults = .standard) -> AISearchPreferences {
        var value = AISearchPreferences()
        if let raw = defaults.string(forKey: serviceKey), let saved = AISearchService(rawValue: raw) { value.service = saved }
        value.model = defaults.string(forKey: modelKey) ?? ""
        value.webSearch = defaults.bool(forKey: webSearchKey)
        return value
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(service.rawValue, forKey: Self.serviceKey)
        defaults.set(model, forKey: Self.modelKey)
        defaults.set(webSearch, forKey: Self.webSearchKey)
    }

    var resolvedModel: String { AISearchCatalog.resolvedModel(model) }

    /// Desktop's `aiKey`: the key of the chosen service.
    @MainActor func activeKey(_ keys: AISearchKeyStore) -> String {
        keys.key(service == .groq ? .groq : .openRouter)
    }
}
