import CryptoKit
import Foundation
import WebKit

struct PluginExecutionScope: Equatable, Sendable {
    let owner: String
    let activation: UUID
}

enum HarborPluginCodeFormat: String, Sendable { case raw, harbor, providerScript = "provider-script" }
enum HarborPluginBridgeKind: String, Sendable { case http, grpc }

/// Implemented by an owner-scoped host; the worker never receives account stores or native objects.
protocol HarborPluginHostTransport: Sendable {
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue
}

private actor PluginBridgeGate {
    static let shared = PluginBridgeGate()
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private func acquire() async {
        if active < 16 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    private func release() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
    func run(_ operation: @Sendable () async throws -> JSONValue) async throws -> JSONValue {
        await acquire(); defer { release() }
        try Task.checkCancellation(); return try await operation()
    }
}

struct HarborPluginRuntimeError: Error, Sendable {
    let code: String
    let detail: String
    init(_ code: String, _ detail: String = "") { self.code = code; self.detail = detail }
}

private struct PluginRuntimeAssets: Decodable {
    struct Program: Decodable { let source: String; let sha256: String }
    let schema: Int
    let reference: String
    let programs: [String: Program]
    static func read() throws -> Self {
        guard let url = Bundle.main.url(forResource: "PluginRuntimeAssets", withExtension: "json") else { throw HarborPluginRuntimeError("plugin-assets") }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw HarborPluginRuntimeError("plugin-assets") }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schema == 1, result.reference == "0834340cec5531650bfe78cd628628702e636987",
              Set(result.programs.keys) == ["sandbox", "parser", "composer"] else { throw HarborPluginRuntimeError("plugin-assets") }
        for program in result.programs.values {
            let hash = SHA256.hash(data: Data(program.source.utf8)).map { String(format: "%02x", $0) }.joined()
            guard hash == program.sha256 else { throw HarborPluginRuntimeError("plugin-assets") }
        }
        return result
    }
}

@MainActor private final class PluginMessageHandler: NSObject, WKScriptMessageHandler {
    weak var runtime: HarborPluginRuntime?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? String else { return }
        runtime?.receive(value)
    }
}

