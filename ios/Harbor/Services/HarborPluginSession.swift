import Foundation
import Observation

/// Desktop's plugin stores are local to the installation, not profile-sync documents.
/// Each activation still gets a new manager so a retired profile cannot publish late work.
@MainActor @Observable final class HarborPluginSession {
    private let namespace: String
    private let file: URL?
    private var store: HarborPluginCatalogStore?
    private var loading: (scope: PluginExecutionScope, task: Task<HarborStreamPluginManager, Error>)?
    private var generation = UUID()
    private(set) var manager: HarborStreamPluginManager?

    init(namespace: String = "device-stream-plugins-v1", file: URL? = nil) {
        self.namespace = namespace; self.file = file
    }
    func open(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) async throws -> HarborStreamPluginManager {
        guard scope == currentScope() else { throw HarborPluginRepositoryError("plugin-scope") }
        if let manager, manager.scope == scope, manager.ready { return manager }
        if let loading, loading.scope == scope { return try await loading.task.value }
        invalidate()
        let ticket = generation
        let catalog: HarborPluginCatalogStore
        if let store { catalog = store }
        else { catalog = try HarborPluginCatalogStore(namespace: namespace, file: file); store = catalog }
        let next = HarborStreamPluginManager(namespace: namespace, scope: scope, currentScope: currentScope, store: catalog)
        manager = next
        let task = Task {
            do {
                try await next.load(); try Task.checkCancellation()
                guard ticket == self.generation, scope == currentScope() else { throw HarborPluginRepositoryError("plugin-scope") }
                return next
            } catch {
                next.dispose()
                if ticket == self.generation { self.manager = nil }
                throw error
            }
        }
        loading = (scope, task)
        defer { if ticket == generation { loading = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    func invalidate() {
        generation = UUID(); loading?.task.cancel(); loading = nil
        manager?.dispose(); manager = nil
    }
}

extension AppModel {
    var pluginExecutionScope: PluginExecutionScope? {
        guard storageReady, profileContext.ready else { return nil }
        return .init(owner: personalOwner, activation: profileContext.activationID)
    }
}
