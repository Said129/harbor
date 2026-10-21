import CryptoKit
import Foundation

private struct ReadingAdapterTransport: HarborPluginHostTransport {
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        throw HarborPluginRuntimeError("reading-adapter-network-denied")
    }
}

/// Only trusted, pinned normalization/composition code runs here. Installed code is data.
@MainActor final class HarborReadingPluginProgram {
    private let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private var runtime: HarborPluginRuntime?
    private var disposed = false
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope; self.currentScope = currentScope
    }
    func apply(_ operation: String, raw: JSONValue, extra: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard !disposed, scope == currentScope() else { throw CancellationError() }
        try Task.checkCancellation()
        if runtime?.isDisposed != false {
            struct Asset: Decodable {
                struct Program: Decodable { let source: String; let sha256: String }
                let schema: Int; let reference: String; let inputs: [String: String]; let program: Program
            }
            guard let url = Bundle.main.url(forResource: "ReadingPluginAssets", withExtension: "json") else { throw HarborPluginRuntimeError("reading-adapter-assets") }
            let data = try Data(contentsOf: url)
            guard data.count <= 1024 * 1024 else { throw HarborPluginRuntimeError("reading-adapter-assets") }
            let asset = try JSONDecoder().decode(Asset.self, from: data)
            let hash = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
            guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987", asset.inputs.count == 10,
                  hash == asset.program.sha256, hash == "4db58f72e6cb2d3675f98fd2e4b88381b6a6fc19736eaefeec9711d3e899fb53" else { throw HarborPluginRuntimeError("reading-adapter-assets") }
            runtime = HarborPluginRuntime(id: "trusted-reading-adapters", name: "Harbor", source: asset.program.source, format: .raw,
                scope: scope, currentScope: currentScope, transport: ReadingAdapterTransport())
        }
        var input = extra; input["operation"] = .string(operation); input["raw"] = raw
        guard let runtime else { throw HarborPluginRuntimeError("reading-adapter-assets") }
        let value = try await runtime.call("content", arguments: [.object(input)], timeout: 10)
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { throw CancellationError() }
        return value
    }
    func dispose() { disposed = true; runtime?.dispose(); runtime = nil }
}
