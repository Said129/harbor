import SwiftUI

struct HomeView: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if model.user == nil {
                    Button { model.showAccount = true } label: {
                        Label("Inicia sesión para recuperar tus addons", systemImage: "person.crop.circle").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.accessibilityIdentifier("home-signin")
                }
                if let error = model.accountError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if !model.heroes.isEmpty { CinemaHero(metas: model.heroes, app: model) }
                else if let media = model.rows.first(where: { !$0.metas.isEmpty })?.metas.first { CinemaHero(metas: [media], app: model) }
                if model.loading && model.rows.isEmpty { ProgressView("Cargando catálogos…").frame(maxWidth: .infinity).padding(40) }
                if let error = model.progressError {
                    VStack(alignment: .leading) {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("Reintentar lectura del progreso") { Task { await model.reloadProgress() } }
                    }.padding(.horizontal)
                }
                if let error = model.error {
                    ContentUnavailableView { Label("No se pudo cargar Harbor", systemImage: "wifi.exclamationmark") } description: { Text(error).accessibilityIdentifier("home-error") } actions: {
                        Button("Reintentar") { Task { if model.storageReady { await model.loadHome() } else { await model.retryStartup() } } }
                    }
                }
                ContinueWatching(app: model)
                CatalogRails(rows: model.rows.filter { !$0.metas.isEmpty }, app: model)
                if model.storageReady && model.rows.isEmpty && !model.loading && model.error == nil {
                    ContentUnavailableView("Sin catálogos", systemImage: "puzzlepiece.extension", description: Text("Instala o activa un addon con catálogos."))
                }
            }.padding(.bottom, 24)
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.loadHome() }
            .accessibilityIdentifier("home-scroll")
    }
}
