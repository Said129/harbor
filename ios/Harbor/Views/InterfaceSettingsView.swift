import SwiftUI

struct InterfaceSettingsView: View {
    @Bindable var preferences = InterfacePreferences.shared
    var body: some View {
        Form {
            Section("Home") {
                Picker("Diseño", selection: $preferences.homeMode) { Text("Harbor").tag("harbor"); Text("Stremio clásico").tag("classic") }
                NavigationLink("Personalizar navegación") { NavigationSettingsView() }
            }
            Section("Carteles y fichas") {
                Toggle("Mostrar puntuación IMDb en carteles", isOn: $preferences.showImdbBadge)
                Toggle("Mostrar puntuación TMDB en carteles", isOn: $preferences.showTmdbBadge)
                Toggle("Mostrar botón de estado visto", isOn: $preferences.showWatchedButton)
            }
            Section("Episodios y spoilers") {
                Toggle("Mostrar descripción de episodios", isOn: $preferences.showEpisodeDescription)
                Toggle("Ocultar spoilers", isOn: $preferences.hideSpoilers)
                Toggle("Difuminar imágenes de episodios", isOn: $preferences.blurEpisodes).disabled(!preferences.hideSpoilers)
            }
        }.navigationTitle("Interfaz").navigationBarTitleDisplayMode(.inline)
    }
}

struct NavigationSettingsView: View {
    @Bindable var preferences = InterfacePreferences.shared
    var body: some View {
        List {
            Section("Secciones") {
                ForEach(preferences.orderedSections) { section in
                    HStack(spacing: 12) {
                        Image("nav-\(section.icon)").resizable().scaledToFit().frame(width: 24, height: 24)
                        TextField(section.title, text: Binding(get: { preferences.navigationNames[section.rawValue] ?? "" }, set: { preferences.navigationNames[section.rawValue] = $0 })).autocorrectionDisabled()
                        if section != .home && section != .settings {
                            Button {
                                if !preferences.navigationHidden.insert(section.rawValue).inserted { preferences.navigationHidden.remove(section.rawValue) }
                            } label: { Image(systemName: preferences.navigationHidden.contains(section.rawValue) ? "eye.slash" : "eye").frame(width: 36, height: 36) }.buttonStyle(.borderless).accessibilityLabel(preferences.navigationHidden.contains(section.rawValue) ? "Mostrar \(section.title)" : "Ocultar \(section.title)")
                        }
                    }
                }.onMove { offsets, destination in
                    var order = preferences.orderedSections.map(\.rawValue)
                    order.move(fromOffsets: offsets, toOffset: destination)
                    preferences.navigationOrder = order
                }
            }
            Section { Button("Restablecer navegación") { preferences.resetNavigation() } }
        }.navigationTitle("Navegación").navigationBarTitleDisplayMode(.inline).toolbar { EditButton() }
    }
}
