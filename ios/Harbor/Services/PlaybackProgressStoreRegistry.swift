import Foundation

/// Reuse the same file actor while any player still owns it. A closing player
/// and a newly selected profile must not cache competing copies of one file.
@MainActor final class PlaybackProgressStoreRegistry {
    private final class WeakStore { weak var value: ResumeStore?; init(_ value: ResumeStore) { self.value = value } }
    private var stores: [String: WeakStore] = [:]
    private let make: @MainActor (String) -> ResumeStore
    init(make: @escaping @MainActor (String) -> ResumeStore = { ResumeStore(owner: $0) }) { self.make = make }
    func store(owner: String) -> ResumeStore {
        if let existing = stores[owner]?.value { return existing }
        if stores.count >= 64 { stores = stores.filter { $0.value.value != nil } }
        let value = make(owner); stores[owner] = WeakStore(value); return value
    }
}
