import SwiftUI

struct HomeView: View {
    let model: AppModel
    @State private var customization: PageCustomization
    @MainActor init(model: AppModel) { self.model = model; _customization = State(initialValue: PageCustomization(owner: model.user?.id ?? "guest", page: "home")) }
    private var rails: [PageRail] { model.rows.filter { !$0.metas.isEmpty }.map(PageRail.catalog) }
    private var heroes: [Media] { model.heroes.isEmpty ? Array(model.rows.first(where: { !$0.metas.isEmpty })?.metas.prefix(5) ?? []) : model.heroes }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if model.user == nil {
                    Button { model.showAccount = true } label: {
                        Label("Inicia sesión para recuperar tus addons", systemImage: "person.crop.circle").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.accessibilityIdentifier("home-signin")
                }
                if let error = model.accountError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if customization.layout.cwTop { ContinueWatching(app: model) }
                if InterfacePreferences.shared.homeMode == "harbor" {
                    CustomizedHero(rails: rails, defaults: heroes, app: model, customization: customization)
                }
                if model.loading && model.rows.isEmpty { ProgressView("Cargando catálogos…").frame(maxWidth: .infinity).padding(40) }
                if let error = model.progressError {
                    VStack(alignment: .leading) {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("Reintentar lectura del progreso") { Task { await model.reloadProgress() } }
                    }.padding(.horizontal)
                }
                if let error = model.error, model.rows.isEmpty {
                    ContentUnavailableView { Label("No se pudo cargar Harbor", systemImage: "wifi.exclamationmark") } description: { Text(error).accessibilityIdentifier("home-error") } actions: {
                        Button("Reintentar") { Task { if model.storageReady { await model.loadHome() } else { await model.retryStartup() } } }
                    }
                } else if let error = model.error {
                    HStack { Text(error).font(.caption).foregroundStyle(.secondary); Button("Reintentar") { Task { await model.loadHome() } }.font(.caption) }.padding(.horizontal)
                }
                PageCustomizeButton(rails: rails, customization: customization)
                if let error = customization.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if !customization.layout.cwTop { ContinueWatching(app: model) }
                CustomizedRails(rails: rails, app: model, customization: customization)
                if model.storageReady && model.rows.isEmpty && !model.loading && model.error == nil {
                    ContentUnavailableView("Sin catálogos", systemImage: "puzzlepiece.extension", description: Text("Instala o activa un addon con catálogos."))
                }
            }.padding(.bottom, 24)
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.loadHome() }
            .accessibilityIdentifier("home-scroll")
    }
}
