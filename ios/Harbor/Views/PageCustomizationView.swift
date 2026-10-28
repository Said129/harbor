import SwiftUI

struct PageCustomizeButton: View {
    let rails: [PageRail]
    let customization: PageCustomization
    var cloud: HarborPageSync? = nil
    var listStore: CustomListStore? = nil
    @State private var optionsOpen = false
    @State private var listsOpen = false
    @State private var listError: String?
    @State private var importingSources = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String {
        DesktopInterfaceText.value(customization.editing ? "Done editing" : customization.page == "home" ? "Customize home" : customization.page == "anime" ? "Customize anime" : "Customize page")
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if customization.editing && customization.page == "home" {
                HStack(spacing: 8) {
                    PageEditPill(title: DesktopInterfaceText.value("Add Custom Source"), icon: "nav-addons") { importingSources = true }
                        .accessibilityIdentifier("custom-source-add")
                    if let listStore, !CustomListHomeRows.available(listStore.lists, ids: customization.listRowIDs).isEmpty {
                        PageEditPill(title: DesktopInterfaceText.value("Add from lists"), icon: "desktop-layers") { listsOpen.toggle() }
                            .accessibilityIdentifier("home-add-list").disabled(!listStore.ready || listStore.busy)
                            .popover(isPresented: $listsOpen) { listPicker(listStore) }
                    }
                }
                if let listError { Text(listError).font(.caption).foregroundStyle(.orange) }
            }
            if let cloud, cloud.hasParkedVersion {
                Button(DesktopInterfaceText.value("Restore my version")) { cloud.restoreMyVersion() }
                    .font(.caption).frame(minHeight: 44).accessibilityIdentifier("page-restore-cloud-layout")
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if customization.editing {
                    PageEditPill(title: DesktopInterfaceText.value("Options"), icon: "page-options") { optionsOpen.toggle() }
                        .accessibilityIdentifier("page-customize-options")
                        .popover(isPresented: $optionsOpen) {
                            VStack(alignment: .leading, spacing: 18) {
                                HarborSettingsToggle(DesktopInterfaceText.value("Square play button"), isOn: setting(\.playButtonSquare))
                                HarborSettingsToggle(DesktopInterfaceText.value("Show More info button"), isOn: setting(\.secondaryMoreInfo))
                                if customization.page == "home" {
                                    HarborSettingsToggle(DesktopInterfaceText.value("Continue Watching at top"), isOn: setting(\.cwTop))
                                }
                            }.padding(16).frame(width: 280).background(ThemePreferences.shared.color("elevated"))
                                .presentationCompactAdaptation(.popover)
                        }
                }
                PageEditPill(title: title, icon: "ui-pencil-outline", selected: customization.editing) {
                    customization.setEditingRails(rails)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { customization.editing.toggle() }
                    optionsOpen = false
                    listsOpen = false
                }.accessibilityIdentifier("page-customize")
            }
        }.padding(.horizontal).disabled(!customization.ready)
            .sheet(isPresented: $importingSources) { CustomSourceImportView(customization: customization) }
            .task(id: rails.map(\.id)) { customization.setEditingRails(rails) }
            .onChange(of: customization.scope) { _, _ in listsOpen = false; listError = nil }
            .onDisappear { customization.editing = false; listsOpen = false }
    }
    private func listPicker(_ store: CustomListStore) -> some View {
        let scope = customization.scope
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(CustomListHomeRows.available(store.lists, ids: customization.listRowIDs)) { list in
                    Button {
                        do { try customization.addListRow(list.id, expected: scope); listError = nil; listsOpen = false }
                        catch { listError = safeMessage(error) }
                    } label: {
                        Label(list.name, systemImage: "text.badge.plus").font(HarborTheme.font(12.5))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("home-add-list-choice")
                }
            }.padding(12)
        }.frame(width: 280).frame(maxHeight: 320).background(ThemePreferences.shared.color("elevated")).presentationCompactAdaptation(.popover)
    }
    private func setting(_ key: WritableKeyPath<PageLayout, Bool>) -> Binding<Bool> { Binding(get: { customization.layout[keyPath: key] }, set: { value in customization.change { $0[keyPath: key] = value } }) }
}

