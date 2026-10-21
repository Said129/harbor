import Foundation
import Observation

struct HarborPluginHealth: Equatable, Sendable {
    var lastAt: Double?
    var milliseconds: Int?
    var count: Int?
    var error: String?
    var skipped: String?
    var title: String?
    var requests = 0
    var seenHosts: [String] = []
}
struct HarborPluginLogLine: Equatable, Sendable, Identifiable {
    let id = UUID()
    let at: Double
    let level: String
    let text: String
}

private struct HarborObservedPluginTransport: HarborPluginHostTransport {
    let wrapped: any HarborPluginHostTransport
    let observe: @MainActor @Sendable (String) -> Void
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        if kind == .http, let url = payload["url"].string { await observe(url) }
        return try await wrapped.perform(kind, payload: payload)
    }
}

/// Reuses actual isolated workers, with the reference's 5-minute / 4-idle-worker budget.
@MainActor @Observable final class HarborStreamPluginPool {
    private final class Slot {
        let identity = UUID()
        let runtime: HarborPluginRuntime
        let plugin: HarborInstalledStreamPlugin
        let configuration: [String: JSONValue]
        var lastUsed: TimeInterval
        var calls = 0
        var requests = 0
        init(runtime: HarborPluginRuntime, plugin: HarborInstalledStreamPlugin, configuration: [String: JSONValue], now: TimeInterval) {
            self.runtime = runtime; self.plugin = plugin; self.configuration = configuration; lastUsed = now
        }
    }
    private let manager: HarborStreamPluginManager
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let scope: PluginExecutionScope
    private let gate: HarborPluginCallGate
    private let now: @MainActor () -> TimeInterval
    private var slots: [String: Slot] = [:]
    private var operations: [UUID: (String, Task<JSONValue, Error>)] = [:]
    private var sweeper: Task<Void, Never>?
    private var disposed = false
    private(set) var health: [String: HarborPluginHealth] = [:]
    private(set) var logs: [String: [HarborPluginLogLine]] = [:]
    private(set) var persistenceFailed = false
    var residentWorkerCount: Int { slots.count }

