import Foundation
import Observation

@MainActor @Observable final class TraktHomeModel {
    let account: TraktAccountStore
    private let client: TraktClient
    private let hydrator: TraktHomeHydrator
    private let active: TraktClient.Active
    private var operation = UUID()
    private var loadedIdentity: UUID?
    private var loadedConfiguration = ""
    private var storedRows: [DiscoveryRail] = []
    private var feeds: [String: TraktHomeFeed] = [:]
    private var pages: [String: [Int: [Media]]] = [:]
    private(set) var loading = false
    var isActive: Bool { active() }
    var rows: [DiscoveryRail] { currentAccount ? storedRows.filter { $0.personal?.available() != false } : [] }
    private var currentAccount: Bool { active() && account.ready && account.session != nil && account.identity == loadedIdentity }
    init(account: TraktAccountStore, client: TraktClient = .shared, hydrator: TraktHomeHydrator = .init(), active: @escaping TraktClient.Active) {
        self.account = account; self.client = client; self.hydrator = hydrator; self.active = active
    }
    convenience init(app: AppModel) {
        let owner = app.personalOwner, scope = app.accountOperationScope
        self.init(account: .forOwner(owner), active: { [weak app] in
            app?.personalOwner == owner && app?.accountOperationScope == scope && app?.storageReady == true
        })
    }
    private static func signature(_ configuration: MetadataConfiguration) -> String {
        [EBookShelf.hash(configuration.tmdbKey), configuration.language, configuration.region, String(configuration.translateTitles), configuration.imageLanguages.joined(separator: ","), UserDefaults.standard.string(forKey: "uiLanguage") ?? "es"].joined(separator: "|")
    }
    func cancel() { operation = UUID(); storedRows = []; feeds = [:]; pages = [:]; loadedIdentity = nil; loadedConfiguration = ""; loading = false }
    private func current(_ ticket: UUID, identity: UUID) -> Bool {
        operation == ticket && active() && account.identity == identity && account.session != nil
    }
    func load(configuration: MetadataConfiguration, force: Bool = false, date: Date = Date()) async {
        guard active(), !Task.isCancelled else { return }
        do { if !account.ready { try account.load() } }
        catch { cancel(); return }
        guard account.session != nil else { cancel(); return }
        let signature = Self.signature(configuration)
        if !force, currentAccount, loadedConfiguration == signature { return }
        let ticket = UUID(), identity = account.identity
        operation = ticket; loading = true
        if loadedIdentity != identity || loadedConfiguration != signature { storedRows = []; feeds = [:]; pages = [:] }
        let lease: TraktClient.Active = { [weak self] in self?.current(ticket, identity: identity) ?? false }
        defer { if operation == ticket { loading = false } }
        do {
            async let watchlist = fetch(.library(.watchlist), lease: lease)
            async let upcoming = fetch(.home(.upcoming(TraktHomeEndpoint.utcDay(date))), lease: lease)
            async let movies = fetch(.home(.recommendations(.movie)), lease: lease)
            async let shows = fetch(.home(.recommendations(.show)), lease: lease)
            let sources = try await TraktHomeFeed.build(watchlist: watchlist, upcoming: upcoming, movies: movies, shows: shows)
            try Task.checkCancellation(); guard lease() else { return }
            let hydrator = hydrator
            let hydrated = try await withThrowingTaskGroup(of: (String, [Media]).self) { group in
                for source in sources { group.addTask { (source.id, try await hydrator.hydrate(source.slice(1), configuration: configuration)) } }
                var output = [String: [Media]]()
                for try await (id, values) in group { output[id] = values }
                return output
            }
            try Task.checkCancellation(); guard lease() else { return }
            feeds = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
            pages = hydrated.mapValues { [1: $0] }; loadedIdentity = identity; loadedConfiguration = signature
            storedRows = sources.compactMap { source in
                guard let values = hydrated[source.id], values.count >= 4 else { return nil }
                var rail = DiscoveryRail(id: source.id, title: DesktopInterfaceText.value(source.title), kind: source.kind, path: "trakt:home", metas: values)
                rail.personal = PersonalDiscoverySource(available: lease, page: { [weak self] page in
                    guard let self else { throw CancellationError() }
                    return try await self.page(source.id, number: page, configuration: configuration, ticket: ticket, identity: identity)
                })
                return rail
            }
        } catch is CancellationError { }
        catch { if lease() { storedRows = []; feeds = [:]; pages = [:] } }
    }
    private func fetch(_ endpoint: TraktEndpoint, lease: @escaping TraktClient.Active) async throws -> JSONValue {
        do {
            let value = try await account.response(endpoint, client: client, active: lease)
            guard case .array = value else { return .array([]) }; return value
        }
        catch is CancellationError { throw CancellationError() }
        catch { return .array([]) }
    }
    private func page(_ id: String, number: Int, configuration: MetadataConfiguration, ticket: UUID, identity: UUID) async throws -> [Media] {
        try Task.checkCancellation()
        guard current(ticket, identity: identity), let source = feeds[id] else { throw CancellationError() }
        if let page = pages[id]?[number] { return page }
        let slice = source.slice(number)
        guard !slice.isEmpty else { return [] }
        let result = try await hydrator.hydrate(slice, configuration: configuration)
        try Task.checkCancellation(); guard current(ticket, identity: identity) else { throw CancellationError() }
        pages[id, default: [:]][number] = result; return result
    }
}