struct CustomizedRails: View {
    let rails: [PageRail]
    let app: AppModel
    let customization: PageCustomization
    var body: some View {
        LazyVStack(spacing: 24) {
            ForEach(customization.ordered(rails, includeHidden: customization.editing)) { rail in
                VStack(spacing: 8) {
                    if customization.editing { PageRowControls(rail: rail, rails: rails, customization: customization).padding(.horizontal) }
                    if !customization.layout.hidden.contains(rail.id) {
                        let title = customization.title(rail, among: rails)
                        if case .list(let list) = rail {
                            CustomListHomeRow(list: list, title: title, app: app, ranked: customization.ranked(rail))
                        } else if customization.ranked(rail) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(title).font(.headline).accessibilityIdentifier("catalog-title"); Spacer(); browse(rail) }.padding(.horizontal)
                                TopTenRail(metas: rail.metas)
                            }
                        } else {
                            switch rail {
                            case .list: EmptyView()
                            case .sources(let row): CustomSourceRowView(row: row, title: title, app: app, customization: customization)
                            case .continuing(let kind):
                                ContinueWatching(app: app, kind: kind, title: title, titleIsLiteral: true)
                            case .catalog(let row): CatalogRails(rows: [row], app: app, titleOverrides: [row.id: title])
                            case .discovery(let row):
                                DiscoveryRails(rows: [row], app: app, titleOverrides: [row.id: title], disableDefaultRanking: true)
                            }
                        }
                    }
                }.accessibilityElement(children: .contain)
            }
        }
    }
    @ViewBuilder private func browse(_ rail: PageRail) -> some View {
        switch rail {
        case .continuing, .sources: EmptyView()
        case .list(let list): NavigationLink { CustomListScreen(app: app, listID: list.id) } label: { Text(DesktopInterfaceText.value("View all")).font(.caption).foregroundStyle(.secondary) }
        case .catalog(let row): NavigationLink { CatalogBrowserView(app: app, initial: row) } label: { Label(DesktopInterfaceText.value("View all"), image: "desktop-chevron-right").font(.caption).foregroundStyle(.secondary) }.accessibilityIdentifier("catalog-browser-link")
        case .discovery(let row): NavigationLink(DesktopInterfaceText.value("View all")) { DiscoveryGrid(rail: row, app: app, titleOverride: customization.title(rail, among: rails)) }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CustomizedHero: View {
    let rails: [PageRail]
    let defaults: [Media]
    let app: AppModel
    let customization: PageCustomization
    var animeSources: [String: String] = [:]
    @State private var selected: [Media] = []
    @State private var enrichedSignature = ""
    private var source: PageRail? { rails.first { $0.id == customization.layout.heroSource } }
    private var sourceList: CustomList? {
        guard let source, case .list(let list) = source else { return nil }
        return list
    }
    private var signature: String {
        let ids = source?.metas.prefix(6).map(\.identity).joined(separator: "|") ?? ""
        let list = sourceList.map { list in
            EBookShelf.hash(String(decoding: (try? JSONEncoder().encode(JSONValue.array(list.items.prefix(6).map(\.raw)))) ?? Data(), as: UTF8.self))
        } ?? ""
        let addons = app.addons.filter(\.enabled).map(\.id).joined()
        let settings = MetadataPreferences.shared
        return [source?.id ?? "automatic", ids, list, app.accountOperationScope, addons, settings.region, settings.language, String(settings.translateTitles), EBookShelf.hash(settings.tmdbKey)].joined(separator: "|")
    }
    private var metas: [Media] {
        guard let source else { return defaults }
        if enrichedSignature == signature && !selected.isEmpty { return selected }
        return Array(source.metas.prefix(customization.page == "anime" ? 6 : 5))
    }
    var body: some View {
        Group {
            if customization.page == "anime" {
                HarborAnimeHero(metas: metas, sources: source == nil ? animeSources : [:], picks: rails.first { $0.id == "discovery-anime-picks" }, app: app, customization: customization)
            } else if customization.page == "series" {
                HarborSeriesHero(metas: metas, app: app)
            } else if !metas.isEmpty {
                CinemaHero(metas: metas, app: app, playSquare: customization.layout.playButtonSquare, moreInfo: customization.layout.secondaryMoreInfo, customList: sourceList)
            }
        }
            .task(id: signature) {
                guard let source else { selected = []; enrichedSignature = ""; return }
                let currentSignature = signature
                let originals = Array(source.metas.prefix(customization.page == "anime" ? 6 : 5)); selected = originals; enrichedSignature = currentSignature
                let owner = app.accountOperationScope, service = app.service, addons = app.addons
                let fetched = await withTaskGroup(of: (Int, Media).self, returning: [(Int, Media)].self) { group in
                    for (index, media) in originals.enumerated() {
                        group.addTask { media.type == "manga" ? (index, media) : (index, (try? await service.metadata(media, addons: addons)) ?? media) }
                    }
                    var result: [(Int, Media)] = []; for await value in group { result.append(value) }; return result
                }
                guard !Task.isCancelled, owner == app.accountOperationScope, customization.layout.heroSource == source.id, currentSignature == signature else { return }
                selected = fetched.sorted { $0.0 < $1.0 }.map(\.1)
            }
    }
}
