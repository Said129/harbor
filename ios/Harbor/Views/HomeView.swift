import SwiftUI

struct HomeView: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.user == nil {
                    Button { model.showAccount = true } label: {
                        Label("Inicia sesión para recuperar tus addons", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.accessibilityIdentifier("home-signin")
                }
                if let error = model.accountError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if let hero = model.rows.first?.metas.first {
                    NavigationLink(value: hero) {
                        GeometryReader { geometry in
                            ZStack(alignment: .bottomLeading) {
                                AsyncImage(url: (hero.background ?? hero.poster).flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.white.opacity(0.05)) }
                                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                    .accessibilityHidden(true)
                                LinearGradient(colors: [.clear, HarborTheme.background], startPoint: .top, endPoint: .bottom)
                                VStack(alignment: .leading) { Text("HARBOR").font(.caption.weight(.semibold)).tracking(4); Text(hero.name).font(.largeTitle.bold()) }.padding()
                            }.frame(width: geometry.size.width, height: geometry.size.height)
                        }.frame(height: 290).clipped().contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(hero.name)
                        .accessibilityIdentifier("home-hero")
                }
                if model.loading { ProgressView("Cargando catálogos…").frame(maxWidth: .infinity) }
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
                if !model.warnings.isEmpty { Text("Algunas solicitudes fallaron: \(model.warnings.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                CatalogRails(rows: model.rows)
                if model.storageReady && model.rows.isEmpty && !model.loading && model.error == nil {
                    ContentUnavailableView("Sin catálogos", systemImage: "puzzlepiece.extension", description: Text("Instala o activa un addon con catálogos."))
                }
            }.containerRelativeFrame(.horizontal, alignment: .leading).padding(.bottom, 24)
        }.background(HarborTheme.background).navigationTitle("Harbor").navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.loadHome() }
            .accessibilityIdentifier("home-scroll")
    }
}
