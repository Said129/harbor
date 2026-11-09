import SwiftUI

struct HomeView: View {
    let model: AppModel
    @State private var customization: PageCustomization
    @State private var seasonalPreferences: SpooktoberInvitationPreferences
    @State private var seasonalDate = Date()
    @State private var showSpooktober = false
    @State private var trakt: TraktHomeModel
    @AppStorage("uiLanguage") private var uiLanguage = "es"
    @Environment(\.scenePhase) private var scenePhase
    @MainActor init(model: AppModel) {
        self.model = model
        let owner = model.personalOwner
        _customization = State(initialValue: model.pageCustomization("home"))
        _seasonalPreferences = State(initialValue: SpooktoberInvitationPreferences(owner: owner))
        _trakt = State(initialValue: TraktHomeModel(app: model))
    }
    private var rails: [PageRail] {
        HomeCatalogFilter.homeLanguageRails(allRails, languages: InterfacePreferences.shared.homeLanguages)
    }
    private var allRails: [PageRail] {
        let showAll = classic || InterfacePreferences.shared.homeShowAllAddonRows
        let catalogs = AddonCatalogRules.discoveredRows(model.rows, showAll: showAll).map(PageRail.catalog)
        let sources = customization.sourceRows.map(PageRail.sources)
        let lists = CustomListHomeRows.selected(model.customLists.lists, ids: customization.listRowIDs).map(PageRail.list)
        guard !classic else { return sources + lists + catalogs }
        let built = (model.home.rows + model.home.animeRows).filter { !$0.metas.isEmpty }.map(PageRail.discovery)
        let takenNames = Set(built.map(HomeView.rowNameKey))
        let addonRails = HomeCatalogFilter.uniqueAddonRows(catalogs, takenKeys: takenNames, key: HomeView.rowNameKey, showAll: showAll)
        let traktRails: [PageRail] = trakt.rows.map(PageRail.discovery)
        let letterboxdRails: [PageRail] = StremboxdHomeModel.forOwner(model.personalOwner).rails.map(PageRail.discovery)
        let simklRails: [PageRail] = SimklHomeModel.forOwner(model.personalOwner).rails.map(PageRail.discovery)
        return sources + lists + traktRails + simklRails + letterboxdRails + built + addonRails
    }
    static func rowNameKey(_ rail: PageRail) -> String { AddonCatalogRules.normalizedName(rail.title, kind: rail.kind) }
    private var heroes: [Media] {
        if !classic && !model.home.heroes.isEmpty { return model.home.heroes }
        return model.heroes.isEmpty ? Array(model.rows.first(where: { !$0.metas.isEmpty })?.metas.prefix(5) ?? []) : model.heroes
    }
    private var homeRibbonMetas: [Media] {
        guard model.storageReady, !classic, let firstRow = customization.ordered(rails).first else { return [] }
        let heroSlides = HomeHeroSlides.displayedHome(rails: rails, defaults: heroes,
                                                       heroSourceID: customization.layout.heroSource,
                                                       feed: HeroLayoutPreferences.shared.feed)
        return HomeHeroSlides.topTen(firstRow: firstRow.metas, heroSlides: heroSlides)
    }
    private var homeRibbonRevision: [String] { homeRibbonMetas.map { $0.id + "|" + $0.name } }
    private func registerHomeRibbonMetas() {
        TopTenRibbonIndexStore.shared.replaceHomeTopTen(homeRibbonMetas,
                                                        profileActivationID: AppProfileContext.shared.activationID)
    }
    private var classic: Bool { InterfacePreferences.shared.homeMode == "classic" }
    private var loading: Bool { model.loading || (!classic && model.home.loading) }
    private var homeError: String? { (!classic ? model.home.error : nil) ?? model.error }
    private var contentSignature: String {
        let configuration = MetadataPreferences.shared.configuration()
        return [model.accountOperationScope, String(model.storageReady), String(classic), EBookShelf.hash(configuration.tmdbKey), configuration.language, configuration.region, String(configuration.translateTitles), StreamingPreferences.forOwner(model.settingsOwner).signature, model.addons.filter(\.enabled).map(\.id).joined(separator: "|")].joined(separator: "|")
    }
    private var traktSignature: String {
        [contentSignature, TraktAccountStore.forOwner(model.personalOwner).identity.uuidString, uiLanguage].joined(separator: "|")
    }
    /// Desktop's New Episodes row sits under Continue Watching, and only exists while its setting is on.
    @ViewBuilder private var newEpisodesRow: some View {
        if InterfacePreferences.shared.homeNewEpisodes { NewEpisodesRow(app: model) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let error = model.accountError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if classic || customization.layout.cwTop { ContinueWatching(app: model, excludesAnime: InterfacePreferences.shared.animeOnlyInAnimeRoom); newEpisodesRow }
                if InterfacePreferences.shared.homeMode == "harbor" {
                    CustomizedHero(rails: rails, defaults: heroes, app: model, customization: customization)
                }
                if loading && rails.isEmpty { HarborLoader().frame(maxWidth: .infinity).padding(40) }
                if SpooktoberSeason.available(seasonalDate) {
                    SpooktoberInvitation(preferences: seasonalPreferences) { showSpooktober = true }
                }
                if let error = model.progressError {
                    VStack(alignment: .leading) {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("Reintentar lectura del progreso") { Task { await model.reloadProgress() } }
                    }.padding(.horizontal)
                }
                if let error = homeError, rails.isEmpty {
                    VStack(spacing: 16) {
                        Image("harbor-mark").resizable().scaledToFit().frame(width: 44, height: 44).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(error).font(HarborTheme.font(13)).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("home-error")
                        Button("Reintentar") { Task { await refresh() } }.buttonStyle(HarborAccountButtonStyle())
                    }.padding(28).frame(maxWidth: .infinity)
                }
                PageCustomizeButton(rails: rails, customization: customization, cloud: model.harborIdentity.signedIn ? model.harborIdentity.page("home") : nil, listStore: model.customLists)
                if let error = customization.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if !classic && !customization.layout.cwTop { ContinueWatching(app: model, excludesAnime: InterfacePreferences.shared.animeOnlyInAnimeRoom); newEpisodesRow }
                CustomizedRails(rails: rails, app: model, customization: customization)
                if model.storageReady && model.customLists.ready && rails.isEmpty && !loading && homeError == nil {
                    HarborCatalogEmptyView(app: model).padding(.horizontal)
                }
            }.padding(.bottom, 24)
        }.customListArtwork(app: model, lists: model.customLists.lists).accessibilityIdentifier("home-scroll")
            .background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { PageEditingFooter(customization: customization) }
            .refreshable { await refresh() }
            .task(id: model.continuingDetectionSignature) { await model.detectContinuingAnime() }
            .task(id: model.settingsOwner) { await model.customLists.load() }
            .onChange(of: model.personalOwner) { _, owner in
                showSpooktober = false; seasonalPreferences = SpooktoberInvitationPreferences(owner: owner)
            }
            .onAppear(perform: registerHomeRibbonMetas)
            .onChange(of: homeRibbonRevision) { _, _ in registerHomeRibbonMetas() }
            .onChange(of: AppProfileContext.shared.activationID) { _, _ in registerHomeRibbonMetas() }
            .task(id: contentSignature) {
                guard model.storageReady, !classic else { return }
                async let curated: Void = model.home.load(app: model)
                async let anime: Void = model.home.loadAnime(owner: model.personalOwner)
                _ = await (curated, anime)
            }
            .task(id: traktSignature) {
                guard model.storageReady, !classic else { trakt.cancel(); return }
                if !trakt.isActive { trakt.cancel(); trakt = TraktHomeModel(app: model) }
                await trakt.load(configuration: MetadataPreferences.shared.configuration())
            }
            .sheet(isPresented: $showSpooktober) {
                NavigationStack {
                    SpooktoberView(app: model)
                        .navigationDestination(for: Media.self) { DetailView(media: $0, app: model) }
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showSpooktober = false } } }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    seasonalDate = Date()
                    if !SpooktoberSeason.available(seasonalDate) { showSpooktober = false }
                    else { _ = try? await SpooktoberUpdates.shared.refresh() }
                    do { try await Task.sleep(for: .seconds(SpooktoberSeason.nextCheck(seasonalDate))) }
                    catch { return }
                }
            }
    }
    private func refresh() async {
        guard model.storageReady else { await model.retryStartup(); return }
        async let catalogs: Void = model.loadHome()
        if !classic {
            async let curated: Void = model.home.load(app: model, refresh: true)
            async let anime: Void = model.home.loadAnime(owner: model.accountOperationScope, refresh: true)
            async let personal: Void = trakt.load(configuration: MetadataPreferences.shared.configuration(), force: true)
            _ = await (curated, anime, personal)
        }
        await catalogs
    }
}
