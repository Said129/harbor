import SwiftUI

struct CatalogsView: View {
    let app: AppModel
    @State private var kind = "all"
    @State private var query = ""
    @State private var addon = ""
    @State private var managing = false
    @State private var customization: PageCustomization
    @MainActor init(app: AppModel) {
        self.app = app
        _customization = State(initialValue: app.pageCustomization("catalogs"))
    }
    private var rows: [CatalogRow] {
        app.rows.filter { row in
            (kind == "all" || row.plan.kind == kind) && (addon.isEmpty || row.plan.addon.id == addon) &&
                (query.isEmpty || (row.plan.title + " " + row.plan.addon.name).localizedCaseInsensitiveContains(query))
        }
    }
    /// Desktop's pinned and hidden catalogs, applied to the rows the filters left (`use-catalog-list.ts`).
    private var sections: HomeCatalogFilter.CatalogSections {
        HomeCatalogFilter.catalogSections(rows, pinned: InterfacePreferences.shared.catalogsPinned, hidden: InterfacePreferences.shared.catalogsHidden)
    }
    private var customizeBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button { managing.toggle() } label: {
                Text(DesktopInterfaceText.value(managing ? "Done" : "Customize")).font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(height: 38)
                    .foregroundStyle(managing ? HarborTheme.accent : HarborTheme.ink)
                    .background(HarborTheme.surface, in: .capsule)
            }.buttonStyle(.plain).accessibilityIdentifier("catalogs-customize")
        }.padding(.horizontal)
    }
    @ViewBuilder private var pinnedSection: some View {
        if !sections.pinned.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 9) {
                    Image(systemName: "pin.fill").foregroundStyle(HarborTheme.accent)
                    Text(DesktopInterfaceText.value("Pinned")).font(.subheadline.weight(.semibold))
                    Text("\(sections.pinned.count)").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal)
                CustomizedRails(rails: sections.pinned.map(PageRail.catalog), app: app, customization: customization)
            }
        }
    }
    @ViewBuilder private var emptyContent: some View {
        if app.rows.isEmpty { HarborCatalogEmptyView(app: app).padding(.horizontal) }
        else if rows.isEmpty { HarborNoMatchesView().padding(.horizontal) }
        else { CatalogAllHiddenView(count: rows.count) { managing = true }.padding(.horizontal) }
    }
    private var providers: [Addon] {
        var seen = Set<String>()
        return app.rows.map { $0.plan.addon }.filter { seen.insert($0.id).inserted }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HarborPageHeading(title: "Catálogos", subtitle: "Todo lo que ofrecen tus complementos, mostrado como pósteres. Desplázate, busca o filtra hasta encontrar lo que quieras.").padding(.horizontal)
                HarborSearchField(prompt: "Buscar catálogos", text: $query).padding(.horizontal)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach([("Todos", "all"), ("Películas", "movie"), ("Series", "series"), ("Anime", "anime")], id: \.1) { title, value in
                            HarborPill(title: title, selected: kind == value) { kind = value }
                        }
                        NavigationLink { LibraryView(app: app) } label: { Text("Biblioteca").font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(height: 38).background(HarborTheme.surface, in: .capsule) }.buttonStyle(.plain)
                        Menu {
                            Button("Todos los addons") { addon = "" }
                            ForEach(providers) { provider in Button(provider.name) { addon = provider.id } }
                        } label: { Label(providers.first { $0.id == addon }?.name ?? "Todos los addons", image: "nav-addons").font(.caption).padding(.horizontal, 14).frame(height: 38).background(HarborTheme.surface, in: .capsule) }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden)
                customizeBar
                PageCustomizeButton(rails: app.rows.map(PageRail.catalog), customization: customization)
                if managing {
                    CatalogManageList(rows: rows)
                } else {
                    pinnedSection
                    ForEach(providers.filter { provider in sections.rest.contains { $0.plan.addon.id == provider.id } }) { provider in
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 9) {
                                Artwork(url: provider.manifest["logo"].string, maxPixels: 96, failureIcon: "nav-addons").frame(width: 24, height: 24).clipShape(.rect(cornerRadius: 6))
                                Text(provider.name).font(.subheadline.weight(.semibold))
                                Text("\(sections.rest.filter { $0.plan.addon.id == provider.id }.count)").font(.caption2).foregroundStyle(.secondary)
                            }.padding(.horizontal)
                            CustomizedRails(rails: sections.rest.filter { $0.plan.addon.id == provider.id }.map(PageRail.catalog), app: app, customization: customization)
                        }
                    }
                    if !app.loading && sections.pinned.isEmpty && sections.rest.isEmpty { emptyContent }
                }
            }.padding(.vertical, 20)
        }.background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { PageEditingFooter(customization: customization) }
            .overlay { if app.loading && app.rows.isEmpty { ProgressView() } }
            .refreshable { await app.loadHome() }
    }
}

