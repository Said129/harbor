import Foundation
import Observation

enum PageRail: Identifiable, Sendable {
    case catalog(CatalogRow)
    case discovery(DiscoveryRail)
    var id: String { switch self { case .catalog(let row): "catalog-" + EBookShelf.hash(row.id); case .discovery(let row): "discovery-" + row.id } }
    var title: String { switch self { case .catalog(let row): row.plan.title; case .discovery(let row): row.title } }
    var kind: String { switch self { case .catalog(let row): row.plan.kind; case .discovery(let row): row.kind } }
    var metas: [Media] { switch self { case .catalog(let row): row.metas; case .discovery(let row): row.metas } }
    var defaultNumerals: Bool { switch self { case .catalog: false; case .discovery(let row): row.ranked || row.id.hasSuffix("-top10") || ["cm-top-movies", "cm-drama", "cm-comedy"].contains(row.id) } }
}
struct PageLayout: Codable, Equatable, Sendable {
    var version = 1
    var order: [String] = []
    var hidden: Set<String> = []
    var renamed: [String: String] = [:]
    var numerals: Set<String> = []
    var plain: Set<String> = []
    var heroSource: String?
    var playButtonSquare = false
    var secondaryMoreInfo = false
    var cwTop = false
}
@MainActor @Observable
final class PageCustomization {
    private static var models: [String: PageCustomization] = [:]
    static func forOwner(_ owner: String, page: String, legacyOwner: String? = nil, inheritedOwner: String? = nil) -> PageCustomization {
        let key = EBookShelf.hash(String(decoding: try! JSONEncoder().encode([owner, page]), as: UTF8.self))
        if let value = models[key] { return value }
        let value = PageCustomization(owner: owner, page: page, legacyOwner: legacyOwner, inheritedOwner: inheritedOwner)
        models[key] = value; return value
    }
    let owner: String
    let page: String
    private(set) var layout: PageLayout
    private(set) var ready = false
    private(set) var error: String?
    private(set) var scope: NavigationScope
    @ObservationIgnored var onEdit: ((PageLayout) -> Void)?
    @ObservationIgnored var onRails: (([PageRail]) -> Void)?
    private var localLayout = PageLayout()
    var editing = false
    private var editingRails: [PageRail] = []
    private var key: String { storageKey(scope) }
    private func storageKey(_ scope: NavigationScope) -> String {
        switch scope {
        case .local: return "page-layout-" + EBookShelf.hash(owner + "|" + page)
        case .harbor: return "page-layout-scope-" + EBookShelf.hash(scope.key + "|" + page)
        }
    }
    init(owner: String, page: String, legacyOwner: String? = nil, inheritedOwner: String? = nil) {
        self.owner = owner; self.page = page; scope = .local(owner: owner)
        var defaults = PageLayout(); defaults.secondaryMoreInfo = page != "home"; defaults.playButtonSquare = page != "home"
        layout = defaults; localLayout = defaults
        do {
            let saved: PageLayout
            if let current = try KeychainStore().read(key, as: PageLayout.self) { saved = current }
            else if let inheritedOwner, inheritedOwner != owner,
                    let shared = try KeychainStore().read("page-layout-" + EBookShelf.hash(inheritedOwner + "|" + page), as: PageLayout.self) {
                // Desktop loadEffective falls back to the household's shared
                // layout until this independent profile saves its own choice.
                saved = shared
            }
            else if let legacyOwner, legacyOwner != owner,
                    let previous = try KeychainStore().read("page-layout-" + EBookShelf.hash(legacyOwner + "|" + page), as: PageLayout.self) {
                guard Self.valid(previous) else { throw HarborError(code: "page-layout") }
                let marker = "page-layout-migration-" + EBookShelf.hash(legacyOwner + "|" + page)
                let destination = try KeychainStore().read(marker, as: String.self)
                if destination == nil || destination == owner {
                    // Claim the migration before copying. A failed copy can retry for
                    // this destination without exposing it to another profile/account.
                    try KeychainStore().write(owner, key: marker)
                    try KeychainStore().write(previous, key: key); saved = previous
                } else { saved = defaults }
            } else { saved = defaults }
            guard Self.valid(saved) else { throw HarborError(code: "page-layout") }
            layout = saved; localLayout = saved; ready = true
        } catch { self.error = "No se pudo recuperar la personalización. Los cambios anteriores se conservan." }
    }
    func ordered(_ rails: [PageRail], includeHidden: Bool = false) -> [PageRail] {
        var unique = Set<String>()
        let available = rails.filter { rail in
            if case .catalog(let row) = rail, row.plan.isPlaybackHistoryCatalog { return false }
            return unique.insert(rail.id).inserted && (includeHidden || !layout.hidden.contains(rail.id))
        }
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        var seen = Set<String>()
        return (layout.order.compactMap { byID[$0] } + available).filter { seen.insert($0.id).inserted }
    }
    func title(_ rail: PageRail, among rails: [PageRail]) -> String {
        if let title = layout.renamed[rail.id] { return title }
        return rail.title
    }
    func ranked(_ rail: PageRail) -> Bool { layout.numerals.contains(rail.id) || (rail.defaultNumerals && !layout.plain.contains(rail.id)) }
    func bind(_ next: NavigationScope) {
        guard next.owner == owner else { return }
        if scope == next && ready { return }
        scope = next; onEdit = nil; onRails = nil; ready = false; editing = false; layout = localLayout
        do {
            let value = try KeychainStore().read(storageKey(next), as: PageLayout.self) ?? localLayout
            guard Self.valid(value) else { throw HarborError(code: "page-layout") }
            layout = value; ready = true; error = nil
            if case .local = next { localLayout = value }
        } catch { error = "No se pudo recuperar la personalización. Los cambios anteriores se conservan." }
    }
    func apply(_ value: PageLayout, to expected: NavigationScope) throws {
        guard ready, scope == expected, Self.valid(value) else { throw HarborError(code: "account-changed") }
        if value != layout { try KeychainStore().write(value, key: key); layout = value }
        error = nil
    }
    func setEditingRails(_ rails: [PageRail]) { editingRails = rails; onRails?(rails) }
    var currentRails: [PageRail] { editingRails }
    func move(_ rail: PageRail, toward neighbor: PageRail) {
        var ids = ordered(editingRails.isEmpty ? [rail, neighbor] : editingRails, includeHidden: true).map(\.id)
        guard let first = ids.firstIndex(of: rail.id), let second = ids.firstIndex(of: neighbor.id) else { return }
        ids.swapAt(first, second)
        change { $0.order = ids }
    }
    func change(_ edit: (inout PageLayout) -> Void) {
        guard ready else { return }
        var next = layout; edit(&next)
        do {
            guard Self.valid(next) else { throw HarborError(code: "page-layout") }
            try KeychainStore().write(next, key: key); layout = next; error = nil
            if case .local = scope { localLayout = next }
            onEdit?(next)
        } catch { self.error = "No se pudo guardar la personalización. Los cambios anteriores se conservan." }
    }
    func reset() { change { value in value = PageLayout(); value.secondaryMoreInfo = page != "home"; value.playButtonSquare = page != "home" } }
    nonisolated static func valid(_ value: PageLayout) -> Bool {
        value.version == 1 && value.order.count <= 1_000 && value.hidden.count <= 1_000 && value.renamed.count <= 1_000 && value.numerals.count <= 1_000 && value.plain.count <= 1_000 && value.renamed.values.allSatisfy { $0.count <= 120 }
    }
}
