import SwiftUI

@main
struct HarborApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { HomeView(model: model).navigationDestination(for: Media.self) { DetailView(media: $0, app: model) } }
                    .tabItem { Label("Home", systemImage: "house") }
                NavigationStack { SearchView(app: model).navigationDestination(for: Media.self) { DetailView(media: $0, app: model) } }
                    .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
                NavigationStack { AddonsView(app: model) }.tabItem { Label("Addons", systemImage: "puzzlepiece.extension") }
                NavigationStack { SettingsView() }.tabItem { Label("Ajustes", systemImage: "gearshape") }
            }
            .tint(HarborTheme.accent).preferredColorScheme(.dark)
            .task { await model.start() }
        }
    }
}
