import SwiftUI

struct PageCustomizeButton: View {
    let rails: [PageRail]
    let customization: PageCustomization
    @State private var optionsOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String {
        DesktopInterfaceText.value(customization.editing ? "Done editing" : customization.page == "home" ? "Customize home" : customization.page == "anime" ? "Customize anime" : "Customize page")
    }
    var body: some View {
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
            }.accessibilityIdentifier("page-customize")
        }.padding(.horizontal).disabled(!customization.ready)
            .task(id: rails.map(\.id)) { customization.setEditingRails(rails) }
            .onDisappear { customization.editing = false }
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
                        if customization.ranked(rail) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(title).font(.headline).accessibilityIdentifier("catalog-title"); Spacer(); browse(rail) }.padding(.horizontal)
                                TopTenRail(metas: rail.metas)
                            }
                        } else {
                            switch rail {
                            case .catalog(let row): CatalogRails(rows: [row], app: app, titleOverrides: [row.id: title])
                            case .discovery(let row):
                                DiscoveryRails(rows: [row], app: app, titleOverrides: [row.id: title], disableDefaultRanking: true)
                            }
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder private func browse(_ rail: PageRail) -> some View {
        switch rail {
        case .catalog(let row): NavigationLink { CatalogBrowserView(app: app, initial: row) } label: { Label(DesktopInterfaceText.value("View all"), image: "desktop-chevron-right").font(.caption).foregroundStyle(.secondary) }.accessibilityIdentifier("catalog-browser-link")
        case .discovery(let row): NavigationLink(DesktopInterfaceText.value("View all")) { DiscoveryGrid(rail: row, app: app) }.font(.caption).foregroundStyle(.secondary)
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
    private var signature: String {
        let ids = source?.metas.prefix(6).map(\.identity).joined(separator: "|") ?? ""
        let addons = app.addons.filter(\.enabled).map(\.id).joined()
        let settings = MetadataPreferences.shared
        return [source?.id ?? "automatic", ids, app.user?.id ?? "guest", addons, settings.region, settings.language, String(settings.translateTitles), EBookShelf.hash(settings.tmdbKey)].joined(separator: "|")
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
                CinemaHero(metas: metas, app: app, playSquare: customization.layout.playButtonSquare, moreInfo: customization.layout.secondaryMoreInfo)
            }
        }
            .task(id: signature) {
                guard let source else { selected = []; enrichedSignature = ""; return }
                let currentSignature = signature
                let originals = Array(source.metas.prefix(customization.page == "anime" ? 6 : 5)); selected = originals; enrichedSignature = currentSignature
                let owner = app.user?.id ?? "guest", service = app.service, addons = app.addons
                let fetched = await withTaskGroup(of: (Int, Media).self, returning: [(Int, Media)].self) { group in
                    for (index, media) in originals.enumerated() { group.addTask { (index, (try? await service.metadata(media, addons: addons)) ?? media) } }
                    var result: [(Int, Media)] = []; for await value in group { result.append(value) }; return result
                }
                guard !Task.isCancelled, owner == (app.user?.id ?? "guest"), customization.layout.heroSource == source.id, currentSignature == signature else { return }
                selected = fetched.sorted { $0.0 < $1.0 }.map(\.1)
            }
    }
}
