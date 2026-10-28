import Foundation
import Observation

enum PageRail: Identifiable, Sendable {
    case catalog(CatalogRow)
    case discovery(DiscoveryRail)
    case continuing(kind: String)
    case sources(DesktopSourceRow)
    case list(CustomList)
    var id: String { switch self { case .catalog(let row): "catalog-" + EBookShelf.hash(row.id); case .discovery(let row): "discovery-" + row.id; case .continuing: "continueWatching"; case .sources(let row): row.rowID; case .list(let list): "list-" + list.id } }
    var title: String { switch self { case .catalog(let row): row.plan.title; case .discovery(let row): row.title; case .continuing: DesktopInterfaceText.value("Continue Watching"); case .sources(let row): row.title; case .list(let list): list.name } }
    var kind: String { switch self { case .catalog(let row): row.plan.kind; case .discovery(let row): row.kind; case .continuing(let kind): kind; case .sources: "source"; case .list: "movie" } }
    var metas: [Media] { switch self { case .catalog(let row): row.metas; case .discovery(let row): row.metas; case .continuing, .sources: []; case .list(let list): list.items.map(\.media) } }
    var supportsArtworkCustomization: Bool { switch self { case .continuing, .sources: false; default: true } }
    var defaultNumerals: Bool { switch self { case .catalog, .continuing, .sources, .list: false; case .discovery(let row): row.ranked || row.id.hasSuffix("-top10") || ["cm-top-movies", "cm-drama", "cm-comedy"].contains(row.id) } }
    static func addingContinuation(to rails: [PageRail], kind: String, records: [LibraryRecord], detectedAnime: Set<String>, presentationError: Bool) -> [PageRail] {
        let rows = rails.filter { $0.id != "continueWatching" }
        guard presentationError || records.contains(where: { $0.continuing && ContinueWatchingSelection.includes($0, kind: kind, detectedAnime: detectedAnime) }) else { return rows }
        return [.continuing(kind: kind)] + rows
    }
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
    private(set) var lastEditor: String?
    private(set) var wireProjection: JSONValue?
    private(set) var ready = false
    private(set) var error: String?
    private(set) var scope: NavigationScope
    @ObservationIgnored var onEdit: ((PageLayout) -> Void)?
    @ObservationIgnored var onRails: (([PageRail]) -> Void)?
    private var localLayout = PageLayout()
    private var localProjection: JSONValue?
    var editing = false
    private var editingRails: [PageRail] = []
    private var key: String { storageKey(scope) }
    private func storageKey(_ scope: NavigationScope) -> String {
        switch scope {
        case .local: return "page-layout-" + EBookShelf.hash(scope.owner + "|" + page)
        case .harbor: return "page-layout-scope-" + EBookShelf.hash(scope.key + "|" + page)
        }
    }
    init(owner: String, page: String, legacyOwner: String? = nil, inheritedOwner: String? = nil) {
        self.owner = owner; self.page = page; scope = .local(owner: owner)
        var defaults = PageLayout(); defaults.secondaryMoreInfo = page != "home"; defaults.playButtonSquare = page != "home"
        layout = defaults; localLayout = defaults
        do {
            let saved: PageLayout
            var loadedEditor: String? = nil
            if let current = try LayoutEditStorage.object(key, as: PageLayout.self) {
                if let raw = current.projection { _ = try DesktopPageLayout(page: page, raw: raw) }
                saved = current.value; loadedEditor = current.editor; wireProjection = current.projection
            }
            else if let inheritedOwner, inheritedOwner != owner,
                    let shared = try LayoutEditStorage.object("page-layout-" + EBookShelf.hash(inheritedOwner + "|" + page), as: PageLayout.self) {
                // Desktop loadEffective falls back to the household's shared
                // layout until this independent profile saves its own choice.
                saved = shared.value; wireProjection = shared.projection
            }
            else if let legacyOwner, legacyOwner != owner,
                    let previous = try LayoutEditStorage.object("page-layout-" + EBookShelf.hash(legacyOwner + "|" + page), as: PageLayout.self) {
                guard Self.valid(previous.value) else { throw HarborError(code: "page-layout") }
                let marker = "page-layout-migration-" + EBookShelf.hash(legacyOwner + "|" + page)
                let destination = try KeychainStore().read(marker, as: String.self)
                if destination == nil || destination == owner {
                    // Claim the migration before copying. A failed copy can retry for
                    // this destination without exposing it to another profile/account.
                    try KeychainStore().write(owner, key: marker)
                    try LayoutEditStorage.writeObject(previous, key: key); saved = previous.value
                    loadedEditor = previous.editor; wireProjection = previous.projection
                } else { saved = defaults }
            } else { saved = defaults }
            guard Self.valid(saved) else { throw HarborError(code: "page-layout") }
            if let raw = wireProjection { _ = try DesktopPageLayout(page: page, raw: raw) }
            layout = saved; localLayout = saved; localProjection = wireProjection; lastEditor = loadedEditor; ready = true
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
    func ranked(_ rail: PageRail) -> Bool { rail.supportsArtworkCustomization && (layout.numerals.contains(rail.id) || (rail.defaultNumerals && !layout.plain.contains(rail.id))) }
    func bind(_ next: NavigationScope) {
        guard next.owner == owner else { return }
        if scope == next && ready { return }
        scope = next; onEdit = nil; onRails = nil; ready = false; editing = false; layout = localLayout; lastEditor = nil; wireProjection = nil
        do {
            let saved = try LayoutEditStorage.object(storageKey(next), as: PageLayout.self)
            let value = saved?.value ?? localLayout
            guard Self.valid(value) else { throw HarborError(code: "page-layout") }
            let projection = saved == nil ? localProjection : saved?.projection
            if let raw = projection { _ = try DesktopPageLayout(page: page, raw: raw) }
            layout = value; lastEditor = saved?.editor; wireProjection = projection; ready = true; error = nil
            if case .local = next { localLayout = value; localProjection = projection }
        } catch { self.error = "No se pudo recuperar la personalización. Los cambios anteriores se conservan." }
    }
    func apply(_ value: PageLayout, to expected: NavigationScope, editor: String? = "", projection: JSONValue? = nil) throws {
        guard ready, scope == expected, Self.valid(value) else { throw HarborError(code: "account-changed") }
        if let projection { _ = try DesktopPageLayout(page: page, raw: projection) }
        if value != layout || lastEditor != editor || wireProjection != projection {
            try LayoutEditStorage.writeObject(.init(value: value, editor: editor, projection: projection), key: key)
            layout = value; lastEditor = editor; wireProjection = projection
            if case .local = scope { localLayout = value; localProjection = projection }
        }
        error = nil
    }
    func refreshStoredValue() throws {
        guard ready, let saved = try LayoutEditStorage.object(key, as: PageLayout.self) else { return }
        guard Self.valid(saved.value) else { throw HarborError(code: "page-layout") }
        if let raw = saved.projection { _ = try DesktopPageLayout(page: page, raw: raw) }
        layout = saved.value; lastEditor = saved.editor; wireProjection = saved.projection
    }
    func inheritSharedIfAbsent(_ shared: NavigationScope) throws {
        guard ready, case .harbor(_, let account, _, false) = scope,
              case .harbor(_, let sourceAccount, _, true) = shared, account == sourceAccount,
              try LayoutEditStorage.object(key, as: PageLayout.self) == nil,
              try LayoutEditStorage.object(storageKey(.local(owner: owner)), as: PageLayout.self) == nil else { return }
        let inherited = try LayoutEditStorage.object(storageKey(shared), as: PageLayout.self)
            ?? LayoutEditStorage.object(storageKey(.local(owner: shared.owner)), as: PageLayout.self)
        guard let inherited else { return }
        guard Self.valid(inherited.value) else { throw HarborError(code: "page-layout") }
        if let raw = inherited.projection { _ = try DesktopPageLayout(page: page, raw: raw) }
        layout = inherited.value; lastEditor = ""; wireProjection = inherited.projection
    }
    func materializeProjection(mapping: DesktopPageRowMap) throws {
        guard ready, let wireProjection else { return }
        let next = try DesktopPageLayout(page: page, raw: wireProjection).native(preserving: layout, mapping: mapping)
        guard Self.valid(next) else { throw HarborError(code: "page-layout") }
        guard next != layout else { return }
        if try LayoutEditStorage.object(key, as: PageLayout.self) == nil {
            // Effective shared settings remain inherited until the user edits.
            layout = next; return
        }
        // Mapping newly available rows is not a user edit or a new sync baseline.
        try apply(next, to: scope, editor: lastEditor, projection: wireProjection)
    }
    func setEditingRails(_ rails: [PageRail]) {
        editingRails = rails
        do { try materializeProjection(mapping: DesktopPageRowMap(page: page, rails: rails)); onRails?(rails) }
        catch { self.error = "No se pudo recuperar la personalización. Los cambios anteriores se conservan." }
    }
    var currentRails: [PageRail] { editingRails }
    func move(_ rail: PageRail, toward neighbor: PageRail) {
        var ids = ordered(editingRails.isEmpty ? [rail, neighbor] : editingRails, includeHidden: true).map(\.id)
        guard let first = ids.firstIndex(of: rail.id), let second = ids.firstIndex(of: neighbor.id) else { return }
        ids.swapAt(first, second)
        change { $0.order = ids }
    }
    func rename(_ rail: PageRail, to label: String) {
        let title = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        change { $0.renamed[rail.id] = title.isEmpty ? nil : title }
    }
    func change(_ edit: (inout PageLayout) -> Void) {
        guard ready else { return }
        var next = layout; edit(&next)
        guard next != layout else { return }
        do {
            guard Self.valid(next) else { throw HarborError(code: "page-layout") }
            let projection = try wireProjection.map { try DesktopPageLayout(page: page, raw: $0)
                .applying(next, mapping: DesktopPageRowMap(page: page, rails: editingRails)).raw }
            try LayoutEditStorage.writeObject(.init(value: next, editor: scope.editorID, projection: projection), key: key)
            layout = next; lastEditor = scope.editorID; wireProjection = projection; error = nil
            if case .local = scope { localLayout = next; localProjection = projection }
            onEdit?(next)
        } catch { self.error = "No se pudo guardar la personalización. Los cambios anteriores se conservan." }
    }
    var sourceRows: [DesktopSourceRow] {
        guard page == "home" else { return [] }
        var seen = Set<String>()
        return (wireProjection?["customSources"].array ?? []).compactMap(DesktopSourceRow.init).filter { seen.insert($0.id).inserted }
    }
    var listRowIDs: [String] { page == "home" ? wireProjection?["listRows"].array.compactMap(\.string) ?? [] : [] }
    func addListRow(_ id: String, expected: NavigationScope) throws {
        try changeListRows(expected: expected) { if !$0.contains(id) { $0.append(id) } }
    }
    func removeListRow(_ id: String, expected: NavigationScope) throws {
        try changeListRows(expected: expected) { $0.removeAll { $0 == id } }
    }
    private func changeListRows(expected: NavigationScope, edit: (inout [String]) -> Void) throws {
        guard ready, page == "home", scope == expected else { throw HarborError(code: "account-changed") }
        let mapping = DesktopPageRowMap(page: page, rails: editingRails)
        let previous = try DesktopPageLayout(page: page, raw: wireProjection ?? .object([:])).applying(layout, mapping: mapping)
        var fields = previous.raw.objectValue, ids = previous.listRows
        edit(&ids); fields["listRows"] = .array(ids.map(JSONValue.string))
        let projection = try DesktopPageLayout(page: page, raw: .object(fields)).raw
        guard projection != previous.raw else { return }
        try LayoutEditStorage.writeObject(.init(value: layout, editor: scope.editorID, projection: projection), key: key)
        wireProjection = projection; lastEditor = scope.editorID; error = nil
        if case .local = scope { localProjection = projection }
        onEdit?(layout)
    }
    @discardableResult func importSources(_ text: String, expected: NavigationScope) throws -> Int {
        guard text.utf8.count <= 96 * 1_024 else { throw HarborError(code: "custom-source-import") }
        let rows = DesktopSourceRow.parse(text)
        guard !rows.isEmpty else { throw HarborError(code: "custom-source-import") }
        try changeSources(expected: expected) { $0 = DesktopSourceRow.merging(rows, into: $0) }
        return rows.count
    }
    func removeSource(_ id: String, expected: NavigationScope) throws {
        try changeSources(expected: expected) { $0.removeAll { $0["id"].string == id } }
    }
    func editSourceImages(rowID: String, folderID: String, cover: String, focus: String, expected: NavigationScope) throws {
        try changeSources(expected: expected) { rows in
            rows = rows.map { raw in
                guard let row = DesktopSourceRow(raw), row.id == rowID else { return raw }
                return row.editingImages(folderID: folderID, cover: cover, focus: focus).raw
            }
        }
    }
    private func changeSources(expected: NavigationScope, edit: (inout [JSONValue]) -> Void) throws {
        guard ready, page == "home", scope == expected else { throw HarborError(code: "account-changed") }
        let mapping = DesktopPageRowMap(page: page, rails: editingRails)
        let previous = try DesktopPageLayout(page: page, raw: wireProjection ?? .object([:])).applying(layout, mapping: mapping)
        var fields = previous.raw.objectValue, rows = previous.raw["customSources"].array
        edit(&rows); fields["customSources"] = .array(rows)
        let projection = try DesktopPageLayout(page: page, raw: .object(fields)).raw
        guard projection != previous.raw else { return }
        try LayoutEditStorage.writeObject(.init(value: layout, editor: scope.editorID, projection: projection), key: key)
        wireProjection = projection; lastEditor = scope.editorID; error = nil
        if case .local = scope { localProjection = projection }
        onEdit?(layout)
    }
    func reset() {
        guard ready else { return }
        var next = PageLayout(); next.secondaryMoreInfo = page != "home"; next.playButtonSquare = page != "home"
        do {
            var projection = try wireProjection.map { try DesktopPageLayout(page: page, raw: $0)
                .applying(next, mapping: DesktopPageRowMap(page: page, rails: editingRails)).raw }
            if page == "home", let original = projection {
                var fields = original.objectValue; fields["customSources"] = .array([]); fields["listRows"] = .array([])
                // Desktop reset clears supported row options even for references
                // removed earlier; unrelated future document fields still survive.
                for key in ["order", "hidden", "numerals"] { fields[key] = .array([]) }
                fields["renamed"] = .object([:]); fields["heroSource"] = .null
                projection = try DesktopPageLayout(page: page, raw: .object(fields)).raw
            }
            guard next != layout || projection != wireProjection else { return }
            try LayoutEditStorage.writeObject(.init(value: next, editor: scope.editorID, projection: projection), key: key)
            layout = next; wireProjection = projection; lastEditor = scope.editorID; error = nil
            if case .local = scope { localLayout = next; localProjection = projection }
            onEdit?(next)
        } catch { self.error = "No se pudo guardar la personalización. Los cambios anteriores se conservan." }
    }
    nonisolated static func valid(_ value: PageLayout) -> Bool {
        value.version == 1 && value.order.count <= 1_000 && value.hidden.count <= 1_000 && value.renamed.count <= 1_000 && value.numerals.count <= 1_000 && value.plain.count <= 1_000 && value.renamed.values.allSatisfy { $0.count <= 120 }
    }
}
