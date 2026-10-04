import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    let service = HarborService()
    let resume = ResumeStore()
    private let keychain = KeychainStore()
    private var started = false
    private(set) var storageReady = false
    private(set) var addons: [Addon] = []
    private(set) var rows: [CatalogRow] = []
    var loading = false
    var error: String?
    var warnings: [String] = []
    var progressError: String?

    func start() async {
        guard !started else { return }
        started = true
        loading = true
        Diagnostics.shared.record(.startup)
        await reloadProgress()
        do {
            // A Keychain error is not an empty store and must never overwrite it.
            if let saved = try keychain.read("addons.v1", as: [Addon].self) { addons = saved }
            else {
                let fallback = try await service.install(HarborService.cinemetaManifest)
                try keychain.write([fallback], key: "addons.v1")
                addons = [fallback]
            }
            storageReady = true
            Diagnostics.shared.record(.coreReady)
            await loadHome()
        } catch is CancellationError { started = false }
        catch { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }
        loading = false
    }

    func retryStartup() async { started = false; error = nil; await start() }

    func reloadProgress() async {
        do { try await resume.load(); progressError = nil }
        catch { progressError = safeMessage(error); Diagnostics.shared.recordFailure(error) }
    }

    func loadHome() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            (rows, warnings) = try await service.catalogs(addons)
            Diagnostics.shared.record(.catalogsLoaded, count: rows.count)
            if rows.isEmpty && !warnings.isEmpty { error = "No se pudo cargar ningún catálogo. \(warnings.joined(separator: ", "))" }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }
    }

    func install(_ url: String) async throws {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        let addon = try await service.install(url)
        let next = addons.filter { $0.transportUrl != addon.transportUrl } + [addon]
        try persist(next)
        Diagnostics.shared.record(.addonInstalled, count: addons.count)
        await loadHome()
    }

    func setEnabled(_ addon: Addon, _ enabled: Bool) throws {
        var next = addons
        guard let index = next.firstIndex(where: { $0.id == addon.id }) else { return }
        next[index].enabled = enabled
        try persist(next)
    }

    func remove(_ offsets: IndexSet) throws {
        try persist(addons.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
    }

    func move(_ offsets: IndexSet, to destination: Int) throws {
        let moving = addons.enumerated().filter { offsets.contains($0.offset) }.map(\.element)
        var remaining = addons.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertion, remaining.count)))
        try persist(remaining)
    }

    private func persist(_ next: [Addon]) throws {
        guard storageReady else { throw HarborError(code: "storage-unavailable") }
        try keychain.write(next, key: "addons.v1")
        addons = next
    }
}

func safeMessage(_ error: Error) -> String {
    if let error = error as? HarborError { return error.localizedDescription }
    return "Harbor no pudo completar la operación."
}
