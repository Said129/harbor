import SwiftUI

struct AddonDetailView: View {
    let app: AppModel
    let original: Addon
    private let owner: String
    @State private var currentID: String
    @State private var configurationLink = ""
    @State private var showConfiguration = false
    @State private var saving = false
    @State private var error: String?
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @MainActor init(app: AppModel, addon: Addon) {
        self.app = app; original = addon; owner = app.user?.id ?? "guest"
        _currentID = State(initialValue: addon.id)
    }
    private var addon: Addon { app.addons.first { $0.id == currentID } ?? original }
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AddonLogo(addon: addon, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(addon.name).font(.headline).accessibilityIdentifier("addon-detail-title")
                        if let version = addon.manifest["version"].string { Text(version).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let text = addon.manifest["description"].string { Text(String(text.prefix(20_000))).font(.subheadline) }
                if let host = URL(string: addon.transportUrl)?.host { Text(host).font(.caption).foregroundStyle(.secondary) }
            }
            Section("En este iPhone") {
                Toggle("Activar addon", isOn: Binding(get: { addon.enabled }, set: { enabled in
                    do { try app.setEnabled(addon, enabled); Task { await app.loadHome() } }
                    catch { self.error = safeMessage(error) }
                })).disabled(saving || app.accountBusy || !app.storageReady)
            }
            if addon.configurable {
                Section("Configuración") {
                    if addon.configurationURL != nil {
                        Button { showConfiguration = true } label: {
                            HStack {
                                Image("nav-settings").resizable().scaledToFit().frame(width: 20, height: 20)
                                Text("Configurar addon")
                            }
                        }.accessibilityIdentifier("addon-configure")
                    }
                    SecureField("Enlace del manifest configurado", text: $configurationLink)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("addon-configured-manifest")
                    Button("Guardar configuración") { save() }
                        .disabled(saving || app.accountBusy || configurationLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !app.storageReady)
                        .accessibilityIdentifier("addon-save-configuration")
                    if saving { ProgressView("Guardando configuración…") }
                    Text(app.user == nil ? "Configura el addon y guarda el enlace resultante aquí. Se conserva su lugar en la lista y se guarda en este iPhone." : "Configura el addon y guarda el enlace resultante aquí. Se conserva su lugar en la lista y se actualiza en tu cuenta.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.orange) } }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }.navigationTitle("Addon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() }.disabled(saving) } }
            .sheet(isPresented: $showConfiguration) {
                if let url = addon.configurationURL {
                    NavigationStack {
                        AddonConfigurationView(name: addon.name, url: url) { value in
                            configurationLink = value
                            message = "Enlace recibido. Pulsa Guardar configuración para aplicarlo."
                            error = nil
                        }
                    }.tint(HarborTheme.accent)
                }
            }
            .onChange(of: app.user?.id) { _, _ in dismiss() }
    }
    private func save() {
        guard !saving, owner == (app.user?.id ?? "guest") else { return }
        let id = currentID, link = configurationLink
        saving = true; error = nil; message = nil
        Task {
            defer { saving = false }
            do {
                let updated = try await app.reconfigure(id, url: link)
                guard owner == (app.user?.id ?? "guest") else { return }
                currentID = updated.id
                configurationLink = ""
                message = "Configuración guardada."
            } catch { self.error = safeMessage(error) }
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
