import SwiftUI

struct SettingsView: View {
    let app: AppModel
    @State private var export: URL?
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("harbor-brand").resizable().frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 14))
                    VStack(alignment: .leading) {
                        Text("Harbor").font(.title2.bold())
                        Text("iPhone · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
            Section("Cuenta") {
                Button(app.user?.displayName ?? "Iniciar sesión en Stremio") { app.showAccount = true }
                    .accessibilityIdentifier("settings-account")
                if app.user != nil { Text("Tus addons se recuperan al iniciar sesión y al abrir Harbor.") }
            }
            Section("Reproductor") {
                ForEach([PlayerSettingsPage.playback, .video, .audio, .subtitles]) { page in
                    NavigationLink(page.title) { PlayerSettingsView(page: page) }
                        .accessibilityIdentifier("settings-\(page.rawValue)")
                }
            }
            Section("Contenido") { NavigationLink("Proveedores de metadata") { MetadataSettingsView() } }
            Section("Apariencia") {
                NavigationLink("Temas y colores") { ThemeSettingsView() }
                NavigationLink("Interfaz y navegación") { InterfaceSettingsView() }
            }
            Section("Diagnóstico") {
                Button("Preparar logs para compartir") { do { export = try Diagnostics.shared.export() } catch { self.error = safeMessage(error) } }
                if let export { ShareLink("Compartir logs", item: export) }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            Section("Harbor para iPhone") {
                Text("Versión de desarrollo de Harbor para iPhone.")
                Text("Instala tus addons para obtener sus catálogos y fuentes reales.")
            }
        }.navigationTitle("Ajustes")
    }
}
