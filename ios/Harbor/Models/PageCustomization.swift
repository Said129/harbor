import Foundation
import Observation

enum PageRail: Identifiable, Sendable {
    case catalog(CatalogRow)
    case discovery(DiscoveryRail)
    var id: String { switch self { case .catalog(let row): "catalog-" + EBookShelf.hash(row.id); case .discovery(let row): "discovery-" + row.id } }
    var title: String { switch self { case .catalog(let row): row.plan.title; case .discovery(let row): row.title } }
    var kind: String { switch self { case .catalog(let row): row.plan.kind; case .discovery(let row): row.kind } }
    var metas: [Media] { switch self { case .catalog(let row): row.metas; case .discovery(let row): row.metas } }
    var defaultNumerals: Bool { switch self { case .catalog: false; case .discovery(let row): row.id.hasSuffix("-top10") || ["cm-top-movies", "cm-drama", "cm-comedy"].contains(row.id) } }
}
struct PageLayout: Codable {
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
    let owner: String
    let page: String
    private(set) var layout: PageLayout
    private(set) var ready = false
    private(set) var error: String?
    var editing = false
    private var editingRails: [PageRail] = []
    private var key: String { "page-layout-" + EBookShelf.hash(owner + "|" + page) }
    init(owner: String, page: String) {
        self.owner = owner; self.page = page
        var defaults = PageLayout(); defaults.secondaryMoreInfo = page != "home"; defaults.playButtonSquare = page != "home"
        layout = defaults
        do {
            let saved = try KeychainStore().read(key, as: PageLayout.self) ?? defaults
            guard Self.valid(saved) else { throw HarborError(code: "page-layout") }
            layout = saved; ready = true
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
    func setEditingRails(_ rails: [PageRail]) { editingRails = rails }
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
        } catch { self.error = "No se pudo guardar la personalización. Los cambios anteriores se conservan." }
    }
    func reset() { change { value in value = PageLayout(); value.secondaryMoreInfo = page != "home"; value.playButtonSquare = page != "home" } }
    private static func valid(_ value: PageLayout) -> Bool {
        value.version == 1 && value.order.count <= 1_000 && value.hidden.count <= 1_000 && value.renamed.count <= 1_000 && value.numerals.count <= 1_000 && value.plain.count <= 1_000 && value.renamed.values.allSatisfy { $0.count <= 120 }
    }
}
