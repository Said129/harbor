import Foundation
import Observation

extension StremboxdRails.RowName {
    /// The row title the person sees, translated where Desktop translates it.
    var title: String {
        switch self {
        case .server(let name):
            return name
        case .list(let name, let owner):
            if let owner = owner, !owner.isEmpty { return name + " · " + owner }
            return name
        case .template(let key, let name):
            return DesktopInterfaceText.value(key, variables: ["name": name])
        case .fallback(let key):
            return DesktopInterfaceText.value(key)
        case .unnamed(let id):
            return id
        }
    }
}

/// Desktop's `buildLetterboxdHomeRows` (`lib/stremboxd/home-rails.ts`) as Discovery rails for Home.
/// Home adds `rows` as it does the Trakt rails (see the port report for the one-line hook).
@MainActor @Observable final class StremboxdHomeModel {
    private static var models: [String: StremboxdHomeModel] = [:]
    /// One model per profile, so Home reads the rails of the profile on screen.
    static func forOwner(_ owner: String) -> StremboxdHomeModel {
        if let saved = models[owner] { return saved }
        let model = StremboxdHomeModel(account: StremboxdAccount.forOwner(owner))
        models[owner] = model
        return model
    }

    private(set) var rows: [DiscoveryRail] = []
    private(set) var loading = false
    @ObservationIgnored private let account: StremboxdAccount
    @ObservationIgnored private var loadedSignature: String?
    @ObservationIgnored private var generation = 0

    init(account: StremboxdAccount) {
        self.account = account
    }

    /// The rails for Home. When a setting that changes them has changed since the last load, a reload starts in the background.
    var rails: [DiscoveryRail] {
        let current = signature
        if current != loadedSignature {
            loadedSignature = current
            Task { await load() }
        }
        return rows
    }

    /// Changes whenever a setting that alters the rails changes, so Home can reload them with `.task(id:)`.
    var signature: String {
        let settings = account.settings
        var parts: [String] = []
        parts.append(String(settings.enabled))
        parts.append(settings.mode.rawValue)
        parts.append(settings.username)
        parts.append(settings.selectedCatalogs.joined(separator: ","))
        parts.append(settings.hiddenCatalogs.joined(separator: ","))
        parts.append(settings.catalogOrder.joined(separator: ","))
        parts.append(settings.listRefs.map { $0.id }.joined(separator: ","))
        parts.append(String(settings.showRatingsOnPosters))
        parts.append(account.session?.userId ?? "")
        return parts.joined(separator: "|")
    }

    /// Rebuilds the rails from the current settings. Catalogs load one after another, as on Desktop.
    func load() async {
        generation += 1
        let current = generation
        loading = true
        defer { if current == generation { loading = false } }
        let built = await buildRows()
        // A newer load started meanwhile; its rows win.
        if current == generation { rows = built }
    }

    private func buildRows() async -> [DiscoveryRail] {
        guard let source = account.source else { return [] }
        let settings = account.settings
        let full = account.session != nil
        let displayName = account.session?.rowName ?? ""
        let ids = StremboxdRails.orderedVisible(selected: settings.selectedCatalogs, hidden: settings.hiddenCatalogs, order: settings.catalogOrder)
        guard !ids.isEmpty else { return [] }

        let client = StremboxdClient(transport: account.transport)
        let names = await manifestNames(client, source)
        var built: [DiscoveryRail] = []
        for catalogID in ids {
            if StremboxdRails.fullOnly.contains(catalogID) && !full { continue }
            let realID = StremboxdRails.realCatalogID(catalogID, full: full)
            guard let firstPage = try? await client.catalog(source, catalogID: realID, skip: 0) else { continue }
            guard StremboxdRails.keepsRow(metaCount: firstPage.count) else { continue }
            let list = settings.listRefs.first(where: { (ref: StremboxdListRef) -> Bool in StremboxdCatalogID.list(ref.id) == catalogID })
            let name = StremboxdRails.rowName(catalogID: catalogID, realID: realID, full: full, displayName: displayName, manifestName: names[realID], list: list)
            built.append(makeRail(catalogID: catalogID, realID: realID, title: name.title, metas: firstPage, source: source, client: client))
        }
        return built
    }

    private func manifestNames(_ client: StremboxdClient, _ source: StremboxdSource) async -> [String: String] {
        guard let manifest = try? await client.manifest(source) else { return [:] }
        var names: [String: String] = [:]
        for catalog in manifest["catalogs"].array {
            if let id = catalog["id"].string, let name = catalog["name"].string { names[id] = name }
        }
        return names
    }

    private func makeRail(catalogID: String, realID: String, title: String, metas: [Media], source: StremboxdSource, client: StremboxdClient) -> DiscoveryRail {
        var rail = DiscoveryRail(id: "letterboxd-" + catalogID, title: title, kind: "movie", path: "letterboxd:" + catalogID, metas: metas)
        // Paging: View All asks for page 1 onward, and page 1 starts at skip 0.
        rail.personal = PersonalDiscoverySource(available: { true }, page: { (page: Int) async throws -> [Media] in
            try await client.catalog(source, catalogID: realID, skip: max(page - 1, 0) * StremboxdRails.pageSize)
        })
        return rail
    }
}
