import SwiftUI

@main
struct HarborApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { HomeView(model: model).navigationDestination(for: Media.self) { DetailView(media: $0, app: model) } }
                    .tabItem { Label("Home", image: "nav-home") }
                NavigationStack { CatalogsView(app: model).navigationDestination(for: Media.self) { DetailView(media: $0, app: model) } }
                    .tabItem { Label("Catálogos", image: "nav-catalogs") }
                NavigationStack { SearchView(app: model).navigationDestination(for: Media.self) { DetailView(media: $0, app: model) } }
                    .tabItem { Label("Buscar", image: "nav-search") }
                NavigationStack { AddonsView(app: model) }.tabItem { Label("Addons", image: "nav-addons") }
                NavigationStack { SettingsView(app: model) }.tabItem { Label("Ajustes", image: "nav-settings") }
            }
            .tint(HarborTheme.accent).preferredColorScheme(.dark)
            .task { await model.start() }
            .sheet(isPresented: $model.showAccount) { NavigationStack { AccountView(app: model) } }
        }
    }
}
