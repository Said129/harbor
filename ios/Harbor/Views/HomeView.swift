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
    private var rails: [PageRail] { model.rows.filter { !$0.metas.isEmpty }.map(PageRail.catalog) }
    private var heroes: [Media] { model.heroes.isEmpty ? Array(model.rows.first(where: { !$0.metas.isEmpty })?.metas.prefix(5) ?? []) : model.heroes }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let error = model.accountError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if customization.layout.cwTop { ContinueWatching(app: model) }
                if InterfacePreferences.shared.homeMode == "harbor" {
                    CustomizedHero(rails: rails, defaults: heroes, app: model, customization: customization)
                }
                if model.loading && model.rows.isEmpty { ProgressView("Cargando catálogos…").frame(maxWidth: .infinity).padding(40) }
                if SpooktoberSeason.available(seasonalDate) && !seasonalPreferences.dismissed {
                    SpooktoberInvitation(preferences: seasonalPreferences) { showSpooktober = true }
                }
                if let error = model.progressError {
                    VStack(alignment: .leading) {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("Reintentar lectura del progreso") { Task { await model.reloadProgress() } }
                    }.padding(.horizontal)
                }
                if let error = model.error, model.rows.isEmpty {
                    VStack(spacing: 16) {
                        Image("harbor-mark").resizable().scaledToFit().frame(width: 44, height: 44).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(error).font(HarborTheme.font(13)).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("home-error")
                        Button("Reintentar") { Task { if model.storageReady { await model.loadHome() } else { await model.retryStartup() } } }.buttonStyle(HarborAccountButtonStyle())
                    }.padding(28).frame(maxWidth: .infinity)
                } else if let error = model.error {
                    HStack { Text(error).font(.caption).foregroundStyle(.secondary); Button("Reintentar") { Task { await model.loadHome() } }.font(.caption) }.padding(.horizontal)
                }
                PageCustomizeButton(rails: rails, customization: customization)
                if let error = customization.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if !customization.layout.cwTop { ContinueWatching(app: model) }
                CustomizedRails(rails: rails, app: model, customization: customization)
                if model.storageReady && model.rows.isEmpty && !model.loading && model.error == nil {
                    HarborCatalogEmptyView(app: model).padding(.horizontal)
                }
            }.padding(.bottom, 24)
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.loadHome() }
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
}
