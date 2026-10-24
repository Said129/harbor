import Foundation

@MainActor protocol MusicBillboardCalling: AnyObject {
    func ranking(_ chart: String, refresh: Bool) async throws -> MusicBillboardRanking
    func resolve(_ item: MusicCatalogItem, catalog: any MusicCatalogCalling) async throws -> MusicCatalogItem?
    func dispose()
}
struct MusicBillboardTransport: HarborPluginHostTransport {
    var network: any HarborNativeNetworkCalling = HarborNativeNetwork()
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        guard kind == .http, let raw = payload["url"].string, let url = URL(string: raw),
              url.scheme == "https", ["www.billboard.com", "api.deezer.com"].contains(url.host?.lowercased() ?? ""),
              url.port == nil, url.user == nil, url.password == nil, payload["opts"]["method"].string == "GET" else { throw HarborError(code: "music-billboard-host") }
        let policy = HarborPluginNetworkPolicy(sameSiteHeaders: false, publicOnly: true, openHeaders: false, baseURL: nil, blockedHosts: [])
        return try await HarborNativePluginTransport(policy: policy, network: network).perform(kind, payload: payload)
    }
}
@MainActor final class MusicBillboardClient: MusicBillboardCalling {
    let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let transport: any HarborPluginHostTransport
    private var runtime: HarborPluginRuntime?
    private var disposed = false
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         transport: any HarborPluginHostTransport = MusicBillboardTransport()) {
        self.scope = scope; self.currentScope = currentScope; self.transport = transport
    }
    func query<T: Decodable & Sendable>(_ operation: String, arguments: [String: JSONValue] = [:], as type: T.Type) async throws -> T {
        try validate()
        if runtime == nil {
            let asset = try MusicBillboardAsset.read()
            runtime = HarborPluginRuntime(id: "trusted-music-billboard", name: "Harbor Billboard", source: asset.program.source, format: .raw,
                scope: scope, currentScope: currentScope, transport: transport)
        }
        guard let runtime else { throw CancellationError() }
        var input = arguments; input["operation"] = .string(operation)
        let result = try await runtime.call("content", arguments: [.object(input)], timeout: 60)
        try validate()
        return try JSONDecoder().decode(type, from: JSONEncoder().encode(result))
    }
    func ranking(_ chart: String, refresh: Bool = false) async throws -> MusicBillboardRanking {
        try await query("load", arguments: ["chart": .string(chart), "refresh": .bool(refresh)], as: MusicBillboardRanking.self)
    }
    func resolve(_ item: MusicCatalogItem, catalog: any MusicCatalogCalling) async throws -> MusicCatalogItem? {
        try validate()
        var arguments: [String: JSONValue] = [:]
        switch item {
        case .track(let value): arguments["item"] = try encoded(value, kind: "track")
        case .artist(let value): arguments["item"] = try encoded(value, kind: "artist")
        case .album(let value):
            arguments["item"] = try encoded(value, kind: "album")
            let candidates = try await catalog.search(value.title + " " + value.artist, limit: 32)
            try validate()
            arguments["albums"] = .array(try candidates.albums.map { try encoded($0, kind: "album") })
        case .playlist, .station: return nil
        }
        return try await query("resolve", arguments: arguments, as: MusicCatalogItem?.self)
    }
    private func encoded<T: Encodable>(_ value: T, kind: String) throws -> JSONValue {
        var object = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)).objectValue
        object["kind"] = .string(kind); return .object(object)
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { dispose(); throw CancellationError() }
    }
    func dispose() { guard !disposed else { return }; disposed = true; runtime?.dispose(); runtime = nil }
}
