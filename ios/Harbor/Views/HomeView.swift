import SwiftUI

struct HomeView: View {
    let model: AppModel
    @State private var customization: PageCustomization
    @State private var seasonalPreferences: SpooktoberInvitationPreferences
    @State private var seasonalDate = Date()
    @State private var showSpooktober = false
    @Environment(\.scenePhase) private var scenePhase
    @MainActor init(model: AppModel) {
        self.model = model
        let owner = model.user?.id ?? "guest"
        _customization = State(initialValue: PageCustomization(owner: owner, page: "home"))
        _seasonalPreferences = State(initialValue: SpooktoberInvitationPreferences(owner: owner))
    }
    private var rails: [PageRail] {
        let catalogs = model.rows.filter { !$0.metas.isEmpty }.map(PageRail.catalog)
        guard !classic else { return catalogs }
        let built = (model.home.rows + model.home.animeRows).filter { !$0.metas.isEmpty }.map(PageRail.discovery)
        var names = Set(built.map { $0.kind + "|" + $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return built + catalogs.filter { names.insert($0.kind + "|" + $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }
    }
    private var heroes: [Media] {
        if !classic && !model.home.heroes.isEmpty { return model.home.heroes }
        return model.heroes.isEmpty ? Array(model.rows.first(where: { !$0.metas.isEmpty })?.metas.prefix(5) ?? []) : model.heroes
    }
    private var classic: Bool { InterfacePreferences.shared.homeMode == "classic" }
    private var loading: Bool { model.loading || (!classic && model.home.loading) }
    private var homeError: String? { (!classic ? model.home.error : nil) ?? model.error }
    private var contentSignature: String {
        let configuration = MetadataPreferences.shared.configuration()
        return [model.user?.id ?? "guest", String(model.storageReady), String(classic), EBookShelf.hash(configuration.tmdbKey), configuration.language, configuration.region, String(configuration.translateTitles), model.addons.filter(\.enabled).map(\.id).joined(separator: "|")].joined(separator: "|")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let error = model.accountError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if classic || customization.layout.cwTop { ContinueWatching(app: model) }
                if InterfacePreferences.shared.homeMode == "harbor" {
                    CustomizedHero(rails: rails, defaults: heroes, app: model, customization: customization)
                }
                if loading && rails.isEmpty { HarborLoader().frame(maxWidth: .infinity).padding(40) }
                if SpooktoberSeason.available(seasonalDate) && !seasonalPreferences.dismissed {
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
                } else if let error = homeError {
                    HStack { Text(error).font(.caption).foregroundStyle(.secondary); Button("Reintentar") { Task { await refresh() } }.font(.caption) }.padding(.horizontal)
                }
                PageCustomizeButton(rails: rails, customization: customization)
                if let error = customization.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if !classic && !customization.layout.cwTop { ContinueWatching(app: model) }
                CustomizedRails(rails: rails, app: model, customization: customization)
                if model.storageReady && rails.isEmpty && !loading && homeError == nil {
                    HarborCatalogEmptyView(app: model).padding(.horizontal)
                }
            }.padding(.bottom, 24)
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
            .refreshable { await refresh() }
            .task(id: contentSignature) {
                guard model.storageReady, !classic else { return }
                async let curated: Void = model.home.load(app: model)
                async let anime: Void = model.home.loadAnime(owner: model.user?.id ?? "guest")
                _ = await (curated, anime)
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
            .accessibilityIdentifier("home-scroll")
    }
    private func refresh() async {
        guard model.storageReady else { await model.retryStartup(); return }
        async let catalogs: Void = model.loadHome()
        if !classic {
            async let curated: Void = model.home.load(app: model, refresh: true)
            async let anime: Void = model.home.loadAnime(owner: model.user?.id ?? "guest", refresh: true)
            _ = await (curated, anime)
        }
        await catalogs
    }
}
