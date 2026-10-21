import CryptoKit
import Foundation
import JavaScriptCore

struct HarborPluginSettingsField: Codable, Equatable, Sendable {
    struct Option: Codable, Equatable, Sendable { let label: String; let value: String }
    let type: String
    let label: String
    let key: String?
    let placeholder: String?
    let description: String?
    let isPassword: Bool?
    let defaultValue: JSONValue?
    let options: [Option]?
}

/// Executes only the pinned, pure Desktop normalizer, with JSON as its sole input.
/// No installed plugin code or native object is evaluated in this context.
enum HarborPluginSettings {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int
        let reference: String
        let inputs: [String: String]
        let program: Program
    }
    static func fields(_ raw: JSONValue) async throws -> [HarborPluginSettingsField] {
        try Task.checkCancellation()
        let fields = try await Task.detached(priority: .utility) { try decode(raw) }.value
        try Task.checkCancellation()
        return fields
    }
    private static func decode(_ raw: JSONValue) throws -> [HarborPluginSettingsField] {
        guard let url = Bundle.main.url(forResource: "PluginSettingsNormalizer", withExtension: "json") else { throw HarborPluginRepositoryError("plugin-settings-assets") }
        let data = try Data(contentsOf: url)
        guard data.count <= 1024 * 1024 else { throw HarborPluginRepositoryError("plugin-settings-assets") }
        let asset = try JSONDecoder().decode(Asset.self, from: data)
        let hash = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987",
              asset.inputs == ["src/lib/streams/plugins/runtime.ts":"9b41fb8a2c012b136efd9bef927f6e9626f4f8f2371b80999a087c71dae7bdf2"],
              hash == asset.program.sha256 else { throw HarborPluginRepositoryError("plugin-settings-assets") }
        let input = try JSONEncoder().encode(raw)
        guard input.count <= 64 * 1024 * 1024, let text = String(data: input, encoding: .utf8), let context = JSContext() else { throw HarborPluginRepositoryError("plugin-settings-normalization") }
        context.evaluateScript(asset.program.source)
        guard context.exception == nil, let function = context.objectForKeyedSubscript("harborNormalizePluginFields"), !function.isUndefined,
              let output = function.call(withArguments: [text]), context.exception == nil, let json = output.toString(),
              let result = json.data(using: .utf8), result.count <= 64 * 1024 * 1024 else { throw HarborPluginRepositoryError("plugin-settings-normalization") }
        return try JSONDecoder().decode([HarborPluginSettingsField].self, from: result)
    }
}

struct HarborPluginSettingsTransport: HarborPluginHostTransport {
    let wrapped: any HarborPluginHostTransport
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        // The reference denyHttp option affects HTTP; onGrpc retains its normal host path.
        guard kind != .http else { throw HarborError(code: "network not available here") }
        return try await wrapped.perform(kind, payload: payload)
    }
}
