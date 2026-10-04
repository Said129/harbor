import SwiftUI

struct AddonsView: View {
    let app: AppModel
    @State private var url = ""
    @State private var error: String?
    @State private var installing = false
    @FocusState private var editingURL: Bool
    var body: some View {
        List {
            if app.user != nil {
                Section { Text("Las instalaciones, eliminaciones y cambios de orden se guardan en tu cuenta de Stremio. Activar o desactivar un addon se aplica en este iPhone.").font(.caption) }
            }
            Section("Instalar desde URL") {
                SecureField("URL del manifest", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused($editingURL)
                    .accessibilityIdentifier("addon-manifest-url")
                Button("Instalar addon") {
                    editingURL = false
                    Task {
                        installing = true; error = nil
                        defer { installing = false }
                        do { try await app.install(url); url = "" } catch { self.error = safeMessage(error) }
                    }
                }.disabled(installing || app.accountBusy || url.isEmpty || !app.storageReady).accessibilityIdentifier("addon-install")
                if installing { ProgressView().accessibilityIdentifier("addon-install-progress") }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            Section("Instalados") {
                ForEach(app.addons) { addon in
                    Toggle(addon.name, isOn: Binding(get: { addon.enabled }, set: { enabled in
                        do { try app.setEnabled(addon, enabled); Task { await app.loadHome() } } catch { self.error = safeMessage(error) }
                    })).disabled(!app.storageReady || app.accountBusy)
                }
                .onDelete { offsets in Task { do { try await app.remove(offsets) } catch { self.error = safeMessage(error) } } }
                .onMove { offsets, destination in Task { do { try await app.move(offsets, to: destination) } catch { self.error = safeMessage(error) } } }
            }
        }.navigationTitle("Addons").toolbar { EditButton().disabled(!app.storageReady || app.accountBusy) }
    }
}
