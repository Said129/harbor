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
    private(set) var rows: [DiscoveryRail] = []
    private(set) var loading = false
    @ObservationIgnored private let account: StremboxdAccount

    init(account: StremboxdAccount = .shared) {
        self.account = account
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
        guard let source = account.source else {
            rows = []
            return
        }
        let settings = account.settings
        let full = account.session != nil
        let displayName = account.session?.rowName ?? ""
        let ids = StremboxdRails.orderedVisible(selected: settings.selectedCatalogs, hidden: settings.hiddenCatalogs, order: settings.catalogOrder)
        guard !ids.isEmpty else {
            rows = []
            return
        }
        loading = true
        defer { loading = false }

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
        rows = built
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
