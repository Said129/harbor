import SwiftUI

struct AddonDetailView: View {
    let app: AppModel
    let original: Addon
    private let owner: String
    @State private var currentID: String
    @State private var configurationLink = ""
    @State private var showConfiguration = false
    @State private var saving = false
    @State private var confirmingRemoval = false
    @State private var error: String?
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @MainActor init(app: AppModel, addon: Addon) {
        self.app = app; original = addon; owner = app.user?.id ?? "guest"
        _currentID = State(initialValue: addon.id)
    }
    private var addon: Addon { app.addons.first { $0.id == currentID } ?? original }
    private var installed: Bool { app.addons.contains { $0.id == currentID } }
    private var blocked: Bool { saving || app.accountBusy || !app.storageReady || owner != (app.user?.id ?? "guest") }
    private var stats: [(String, String)] {
        [("Versión", addon.manifest["version"].string ?? "—"), ("Recursos", addon.resources.joined(separator: ", ")),
         ("Tipos", addon.types.joined(separator: ", ")), ("Prefijos de ID", addon.manifest["idPrefixes"].array.compactMap(\.string).prefix(3).joined(separator: ", ")),
         ("Catálogos", String(addon.manifest["catalogs"].array.count)), ("P2P", addon.manifest["behaviorHints"]["p2p"] == .bool(true) ? "Sí" : "No")]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top, spacing: 18) {
                    AddonLogo(addon: addon, size: 72)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(addon.name).font(.custom("Fraunces-9ptBlack", size: 30)).accessibilityIdentifier("addon-detail-title")
                        Text(addon.category.title).font(.subheadline).foregroundStyle(.secondary)
                        if let host = URL(string: addon.transportUrl)?.host { Text(host).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let text = addon.manifest["description"].string { Text(String(text.prefix(20_000))).font(.subheadline).foregroundStyle(HarborTheme.ink.opacity(0.75)) }
                actions
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Divider()
                Text("Información").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 22) {
                    ForEach(stats, id: \.0) { label, value in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(label.uppercased()).font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
                            Text(value.isEmpty ? "—" : value).font(.caption).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if addon.configurable { configuration }
            }.padding(22)
        }.background(HarborTheme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() }.disabled(saving) } }
            .confirmationDialog("Eliminar \(addon.name) de tus addons", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Eliminar addon", role: .destructive) { remove() }
            } message: { Text(app.user == nil ? "El addon se quitará de este iPhone." : "El addon se quitará también de tu colección de Stremio.") }
            .sheet(isPresented: $showConfiguration) {
                if let url = addon.configurationURL {
                    NavigationStack {
                        AddonConfigurationView(name: addon.name, url: url) { value in
                            guard owner == (app.user?.id ?? "guest") else { return }
                            configurationLink = value; message = "Enlace recibido. Pulsa Guardar configuración para aplicarlo."; error = nil
                        }
                    }.font(HarborTheme.font()).tint(HarborTheme.accent)
                }
            }.onChange(of: app.user?.id) { _, _ in dismiss() }
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if installed {
                    Toggle("Activar addon", isOn: Binding(get: { addon.enabled }, set: { enabled in
                        do { try app.setEnabled(addon, enabled); Task { await app.loadHome() } }
                        catch { self.error = safeMessage(error) }
                    })).font(.subheadline).disabled(blocked)
                } else if !addon.configurable {
                    Button("Instalar addon") { save(link: addon.transportUrl) }.buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(blocked).accessibilityIdentifier("addon-detail-install")
                }
            }
            HStack(spacing: 10) {
                if addon.configurationURL != nil {
                    Button { showConfiguration = true } label: { HStack { Image("nav-settings").resizable().scaledToFit().frame(width: 18, height: 18); Text("Configurar addon") } }
                        .buttonStyle(HarborAccountButtonStyle(primary: !installed)).disabled(blocked).accessibilityIdentifier("addon-configure")
                }
                if installed { Button("Eliminar") { confirmingRemoval = true }.buttonStyle(HarborAccountButtonStyle()).foregroundStyle(.red).disabled(blocked).accessibilityIdentifier("addon-remove") }
            }
            if saving { ProgressView("Guardando addon…") }
        }
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuración").font(.headline)
            SecureField("Enlace del manifest configurado", text: $configurationLink).font(HarborTheme.font(13)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("addon-configured-manifest")
            Button("Guardar configuración") { save(link: configurationLink) }.buttonStyle(HarborAccountButtonStyle(primary: true))
                .disabled(blocked || configurationLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("addon-save-configuration")
            Text(installed ? "Configura el addon y guarda el enlace resultante aquí. Se conserva su lugar en la lista." : "Configura el addon en su página y guarda el enlace resultante para instalarlo.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func save(link: String) {
        guard !blocked, let manifestID = original.manifest["id"].string else { return }
        let id = currentID, wasInstalled = installed
        saving = true; error = nil; message = nil
        Task {
            defer { saving = false }
            do {
                if wasInstalled {
                    let updated = try await app.reconfigure(id, url: link)
                    guard owner == (app.user?.id ?? "guest") else { return }
                    currentID = updated.id
                } else {
                    try await app.install(link, expectedManifestID: manifestID)
                    guard owner == (app.user?.id ?? "guest") else { return }
                    if let updated = app.addons.last(where: { $0.manifest["id"].string == manifestID }) { currentID = updated.id }
                }
                configurationLink = ""; message = wasInstalled ? "Configuración guardada." : "Addon instalado."
            } catch { guard owner == (app.user?.id ?? "guest") else { return }; self.error = safeMessage(error) }
        }
    }
    private func remove() {
        guard !blocked else { return }
        let id = currentID
        saving = true; error = nil; message = nil
        Task {
            defer { saving = false }
            do {
                guard owner == (app.user?.id ?? "guest"), let index = app.addons.firstIndex(where: { $0.id == id }) else { return }
                try await app.remove(IndexSet(integer: index))
                guard owner == (app.user?.id ?? "guest") else { return }
                dismiss()
            }
            catch { guard owner == (app.user?.id ?? "guest") else { return }; self.error = safeMessage(error) }
        }
    }
}

struct AddonLogo: View {
    let addon: Addon
    let size: CGFloat
    var body: some View {
        Group {
            if let url = addon.logoURL { Artwork(url: url, fit: .fit, maxPixels: 240, failureIcon: "nav-addons") }
            else { Image("nav-addons").resizable().scaledToFit().padding(size / 5).foregroundStyle(.secondary) }
        }.frame(width: size, height: size).clipShape(.rect(cornerRadius: size / 5)).accessibilityHidden(true)
    }
}