/// Desktop's Customize list (`catalogs/catalog-manage-list.tsx`): pin, hide and reorder the catalogs on this screen.
private struct CatalogManageList: View {
    let rows: [CatalogRow]
    private var pinnedKeys: [String] { InterfacePreferences.shared.catalogsPinned }
    private var pinnedRows: [CatalogRow] { HomeCatalogFilter.catalogSections(rows, pinned: pinnedKeys, hidden: []).pinned }
    private var unpinned: [CatalogRow] { rows.filter { (row: CatalogRow) -> Bool in !pinnedKeys.contains(HomeCatalogFilter.catalogKey(row)) } }
    private var addons: [Addon] {
        var seen = Set<String>()
        return unpinned.map { $0.plan.addon }.filter { seen.insert($0.id).inserted }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(DesktopInterfaceText.value("Pin the catalogs you want up top, hide the ones you never open, and reorder your pinned rails. Your browse view updates instantly."))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if !pinnedRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DesktopInterfaceText.value("Pinned to top")).font(.subheadline.weight(.semibold))
                    ForEach(pinnedRows) { row in CatalogManageRow(row: row, pinnedOrder: pinnedKeys) }
                }.padding(.horizontal)
            }
            ForEach(addons) { addon in
                VStack(alignment: .leading, spacing: 8) {
                    Text(addon.name).font(.subheadline.weight(.semibold))
                    ForEach(unpinned.filter { $0.plan.addon.id == addon.id }) { row in CatalogManageRow(row: row, pinnedOrder: pinnedKeys) }
                }.padding(.horizontal)
            }
        }
    }
}

private struct CatalogManageRow: View {
    let row: CatalogRow
    let pinnedOrder: [String]
    var body: some View {
        let key = HomeCatalogFilter.catalogKey(row)
        let index = pinnedOrder.firstIndex(of: key)
        let isHidden = InterfacePreferences.shared.catalogsHidden.contains(key)
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.plan.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(row.plan.addon.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let index {
                iconButton("chevron.up", label: DesktopInterfaceText.value("Move up"), enabled: index > 0) { move(key, by: -1) }
                iconButton("chevron.down", label: DesktopInterfaceText.value("Move down"), enabled: index < pinnedOrder.count - 1) { move(key, by: 1) }
            }
            iconButton(isHidden ? "eye.slash" : "eye", label: isHidden ? DesktopInterfaceText.value("Show this catalog") : DesktopInterfaceText.value("Hide this catalog")) { toggleHidden(key) }
            iconButton(index == nil ? "pin" : "pin.slash", label: index == nil ? DesktopInterfaceText.value("Pin to top") : DesktopInterfaceText.value("Unpin")) { togglePin(key) }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(HarborTheme.surface, in: .rect(cornerRadius: 12))
        .opacity(isHidden ? 0.45 : 1)
    }
    private func iconButton(_ symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 40, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3).accessibilityLabel(label)
    }
    private func move(_ key: String, by offset: Int) {
        InterfacePreferences.shared.catalogsPinned = HomeCatalogFilter.movingPin(InterfacePreferences.shared.catalogsPinned, key, by: offset)
    }
    private func togglePin(_ key: String) {
        InterfacePreferences.shared.catalogsPinned = HomeCatalogFilter.toggled(InterfacePreferences.shared.catalogsPinned, key)
    }
    private func toggleHidden(_ key: String) {
        InterfacePreferences.shared.catalogsHidden = HomeCatalogFilter.toggled(InterfacePreferences.shared.catalogsHidden, key)
    }
}

