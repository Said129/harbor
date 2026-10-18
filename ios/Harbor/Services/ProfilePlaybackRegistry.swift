import Foundation
import Observation

@MainActor protocol ProfilePlaybackControlling: AnyObject {
    func close()
}

/// A detached PiP surface still belongs to the profile that opened it. Weak
/// registrations stop it before another profile's accounts or settings are bound.
@MainActor @Observable final class ProfilePlaybackRegistry {
    private struct Entry {
        weak var controller: (any ProfilePlaybackControlling)?
    }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private(set) var generation = UUID()
    var hasActivePlayback: Bool { entries.values.contains { $0.controller != nil } }
    @discardableResult func register(_ controller: any ProfilePlaybackControlling, generation: UUID) -> Bool {
        guard generation == self.generation else { controller.close(); return false }
        entries = entries.filter { $0.value.controller != nil }
        entries[ObjectIdentifier(controller)] = Entry(controller: controller)
        return true
    }
    func remove(_ controller: any ProfilePlaybackControlling) { entries.removeValue(forKey: ObjectIdentifier(controller)) }
    func stopForProfileChange() {
        let controllers = entries.values.compactMap(\.controller)
        entries = [:]; generation = UUID()
        for controller in controllers { controller.close() }
    }
}
