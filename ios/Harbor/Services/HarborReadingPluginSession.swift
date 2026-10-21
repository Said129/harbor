import Foundation
import Observation

@MainActor @Observable final class HarborReadingPluginSession {
    private var store: HarborReadingPluginStore?
    private var loading: Task<HarborReadingPluginManager, Error>?
    private var generation = UUID()
    private(set) var manager: HarborReadingPluginManager?
    func open(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) async throws -> HarborReadingPluginManager {
        try Task.checkCancellation()
        guard scope == currentScope() else { throw CancellationError() }
        if let manager, manager.scope == scope, manager.ready { return manager }
        if let loading, manager?.scope == scope { let value = try await loading.value; try Task.checkCancellation(); return value }
        invalidate(); let ticket = generation
        let catalog: HarborReadingPluginStore
        if let store { catalog = store } else { catalog = try HarborReadingPluginStore(); store = catalog }
        let next = HarborReadingPluginManager(scope: scope, currentScope: currentScope, store: catalog); manager = next
        let task = Task {
            do {
                try await next.load(); try Task.checkCancellation()
                guard self.generation == ticket, scope == currentScope() else { throw CancellationError() }
                return next
            } catch { next.dispose(); if self.generation == ticket { self.manager = nil }; throw error }
        }
        loading = task; defer { if generation == ticket { loading = nil } }
        let value = try await task.value; try Task.checkCancellation(); return value
    }
    func invalidate() { generation = UUID(); loading?.cancel(); loading = nil; manager?.dispose(); manager = nil }
}
extension AppModel {
    func openReadingPlugins() async throws -> HarborReadingPluginManager {
        guard let scope = pluginExecutionScope else { throw CancellationError() }
        return try await readingPlugins.open(scope: scope, currentScope: { [weak self] in
            self?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation)
        })
    }
}
