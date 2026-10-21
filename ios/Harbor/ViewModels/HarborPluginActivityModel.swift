import Foundation
import Observation

struct HarborPluginCheckResult: Equatable, Sendable {
    let count: Int
    let milliseconds: Int
    let requests: Int
}

/// Uses the same real-title check as Desktop's streams kind adapter; no playback or installation mutation.
@MainActor @Observable final class HarborPluginActivityModel {
    let id: String
    let manager: HarborStreamPluginManager
    let runtime: HarborStreamPluginPool
    private let options: @MainActor () -> HarborPluginStreamOptions
    private var generation = UUID()
    private(set) var checking = false
    private(set) var result: HarborPluginCheckResult?
    private(set) var error: String?

    init(id: String, manager: HarborStreamPluginManager, runtime: HarborStreamPluginPool,
        options: @escaping @MainActor () -> HarborPluginStreamOptions = { .current() }) {
        self.id = id; self.manager = manager; self.runtime = runtime; self.options = options
    }
    var plugin: HarborInstalledStreamPlugin? { manager.document.plugins.first { $0.id == id } }
    var health: HarborPluginHealth? { runtime.health[id] }
    var logs: [HarborPluginLogLine] { runtime.logs[id] ?? [] }
    var canCheck: Bool {
        guard manager.ready, options().enabled, let plugin else { return false }
        return plugin.enabled && !plugin.repoDisabled && plugin.listed && plugin.entry.format != .androidExtension
            && !(plugin.entry.nsfw && options().hideAdult)
    }
    static func sampleRequest(title: String?) -> JSONValue {
        .object(["type": .string("movie"), "id": .string("tt0137523"), "ids": .array([.string("tt0137523")]),
            "imdbId": .string("tt0137523"), "tmdb": .object(["id": .integer(550), "kind": .string("movie")]),
            "title": .string(title ?? "Fight Club"), "year": .integer(1999), "season": .null, "episode": .null,
            "absoluteEpisode": .null, "settings": .object([:])])
    }
    func check(timeout: TimeInterval = 30) async {
        guard canCheck, !checking else { return }
        let ticket = generation, started = ProcessInfo.processInfo.systemUptime
        checking = true; result = nil; error = nil
        defer { if generation == ticket { checking = false } }
        do {
            let budget = timeout.isFinite ? min(120, max(8, timeout)) : 30
            let raw = try await runtime.run(id, request: Self.sampleRequest(title: health?.title), timeout: budget, checking: true)
            try Task.checkCancellation()
            guard generation == ticket, manager.ready, plugin != nil else { return }
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            let count: Int
            if case .array(let rows) = raw { count = rows.count } else { count = raw["streams"].array.count }
            result = .init(count: count, milliseconds: Int(min(Double(Int32.max), max(0, elapsed))), requests: health?.requests ?? 0)
        } catch is CancellationError { return }
        catch {
            guard generation == ticket, manager.ready, plugin != nil, !Task.isCancelled else { return }
            let code = (error as? HarborPluginRuntimeError)?.code ?? (error as? HarborPluginRepositoryError)?.code ?? "plugin-operation"
            self.error = DesktopInterfaceText.value("Stopped with: {error}", variables: ["error": code])
        }
    }
    func clear() { generation = UUID(); checking = false; result = nil; error = nil }
}