/// The reference worker and host parser run in WebKit's isolated content process.
/// This foundation is not an installed-plugin manager or a complete Plugins room.
@MainActor final class HarborPluginRuntime: NSObject, WKNavigationDelegate {
    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, Error>
        let deadline: Task<Void, Never>
    }
    private static var cachedAssets: PluginRuntimeAssets?
    private let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let transport: any HarborPluginHostTransport
    private let source: String
    private let configuration: JSONValue
    private let format: HarborPluginCodeFormat
    private let pluginID: String
    private let name: String
    private let instance = UUID().uuidString
    private let messageHandler = PluginMessageHandler()
    private var web: WKWebView?
    private var initialization: Task<JSONValue, Error>?
    private var pending: [String: Pending] = [:]
    private var bridges: [String: Task<Void, Never>] = [:]
    private var queuedBridges: [(String, HarborPluginBridgeKind, JSONValue)] = []
    private var disposed = false
    private(set) var logs: [String] = []

    init(id: String, name: String, source: String, format: HarborPluginCodeFormat, configuration: JSONValue = .object([:]),
        scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope, transport: any HarborPluginHostTransport) {
        self.pluginID = id; self.name = name; self.source = source; self.format = format; self.configuration = configuration
        self.scope = scope; self.currentScope = currentScope; self.transport = transport
        super.init(); messageHandler.runtime = self
    }

    func metadata() async throws -> JSONValue {
        try validate()
        let task: Task<JSONValue, Error>
        if let initialization { task = initialization }
        else { task = Task { try await self.initialize() }; initialization = task }
        let result = try await task.value
        try validate(); return result
    }

    func call(_ method: String, arguments: [JSONValue] = [], timeout: TimeInterval = 20) async throws -> JSONValue {
        try Task.checkCancellation()
        _ = try await metadata()
        try validate(); try Task.checkCancellation()
        let methods: Set<String> = ["popular", "search", "detail", "chapters", "content", "pageUrls", "tags", "streams", "settings"]
        guard methods.contains(method) else { throw HarborPluginRuntimeError("plugin-method") }
        let id = UUID().uuidString
        let deadline = timeout.isFinite && timeout > 0 ? max(0.05, min(120, timeout)) : 20
        return try await request(id: id, timeout: deadline) {
            self.send("call", .object(["id": .string(id), "method": .string(method), "args": .array(arguments)]))
        }
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        initialization?.cancel(); initialization = nil
        bridges.values.forEach { $0.cancel() }; bridges = [:]; queuedBridges = []
        if let retiring = web {
            retiring.evaluateJavaScript("globalThis.harborPluginHost?.dispose()") { _, _ in retiring.stopLoading() }
        }
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "harborPlugin")
        web?.stopLoading(); web?.navigationDelegate = nil; web = nil
        for id in Array(pending.keys) { finish(id, result: .failure(HarborPluginRuntimeError("plugin-disposed"))) }
        logs = []
    }

    private func validate() throws {
        guard !disposed else { throw HarborPluginRuntimeError("plugin-disposed") }
        guard scope == currentScope() else { dispose(); throw HarborPluginRuntimeError("plugin-scope") }
    }

    private func initialize() async throws -> JSONValue {
        try validate(); try Task.checkCancellation()
        guard source.utf8.count <= 8 * 1024 * 1024, case .object = configuration,
              let hostURL = Bundle.main.url(forResource: "PluginRuntimeHost", withExtension: "js") else { throw HarborPluginRuntimeError("plugin-source") }
        let assets: PluginRuntimeAssets
        if let cached = Self.cachedAssets { assets = cached } else { assets = try PluginRuntimeAssets.read(); Self.cachedAssets = assets }
        guard let sandbox = assets.programs["sandbox"], let parser = assets.programs["parser"], let composer = assets.programs["composer"] else { throw HarborPluginRuntimeError("plugin-assets") }
        let host = try String(contentsOf: hostURL, encoding: .utf8)
        let sandboxJSON = try json(.string(sandbox.source)), instanceJSON = try json(.string(instance))
        let script = host + "\ninstallHarborPluginHost(" + sandboxJSON + "," + parser.source + "," + composer.source + "," + instanceJSON + ");"
        let preferences = WKWebViewConfiguration()
        preferences.websiteDataStore = .nonPersistent()
        preferences.preferences.javaScriptCanOpenWindowsAutomatically = false
        preferences.userContentController.add(messageHandler, name: "harborPlugin")
        preferences.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: preferences); view.navigationDelegate = self; web = view
        return try await request(id: "ready", timeout: 10) {
            view.loadHTMLString("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-eval' blob:; worker-src blob:; connect-src 'none'; img-src 'none'; style-src 'none'\"><title>Harbor plugin worker</title>", baseURL: URL(string: "https://harbor-plugin.invalid/"))
        }
    }

    private func request(id: String, timeout: TimeInterval, start: () -> Void) async throws -> JSONValue {
        try validate(); try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    guard let self, self.pending[id] != nil else { return }
                    self.finish(id, result: .failure(HarborPluginRuntimeError("plugin-timeout"))); self.dispose()
                }
                pending[id] = Pending(continuation: continuation, deadline: deadline)
                start()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
    }

    private func cancel(_ id: String) {
        guard pending[id] != nil else { return }
        send("cancel", .string(id)); finish(id, result: .failure(CancellationError()))
        if id == "ready" { dispose() }
    }

    private func finish(_ id: String, result: Result<JSONValue, Error>) {
        guard let value = pending.removeValue(forKey: id) else { return }
        value.deadline.cancel(); value.continuation.resume(with: result)
    }

    private func json(_ value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw HarborPluginRuntimeError("plugin-message") }
        return text
    }

    private func send(_ method: String, _ value: JSONValue) {
        do {
            try validate()
            let encoded = try json(value)
            web?.evaluateJavaScript("globalThis.harborPluginHost." + method + "(" + encoded + ")") { [weak self] _, error in
                guard error != nil else { return }
                self?.fail(HarborPluginRuntimeError("plugin-bridge"))
            }
        } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        for id in Array(pending.keys) { finish(id, result: .failure(error)) }
        dispose()
    }

    fileprivate func receive(_ text: String) {
        guard text.utf8.count <= 8 * 1024 * 1024, let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(JSONValue.self, from: data), message["instance"].string == instance else { return }
        do { try validate() } catch { return }
        switch message["type"].string {
        case "hostReady":
            send("initialize", .object(["source": .string(source), "format": .string(format.rawValue), "configuration": configuration,
                "meta": .object(["id": .string(pluginID), "name": .string(name), "settings": configuration])]))
        case "ready": finish("ready", result: .success(message["meta"]))
        case "initError", "fatal": fail(HarborPluginRuntimeError("plugin-runtime", message["error"].string ?? ""))
        case "result": if let id = message["id"].string { finish(id, result: .success(message["value"])) }
        case "error": if let id = message["id"].string { finish(id, result: .failure(HarborPluginRuntimeError("plugin-call", message["error"].string ?? ""))) }
        case "cancelled": if let id = message["id"].string { finish(id, result: .failure(CancellationError())) }
        case "log":
            logs.append(String(message["args"].array.compactMap(\.string).joined(separator: " ").prefix(600)))
            if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        case "http", "grpc":
            guard let id = message["id"].string, bridges[id] == nil, !queuedBridges.contains(where: { $0.0 == id }),
                  let kind = message["type"].string.flatMap(HarborPluginBridgeKind.init(rawValue:)) else { return }
            queuedBridges.append((id, kind, message["payload"])); drainBridges()
        default: break
        }
    }

    private func drainBridges() {
        guard !disposed, scope == currentScope() else { dispose(); return }
        while bridges.count < 6, !queuedBridges.isEmpty {
            let (id, kind, payload) = queuedBridges.removeFirst(), transport = self.transport
            bridges[id] = Task { [weak self] in
                defer { self?.bridges[id] = nil; self?.drainBridges() }
                do {
                    let value = try await PluginBridgeGate.shared.run { try await transport.perform(kind, payload: payload) }
                    try Task.checkCancellation(); try self?.validate()
                    self?.send("bridgeResult", .object(["id": .string(id), "ok": .bool(true), "value": value]))
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.send("bridgeResult", .object(["id": .string(id), "ok": .bool(false), "error": .string("plugin host request failed")]))
                }
            }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(HarborPluginRuntimeError("plugin-process")) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(HarborPluginRuntimeError("plugin-host")) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.navigationType == .other && (action.request.url?.scheme == "about" || action.request.url?.host == "harbor-plugin.invalid") ? .allow : .cancel
    }
}