    init(manager: HarborStreamPluginManager, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         gate: HarborPluginCallGate? = nil, now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.manager = manager; self.scope = manager.scope; self.currentScope = currentScope
        self.gate = gate ?? .shared; self.now = now
    }
    func run(_ id: String, request: JSONValue, timeout: TimeInterval = 30, checking: Bool = false) async throws -> JSONValue {
        try validate()
        let operationID = UUID()
        let task = Task { try await self.execute(id, request: request, timeout: timeout, checking: checking) }
        operations[operationID] = (id, task)
        defer { operations[operationID] = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    func invalidate(_ id: String) {
        for (_, value) in operations where value.0 == id { value.1.cancel() }
        slots.removeValue(forKey: id)?.runtime.dispose()
        stopEmptySweep()
    }
    func cancelCalls() {
        operations.values.forEach { $0.1.cancel() }
        // A master pause stops bridge work as well as its consumer. Resuming creates fresh
        // workers from the retained installation/configuration instead of reusing aborted code.
        slots.values.forEach { $0.runtime.dispose() }; slots = [:]
        sweeper?.cancel(); sweeper = nil
    }
    func recordSkip(_ id: String, title: String?, reason: String) {
        guard !disposed, manager.ready, scope == currentScope() else { return }
        var status = health[id] ?? .init()
        status.lastAt = Date().timeIntervalSince1970 * 1000; status.milliseconds = 0; status.count = 0
        status.error = nil; status.skipped = reason; status.title = title.map { String($0.prefix(500)) }; status.requests = 0
        health[id] = status
        log(id, level: "info", text: reason)
    }
    func dispose() {
        guard !disposed else { return }; disposed = true
        operations.values.forEach { $0.1.cancel() }; operations = [:]
        slots.values.forEach { $0.runtime.dispose() }; slots = [:]
        sweeper?.cancel(); sweeper = nil; health = [:]; logs = [:]
    }
    func sweep(trimIdle: Bool = false) {
        let time = now()
        for (id, slot) in slots where slot.calls == 0 && (trimIdle || time - slot.lastUsed > 300) {
            slots.removeValue(forKey: id)?.runtime.dispose()
        }
        let idle = slots.filter { $0.value.calls == 0 }.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (id, _) in idle.prefix(max(0, idle.count - 4)) { slots.removeValue(forKey: id)?.runtime.dispose() }
        stopEmptySweep()
    }
    private func stopEmptySweep() { if slots.isEmpty { sweeper?.cancel(); sweeper = nil } }
    private func startSweep() {
        guard sweeper == nil else { return }
        sweeper = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, !self.disposed else { return }
                self.sweep()
                if self.slots.isEmpty { return }
            }
        }
    }
    private func validate() throws {
        guard !disposed, manager.ready, scope == currentScope() else { throw CancellationError() }
        try Task.checkCancellation()
    }
    private func eligible(_ plugin: HarborInstalledStreamPlugin, checking: Bool) -> Bool {
        plugin.enabled && !plugin.repoDisabled && plugin.listed && plugin.entry.format != .androidExtension && (checking || !plugin.autoPaused)
    }
    private func slot(_ plugin: HarborInstalledStreamPlugin, configuration: [String: JSONValue]) throws -> Slot {
        if let old = slots[plugin.id], !old.runtime.isDisposed, old.plugin.hash == plugin.hash,
           old.plugin.entry.format == plugin.entry.format, old.plugin.entry.id == plugin.entry.id, old.configuration == configuration {
            old.lastUsed = now(); return old
        }
        slots.removeValue(forKey: plugin.id)?.runtime.dispose()
        let transport = HarborObservedPluginTransport(wrapped: try manager.runtimeTransport(), observe: { [weak self] url in self?.recordHTTP(plugin.id, url: url) })
        let runtime = HarborPluginRuntime(id: plugin.id, name: plugin.entry.name, source: plugin.code,
            format: plugin.entry.format == .providerScript ? .providerScript : .harbor, configuration: .object(configuration),
            scope: scope, currentScope: currentScope, transport: transport, sourceID: plugin.entry.id)
        let result = Slot(runtime: runtime, plugin: plugin, configuration: configuration, now: now())
        let secrets = plugin.secretKeys.compactMap { configuration[$0]?.string }.filter { !$0.isEmpty }
        runtime.redactLog = { text in secrets.reduce(text) { value, secret in value.replacingOccurrences(of: secret, with: "[redacted]") } }
        runtime.onLog = { [weak self, weak result] level, text in
            guard let self, let result, self.slots[plugin.id] === result, self.scope == self.currentScope(), !self.disposed else { return }
            self.log(plugin.id, level: level, text: text)
        }
        slots[plugin.id] = result; startSweep(); return result
    }
    private func execute(_ id: String, request: JSONValue, timeout: TimeInterval, checking: Bool) async throws -> JSONValue {
        try await gate.acquire(); defer { gate.release() }
        try validate()
        guard let plugin = manager.document.plugins.first(where: { $0.id == id }), eligible(plugin, checking: checking) else {
            throw HarborPluginRepositoryError("plugin-unavailable")
        }
        let configuration = try await manager.configuration(id)
        try validate()
        guard manager.document.plugins.first(where: { $0.id == id }) == plugin else { throw CancellationError() }
        let slot = try slot(plugin, configuration: configuration)
        slot.calls += 1
        let requestsBefore = slot.requests, started = now()
        defer { slot.calls -= 1; slot.lastUsed = now(); if !disposed { sweep() } }
        var arguments = request.objectValue; arguments["settings"] = .object(configuration)
        do {
            let value = try await slot.runtime.call("streams", arguments: [.object(arguments)], timeout: timeout)
            try validate()
            guard sameInstallation(plugin, checking: checking) else { throw CancellationError() }
            var status = health[id] ?? .init()
            status.lastAt = Date().timeIntervalSince1970 * 1000; status.milliseconds = elapsed(started)
            if case .array(let streams) = value { status.count = streams.count }
            else { status.count = value["streams"].array.count }
            status.error = nil; status.skipped = nil; status.title = request["title"].string
            status.requests = max(0, slot.requests - requestsBefore); health[id] = status
            log(id, level: "info", text: "\(status.count ?? 0) streams · \(status.milliseconds ?? 0) ms · \(status.requests) requests")
            do { try await manager.recordRuntimeOutcome(id, expected: plugin, succeeded: true) }
            catch { if !disposed, scope == currentScope(), !Task.isCancelled { persistenceFailed = true } }
            try validate()
            guard sameInstallation(plugin, checking: checking) else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, !disposed, scope == currentScope(), manager.ready, sameInstallation(plugin, checking: checking), !(error is CancellationError) else { throw CancellationError() }
            let code = (error as? HarborPluginRuntimeError)?.code ?? (error as? HarborPluginRepositoryError)?.code ?? "plugin-runtime"
            var status = health[id] ?? .init()
            status.lastAt = Date().timeIntervalSince1970 * 1000; status.milliseconds = elapsed(started)
            status.count = nil; status.error = code; status.skipped = nil; status.title = request["title"].string
            status.requests = max(0, slot.requests - requestsBefore); health[id] = status
            log(id, level: "error", text: code)
            do { try await manager.recordRuntimeOutcome(id, expected: plugin, succeeded: false) }
            catch { if !disposed, scope == currentScope(), !Task.isCancelled { persistenceFailed = true } }
            if manager.document.plugins.first(where: { $0.id == id })?.autoPaused == true { slots.removeValue(forKey: id)?.runtime.dispose() }
            try validate()
            throw error
        }
    }
    private func sameInstallation(_ plugin: HarborInstalledStreamPlugin, checking: Bool) -> Bool {
        guard let current = manager.document.plugins.first(where: { $0.id == plugin.id }) else { return false }
        return current.hash == plugin.hash && current.secretRevision == plugin.secretRevision && current.settingsValues == plugin.settingsValues
            && current.entry == plugin.entry && eligible(current, checking: checking)
    }
    private func elapsed(_ started: TimeInterval) -> Int {
        let milliseconds = (now() - started) * 1000
        guard milliseconds.isFinite else { return 0 }
        return Int(min(Double(Int32.max), max(0, milliseconds.rounded())))
    }
    private func recordHTTP(_ id: String, url: String) {
        guard !disposed, scope == currentScope(), let slot = slots[id], let host = URL(string: url)?.host?.lowercased() else { return }
        slot.requests += 1
        var status = health[id] ?? .init()
        if !status.seenHosts.contains(host) { status.seenHosts.append(host); status.seenHosts = Array(status.seenHosts.suffix(40)) }
        health[id] = status
    }
    private func log(_ id: String, level: String, text: String) {
        var lines = logs[id] ?? []
        lines.append(.init(at: Date().timeIntervalSince1970 * 1000, level: String(level.prefix(32)), text: String(text.prefix(600))))
        logs[id] = Array(lines.suffix(200))
    }
}
