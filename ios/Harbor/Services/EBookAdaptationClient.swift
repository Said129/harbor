import CryptoKit
import Foundation

private struct EBookAdaptationTransport: HarborPluginHostTransport {
    let network: any HarborNativeNetworkCalling
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        let hosts: Set<String> = ["graphql.anilist.co", "kitsu.io", "api.tenrai.org", "jikanfortheweebs.midnightignite.me"]
        guard kind == .http, let value = payload["url"].string, let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(), hosts.contains(host) else { throw HarborPluginRuntimeError("reading-adaptation-host") }
        return try await HarborNativePluginTransport(policy: .init(sameSiteHeaders: false, publicOnly: true, openHeaders: false, baseURL: nil, blockedHosts: []), network: network).perform(kind, payload: payload)
    }
}

@MainActor final class EBookAdaptationClient {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int; let reference: String; let inputs: [String: String]; let program: Program
    }
    private let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let network: any HarborNativeNetworkCalling
    private var runtime: HarborPluginRuntime?
    private var disposed = false
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope, network: any HarborNativeNetworkCalling = HarborNativeNetwork()) {
        self.scope = scope; self.currentScope = currentScope; self.network = network
    }
    func query(_ operation: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { dispose(); throw CancellationError() }
        if runtime == nil {
            guard let url = Bundle.main.url(forResource: "EBookAdaptationAssets", withExtension: "json") else { throw HarborPluginRuntimeError("reading-adaptation-assets") }
            let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
            let hash = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
            guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987", asset.inputs.count == 7,
                  hash == asset.program.sha256, hash == "cef50f38205ab590978a854ebf5f1d6bb7315ea2302b26ffda26be2e9bc1f75c" else { throw HarborPluginRuntimeError("reading-adaptation-assets") }
            runtime = HarborPluginRuntime(id: "trusted-book-adaptations", name: "Harbor Adaptations", source: asset.program.source, format: .raw,
                scope: scope, currentScope: currentScope, transport: EBookAdaptationTransport(network: network))
        }
        guard let runtime else { throw CancellationError() }
        var input = arguments; input["operation"] = .string(operation)
        let result = try await runtime.call("content", arguments: [.object(input)], timeout: 25)
        try Task.checkCancellation(); guard !disposed, scope == currentScope() else { dispose(); throw CancellationError() }
        return result
    }
    func dispose() { guard !disposed else { return }; disposed = true; runtime?.dispose(); runtime = nil }
    static func animeMedia(_ value: JSONValue) -> Media? {
        guard let id = value["id"].string, id.range(of: #"^(?:anilist|kitsu|mal):[1-9][0-9]*$"#, options: .regularExpression) != nil else { return nil }
        return Media.parse(value, kind: "anime")
    }
    static func directAnime(_ item: JSONValue) -> Media? {
        guard item["kind"].string == "anime", let id = item["anilistId"].integer, id > 0, let title = item["title"].string else { return nil }
        var media = Media(id: "anilist:" + String(id), type: "anime", name: title)
        media.poster = item["poster"].string; media.description = item["description"].string; media.releaseInfo = item["year"].integer.map(String.init)
        return media
    }
}
