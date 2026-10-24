import Foundation

@MainActor protocol MusicExploreCalling: AnyObject {
    func filter(_ filters: MusicGenreFilters, countryNames: [String: String], genreNames: [String: String]) async throws -> [MusicGenre]
    func chart() async throws -> MusicGenreSelection
    func selection(_ genre: Int) async throws -> MusicGenreSelection
    func tracks(_ genre: Int, page: Int) async throws -> MusicGenreSelection
    func related(_ genre: Int) async throws -> [MusicGenre]
    func dispose()
}
struct MusicExploreTransport: HarborPluginHostTransport {
    var network: any HarborNativeNetworkCalling = HarborNativeNetwork()
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        guard kind == .http, let raw = payload["url"].string, let url = URL(string: raw),
              url.scheme == "https", url.host?.lowercased() == "api.deezer.com", url.port == nil,
              url.user == nil, url.password == nil, payload["opts"]["method"].string == "GET" else { throw HarborError(code: "music-explore-host") }
        return try await HarborNativePluginTransport(policy: .init(sameSiteHeaders: false, publicOnly: true, openHeaders: false, baseURL: nil, blockedHosts: []), network: network).perform(kind, payload: payload)
    }
}
@MainActor final class MusicExploreClient: MusicExploreCalling {
    let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let transport: any HarborPluginHostTransport
    private var runtime: HarborPluginRuntime?
    private var disposed = false
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         transport: any HarborPluginHostTransport = MusicExploreTransport()) {
        self.scope = scope; self.currentScope = currentScope; self.transport = transport
    }
    func query<T: Decodable & Sendable>(_ operation: String, arguments: [String: JSONValue] = [:], as type: T.Type) async throws -> T {
        try validate()
        if runtime == nil {
            let asset = try MusicExploreAsset.read()
            runtime = HarborPluginRuntime(id: "trusted-music-explore", name: "Harbor Music Explore", source: asset.program.source, format: .raw,
                scope: scope, currentScope: currentScope, transport: transport)
        }
        guard let runtime else { throw CancellationError() }
        var input = arguments; input["operation"] = .string(operation)
        let value: JSONValue
        do { value = try await runtime.call("content", arguments: [.object(input)], timeout: 60) }
        catch { try validate(); throw error }
        try validate()
        return try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { dispose(); throw CancellationError() }
    }
    func filter(_ filters: MusicGenreFilters, countryNames: [String: String], genreNames: [String: String]) async throws -> [MusicGenre] {
        try await query("filter", arguments: ["query": .string(filters.query), "countries": .array(filters.countries.map(JSONValue.string)),
            "family": .string(filters.family), "countryNames": .object(countryNames.mapValues(JSONValue.string)), "genreNames": .object(genreNames.mapValues(JSONValue.string))], as: [MusicGenre].self)
    }
    func chart() async throws -> MusicGenreSelection { try await query("chart", as: MusicGenreSelection.self) }
    func selection(_ genre: Int) async throws -> MusicGenreSelection { try await query("selection", arguments: ["genre": .integer(Int64(genre))], as: MusicGenreSelection.self) }
    func tracks(_ genre: Int, page: Int) async throws -> MusicGenreSelection {
        try await query("tracks", arguments: ["genre": .integer(Int64(genre)), "page": .integer(Int64(page))], as: MusicGenreSelection.self)
    }
    func related(_ genre: Int) async throws -> [MusicGenre] { try await query("related", arguments: ["genre": .integer(Int64(genre))], as: [MusicGenre].self) }
    func dispose() { guard !disposed else { return }; disposed = true; runtime?.dispose(); runtime = nil }
}
