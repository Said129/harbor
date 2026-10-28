import Foundation
import Observation

protocol CustomListPersistence: Sendable {
    func read(owner: String) async throws -> JSONValue?
    func write(_ value: JSONValue, owner: String) async throws
}

actor CustomListDisk: CustomListPersistence {
    static let shared = CustomListDisk()
    private let root: URL
    init(root: URL? = nil) { self.root = root ?? URL.applicationSupportDirectory.appendingPathComponent("HarborCustomLists", isDirectory: true) }
    private func file(_ owner: String) -> URL { root.appendingPathComponent(EBookShelf.hash(owner) + ".json") }
    func read(owner: String) throws -> JSONValue? {
        let path = file(owner); guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        guard (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1_024 * 1_024 else { throw HarborError(code: "custom-lists-store") }
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: path))
        guard case .array = value else { throw HarborError(code: "custom-lists-store") }
        return value
    }
    func write(_ value: JSONValue, owner: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard case .array = value, data.count <= 16 * 1_024 * 1_024 else { throw HarborError(code: "custom-lists-store") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: file(owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor @Observable final class CustomListStore {
    private struct Scope: Hashable { let owner: String; let inheritedOwner: String? }
    private static var stores: [Scope: CustomListStore] = [:]
    static func forOwner(_ owner: String, inheritedOwner: String? = nil) -> CustomListStore {
        let shared = inheritedOwner.flatMap { $0 == owner ? nil : $0 }, key = Scope(owner: owner, inheritedOwner: shared)
        if let store = stores[key] { return store }
        let inherited = shared.map { forOwner($0) }, store = CustomListStore(owner: owner, inherited: inherited)
        stores[key] = store; Task { await store.load() }; return store
    }
    let owner: String
    let inherited: CustomListStore?
    private let disk: any CustomListPersistence
    private let now: () -> Int64
    private var value: CustomListsDocument?
    @ObservationIgnored private var loading: Task<Void, Never>?
    private(set) var ready = false
    private(set) var busy = false
    private(set) var unsaved = false
    private(set) var error: String?
    var lists: [CustomList] { document.sorted }
    private var document: CustomListsDocument { value ?? inherited?.document ?? .init() }
    init(owner: String, inherited: CustomListStore? = nil, disk: any CustomListPersistence = CustomListDisk.shared,
         now: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded(.towardZero)) }) {
        self.owner = owner; self.inherited = inherited; self.disk = disk; self.now = now
    }
    func load(force: Bool = false) async {
        if let loading { await loading.value; return }
        guard !busy, !unsaved, force || !ready else { return }
        busy = true
        let task = Task { await self.read() }; loading = task; await task.value; loading = nil; busy = false
    }
    private func read() async {
        do {
            let raw = try await disk.read(owner: owner)
            if raw == nil { await inherited?.load() }
            guard raw != nil || inherited?.ready != false else { throw HarborError(code: "custom-lists-store") }
            value = await Task.detached { raw.map(CustomListsDocument.init) }.value
            ready = true; error = nil
        } catch { error = "Could not read your lists. Your saved data is preserved." }
    }
    @discardableResult func apply(_ action: CustomListsDocument.Action) async -> CustomListsDocument.Result? {
        guard ready, !busy else { return nil }
        busy = true; defer { busy = false }
        let current = document, timestamp = now()
        let (next, result) = await Task.detached {
            var next = current; let result = next.apply(action, at: timestamp); return (next, result)
        }.value
        guard result.changed else { return result }
        do {
            try await disk.write(next.raw, owner: owner)
            value = next; unsaved = false; error = nil
        } catch {
            // Same visible fallback as Desktop's exhausted localStorage: keep
            // the edit in this owner's memory and make retry explicit.
            value = next; unsaved = true; error = "Your lists are kept in memory. Save them before closing the app."
        }
        return result
    }
    func save() async {
        guard ready, unsaved, !busy else { return }
        busy = true; defer { busy = false }
        do { try await disk.write(document.raw, owner: owner); unsaved = false; error = nil }
        catch { error = "Your lists are kept in memory. Save them before closing the app." }
    }
    func contains(_ item: String, list: String) -> Bool { lists.first { $0.id == list }?.items.contains { $0.id == item } ?? false }
}
