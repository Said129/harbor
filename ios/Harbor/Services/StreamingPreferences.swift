import Foundation
import Observation

struct StreamingServiceDefinition: Decodable, Identifiable, Sendable {
    let key: String
    let name: String
    let providerIds: [Int]
    let enabledByDefault: Bool
    let asset: String
    let tint: String
    let logoHeight: Double
    var id: String { key }
    var providers: String { providerIds.map(String.init).joined(separator: "|") }
    static let all: [StreamingServiceDefinition] = {
        guard let file = Bundle.main.url(forResource: "DesktopStreamingServices", withExtension: "json"),
              let bytes = try? Data(contentsOf: file), bytes.count <= 64 * 1_024,
              let definitions = try? JSONDecoder().decode([Self].self, from: bytes),
              definitions.count == 27, Set(definitions.map(\.key)).count == definitions.count,
              definitions.allSatisfy({ !$0.providerIds.isEmpty && $0.providerIds.count <= 8 && $0.providerIds.allSatisfy { $0 > 0 } }) else { return [] }
        return definitions
    }()
}

@MainActor protocol StreamingPreferencePersistence {
    func load(_ key: String) throws -> [String: Bool]?
    func save(_ value: [String: Bool], key: String) throws
}

@MainActor private struct StreamingKeychain: StreamingPreferencePersistence {
    func load(_ key: String) throws -> [String: Bool]? { try KeychainStore().read(key, as: [String: Bool].self) }
    func save(_ value: [String: Bool], key: String) throws { try KeychainStore().write(value, key: key) }
}

@MainActor @Observable
final class StreamingPreferences {
    private static var stores: [String: StreamingPreferences] = [:]
    static func forOwner(_ owner: String) -> StreamingPreferences {
        if let value = stores[owner] { return value }
        let value = StreamingPreferences(owner: owner); stores[owner] = value; return value
    }
    let owner: String
    private(set) var scope: NavigationScope
    private(set) var values: [String: Bool] = [:]
    private(set) var ready = false
    private(set) var cloudWritePending = false
    private(set) var error: String?
    private let persistence: any StreamingPreferencePersistence
    @ObservationIgnored var onEdit: (([String: Bool]) -> Void)?
    private var localKey: String { "native-streaming-" + EBookShelf.hash(owner) }
    private var key: String {
        switch scope {
        case .local: localKey
        case .harbor: "scoped-streaming-" + EBookShelf.hash(scope.key)
        }
    }
    var enabled: [StreamingServiceDefinition] { StreamingServiceDefinition.all.filter { isEnabled($0.key) } }
    var signature: String { (ready ? "ready|" : "unavailable|") + enabled.map(\.key).joined(separator: ",") }

    init(owner: String, persistence: (any StreamingPreferencePersistence)? = nil) {
        self.owner = owner; self.scope = .local(owner: owner)
        self.persistence = persistence ?? StreamingKeychain(); reload()
    }
    func isEnabled(_ key: String) -> Bool { values[key] ?? StreamingServiceDefinition.all.first { $0.key == key }?.enabledByDefault ?? false }
    var selection: [String: Bool] { Dictionary(uniqueKeysWithValues: StreamingServiceDefinition.all.map { ($0.key, isEnabled($0.key)) }) }
    func bind(_ next: NavigationScope) {
        guard next.owner == owner, next != scope || !ready else { return }
        if next != scope { values = [:] }
        scope = next; onEdit = nil; cloudWritePending = false; reload()
    }
    func suspend() { ready = false; values = [:]; onEdit = nil; cloudWritePending = false }
    func reload() {
        ready = false
        do {
            let value: [String: Bool]
            if let saved = try persistence.load(key) { value = saved }
            else if case .harbor = scope { value = try persistence.load(localKey) ?? [:] }
            else { value = [:] }
            guard Self.valid(value) else { throw HarborError(code: "streaming-preferences") }
            values = value; ready = true; error = nil
        } catch { self.error = "Could not load streaming preferences. Saved settings are kept." }
    }
    @discardableResult func setEnabled(_ enabled: Bool, for service: String, in expected: NavigationScope? = nil) -> Bool {
        guard ready, !cloudWritePending, expected == nil || expected == scope, StreamingServiceDefinition.all.contains(where: { $0.key == service }) else { return false }
        guard isEnabled(service) != enabled else { return true }
        var next = values; next[service] = enabled
        do {
            try persistence.save(next, key: key); values = next; error = nil; onEdit?(selection); return true
        } catch { self.error = "Could not save streaming preferences. Your previous settings are kept."; return false }
    }
    func apply(_ selection: [String: Bool], to expected: NavigationScope) throws {
        let known = Set(StreamingServiceDefinition.all.map(\.key))
        guard ready, scope == expected, Self.valid(selection), Set(selection.keys) == known else { throw HarborError(code: "account-changed") }
        let next = values.filter { !known.contains($0.key) }.merging(selection) { _, new in new }
        if next != values { try persistence.save(next, key: key); values = next }
        error = nil
    }
    func holdCloudWrite(_ pending: Bool, in expected: NavigationScope) {
        guard scope == expected else { return }; cloudWritePending = pending
    }
    private static func valid(_ value: [String: Bool]) -> Bool { value.count <= 128 && value.keys.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 } }
}

enum StreamingCatalog {
    static func rail(_ service: StreamingServiceDefinition) -> DiscoveryRail {
        DiscoveryRail(id: "streaming-" + service.key, title: service.name, kind: "mixed", path: "streaming:" + service.key)
    }
    static func definition(_ service: StreamingServiceDefinition, kind: String, region: String) -> DiscoveryRail {
        DiscoveryRail(id: "streaming-\(service.key)-\(kind)", title: service.name, kind: kind,
                      path: "discover/" + (kind == "movie" ? "movie" : "tv"),
                      parameters: ["with_watch_providers": service.providers, "watch_region": region.isEmpty ? "US" : region,
                                   "with_watch_monetization_types": "flatrate", "vote_count.gte": "300", "sort_by": "popularity.desc"])
    }
    static func interleave(_ movies: [Media], _ series: [Media], perTypeLimit: Int? = 12) -> [Media] {
        var output: [Media] = []; var seen = Set<String>()
        let movieCount = min(movies.count, max(0, perTypeLimit ?? movies.count)), seriesCount = min(series.count, max(0, perTypeLimit ?? series.count))
        for index in 0..<max(movieCount, seriesCount) {
            for list in [movies, series] where index < min(list.count, max(0, perTypeLimit ?? list.count)) {
                if seen.insert(list[index].identity).inserted { output.append(list[index]) }
            }
        }
        return output
    }
    static func page(_ service: StreamingServiceDefinition, page: Int, configuration: MetadataConfiguration, preview: Bool = false) async throws -> [Media] {
        async let movies = TMDBService().page(definition(service, kind: "movie", region: configuration.region), page: page, configuration: configuration)
        async let series = TMDBService().page(definition(service, kind: "series", region: configuration.region), page: page, configuration: configuration)
        let results = try await (movies, series)
        return interleave(results.0, results.1, perTypeLimit: preview ? 12 : nil)
    }
}
