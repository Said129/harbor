import SwiftUI

struct SettingsView: View {
    let app: AppModel
    @State private var export: URL?
    @State private var error: String?
    @State private var query = ""
    private func matches(_ title: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || title.localizedCaseInsensitiveContains(term)
    }
    private var playerPages: [PlayerSettingsPage] { [PlayerSettingsPage.playback, .video, .audio, .subtitles].filter { matches($0.title) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HarborPageHeading(title: "Ajustes")
                HarborSearchField(prompt: "Buscar ajustes…", text: $query)
                if matches("Cuenta y configuración perfil Stremio") {
                    group("Cuenta y configuración") {
                        ProfileAccountButton(app: app, expanded: true).accessibilityIdentifier("settings-account").padding(14)
                    }
                }
                if !playerPages.isEmpty {
                    group("Reproducción") {
                        ForEach(playerPages) { page in
                            NavigationLink { PlayerSettingsView(page: page).toolbar(.visible, for: .navigationBar) } label: {
                                SettingsRow(title: page.title, icon: page.icon)
                            }.accessibilityIdentifier("settings-\(page.rawValue)")
                        }
                    }
                }
                if matches("Proveedores de metadata") || matches("Descargas y almacenamiento") {
                    group("Fuentes y biblioteca") {
                        if matches("Proveedores de metadata") {
                            NavigationLink { MetadataSettingsView().toolbar(.visible, for: .navigationBar) } label: { SettingsRow(title: "Proveedores de metadata", icon: "nav-catalogs") }
                        }
                        if matches("Descargas y almacenamiento") {
                            NavigationLink { DownloadsView(app: app).toolbar(.visible, for: .navigationBar) } label: { SettingsRow(title: "Descargas y almacenamiento", icon: "nav-download") }
                        }
                    }
                }
                if matches(DesktopInterfaceText.value("Colors") + " Temas") || matches(DesktopInterfaceText.value("Library") + " Interfaz navegación Home spoilers") {
                    group("Apariencia") {
                        if matches(DesktopInterfaceText.value("Colors") + " Temas") {
                            NavigationLink { ThemeSettingsView().toolbar(.visible, for: .navigationBar) } label: { SettingsRow(title: DesktopInterfaceText.value("Colors"), icon: "desktop-palette") }.accessibilityIdentifier("settings-theme")
                        }
                        if matches(DesktopInterfaceText.value("Library") + " Interfaz navegación Home spoilers") {
                            NavigationLink { InterfaceSettingsView().toolbar(.visible, for: .navigationBar) } label: { SettingsRow(title: DesktopInterfaceText.value("Library"), icon: "nav-settings") }.accessibilityIdentifier("settings-interface")
                        }
                    }
                }
                if matches("Diagnóstico y ayuda sistema logs compartir") {
                    group("Sistema y ayuda") {
                        Button { do { export = try Diagnostics.shared.export() } catch { self.error = safeMessage(error) } } label: { SettingsRow(title: "Preparar logs para compartir", icon: "ui-help") }
                        if let export { ShareLink(item: export) { SettingsRow(title: "Compartir logs", icon: "ui-help") } }
                        if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(14) }
                    }
                }
                Text("Harbor para iPhone · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(HarborTheme.background).buttonStyle(.plain).accessibilityIdentifier("settings-scroll")
            .navigationTitle("Ajustes").toolbar(.hidden, for: .navigationBar)
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(HarborTheme.font(14, weight: .semibold))
            VStack(alignment: .leading, spacing: 0, content: content).frame(maxWidth: .infinity, alignment: .leading).background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12))
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(icon).resizable().scaledToFit().frame(width: 19, height: 19).foregroundStyle(.secondary)
            Text(title).font(HarborTheme.font(14)).foregroundStyle(HarborTheme.ink)
            Spacer(minLength: 8)
            Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(.secondary)
        }.padding(.horizontal, 14).frame(minHeight: 54).contentShape(Rectangle())
    }
}