/// Desktop's `AllHidden` notice (`catalogs.tsx`): every catalog that matched is hidden.
private struct CatalogAllHiddenView: View {
    let count: Int
    let onCustomize: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text(count == 1 ? DesktopInterfaceText.value("You've hidden the one catalog that matched.") : DesktopInterfaceText.value("You've hidden every catalog that matched."))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: onCustomize) {
                Text(DesktopInterfaceText.value("Customize")).font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(height: 40)
                    .background(HarborTheme.surface, in: .capsule)
            }.buttonStyle(.plain)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

struct CatalogBrowserView: View {
    let app: AppModel
    let initial: CatalogRow
    var titleOverride: String?
    @State private var genre = ""
    @State private var items: [Media] = []
    @State private var loading = false
    @State private var error: String?
    @State private var paging: DesktopGridPaging
    @State private var loadedGenre: String?
    @State private var generation = 0
    private var genres: [String] { initial.plan.catalog?.extra.first { $0.name == "genre" }?.options ?? [] }
    private var supportsPaging: Bool { initial.plan.catalog?.extra.contains { $0.name == "skip" } ?? false }
    init(app: AppModel, initial: CatalogRow, titleOverride: String? = nil) {
        self.app = app; self.initial = initial; self.titleOverride = titleOverride
        _genre = State(initialValue: initial.selectedGenre ?? "")
        _items = State(initialValue: initial.metas)
        _paging = State(initialValue: DesktopGridPaging(initialCount: initial.receivedCount ?? initial.metas.count))
        _loadedGenre = State(initialValue: initial.metas.isEmpty ? nil : initial.selectedGenre ?? "")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !genres.isEmpty {
                    Picker("Género", selection: $genre) {
                        Text("Todos los géneros").tag("")
                        ForEach(genres, id: \.self) { Text($0).tag($0) }
                    }.padding(.horizontal).accessibilityIdentifier("catalog-genre")
                }
                if let error {
                    VStack(alignment: .leading) { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load(reset: items.isEmpty) } } }.padding(.horizontal)
                }
                PosterGrid(spacing: 20) {
                    ForEach(items, id: \.identity) { media in
                        NavigationLink { DetailView(media: media, app: app) } label: { Poster(media: media, width: nil) }.buttonStyle(.plain).accessibilityLabel(media.name).accessibilityIdentifier("catalog-browser-media")
                    }
                }.padding(.horizontal)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if supportsPaging && paging.loaded > 0 && !paging.finished && error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding().task(id: paging.page) { await load(reset: false) }
                }
                if !loading && items.isEmpty && error == nil { HarborNoMatchesView(text: "No titles match these filters.").padding(.horizontal) }
            }
        }.background(HarborTheme.background).navigationTitle(titleOverride ?? initial.plan.title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("catalog-browser-scroll")
            .task(id: genre) { if loadedGenre != genre { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        loading = true; error = nil
        generation += 1
        let requestGeneration = generation
        if reset { items = []; paging = DesktopGridPaging(); loadedGenre = nil }
        let requestedGenre = genre
        defer { if requestGeneration == generation { loading = false } }
        do {
            // Request this catalog only: some addons expose dozens of catalogs.
            let result = try await app.service.catalog(initial.plan, genre: requestedGenre.isEmpty ? nil : requestedGenre, skip: paging.loaded)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            var known = Set(items.map(\.identity))
            let additions = result.metas.filter { known.insert($0.identity).inserted }
            items.append(contentsOf: additions)
            let count = result.receivedCount ?? result.metas.count
            paging.received(count); loadedGenre = requestedGenre
        } catch is CancellationError { return }
        catch { if requestGeneration == generation { self.error = safeMessage(error) } }
    }
}
