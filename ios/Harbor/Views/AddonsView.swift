import SwiftUI

struct AddonsView: View {
    let app: AppModel
    @State private var url = ""
    @State private var error: String?
    @State private var installing = false
    @FocusState private var editingURL: Bool
    var body: some View {
        List {
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
                }.disabled(installing || url.isEmpty || !app.storageReady).accessibilityIdentifier("addon-install")
                if installing { ProgressView().accessibilityIdentifier("addon-install-progress") }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            Section("Instalados") {
                ForEach(app.addons) { addon in
                    Toggle(addon.name, isOn: Binding(get: { addon.enabled }, set: { enabled in
                        do { try app.setEnabled(addon, enabled); Task { await app.loadHome() } } catch { self.error = safeMessage(error) }
                    })).disabled(!app.storageReady)
                }
                .onDelete { offsets in do { try app.remove(offsets); Task { await app.loadHome() } } catch { self.error = safeMessage(error) } }
                .onMove { offsets, destination in do { try app.move(offsets, to: destination); Task { await app.loadHome() } } catch { self.error = safeMessage(error) } }
            }
        }.navigationTitle("Addons").toolbar { EditButton().disabled(!app.storageReady) }
    }
}
