import SwiftUI

struct EBookMetadataSettingsView: View {
    let manager: HarborReadingPluginManager
    @State private var client: EBookMetadataClient?
    @State private var key = ""
    @State private var running = false
    @State private var message: String?
    @State private var failed = false
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        Form {
            Section("Google Books") {
                SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("ebook-google-key")
                Text("Opcional. La clave se guarda en el llavero de este perfil y se usa para consultar Google Books.").font(.caption).foregroundStyle(.secondary)
                Button(text("Save")) { act {
                    guard let client else { return }
                    try await client.saveGoogleKey(key); key = ""; message = text("Saved")
                } }.disabled(running || client == nil).accessibilityIdentifier("ebook-google-key-save")
                if client?.googleKey.isEmpty == false {
                    Button(text("Remove"), role: .destructive) { act { try await client?.saveGoogleKey(""); key = ""; message = text("Removed") } }.disabled(running)
                }
            }
            Section(text("Cache")) {
                Text("Los metadatos públicos guardados aceleran las próximas consultas. Vaciar esta caché conserva tus libros y el progreso.").font(.caption).foregroundStyle(.secondary)
                Button(text("Clear cache")) { act { try await client?.clearCache(); message = text("Cache cleared") } }.disabled(running || client == nil).accessibilityIdentifier("ebook-metadata-clear-cache")
            }
            if running { ProgressView(text("Loading")) }
            if let message { Text(message).foregroundStyle(failed ? Color.orange : Color.secondary).accessibilityIdentifier("ebook-metadata-message") }
        }.navigationTitle(text("Book metadata")).navigationBarTitleDisplayMode(.inline)
            .task { do { client = try manager.ebookMetadata() } catch { message = "No se pudieron abrir los ajustes de libros."; failed = true } }
            .onDisappear { key = "" }
    }
    private func act(_ action: @escaping @MainActor () async throws -> Void) {
        guard !running else { return }; running = true; message = nil; failed = false
        Task {
            defer { running = false }
            do { try await action() }
            catch is CancellationError { return }
            catch { failed = true; message = "No se pudo completar la operación. Comprueba la clave y la conexión." }
        }
    }
}
