import SwiftUI

struct MetadataSettingsView: View {
    @Bindable var preferences = MetadataPreferences.shared
    @State private var key = ""
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section("TMDB") {
                SecureField("Clave API", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Guardar y comprobar") { Task {
                    guard !busy else { return }
                    busy = true
                    defer { busy = false }
                    do {
                        var configuration = preferences.configuration(); configuration.tmdbKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !configuration.tmdbKey.isEmpty else { throw HarborError(code: "metadata-not-configured") }
                        _ = try await TMDBService().page(TMDBService().definitions("movie")[0], page: 1, configuration: configuration)
                        try preferences.save(key); message = "TMDB conectado."
                    } catch { message = safeMessage(error) }
                } }.disabled(busy)
                if busy { ProgressView("Comprobando TMDB…") }
                if !preferences.tmdbKey.isEmpty { Button("Desconectar TMDB", role: .destructive) { do { try preferences.save(""); key = ""; message = nil } catch { message = safeMessage(error) } } }
                Text("Usa la misma clave que configuraste en Harbor Desktop. TMDB aporta tendencias, estrenos, carteles, logos y fichas; tus addons proporcionan las fuentes.").font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption) }
                if let error = preferences.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("Contenido") {
                Picker("Región", selection: $preferences.region) { ForEach(["US", "ES", "GB", "FR", "DE", "IT", "PT", "MX", "AR", "BR", "JP"], id: \.self) { Text(Locale.current.localizedString(forRegionCode: $0) ?? $0).tag($0) } }
                Picker("Idioma de metadata", selection: $preferences.language) { Text("Español").tag("es-ES"); Text("Inglés").tag("en-US"); Text("Francés").tag("fr-FR"); Text("Japonés").tag("ja-JP"); Text("Portugués").tag("pt-BR") }
                Toggle("Traducir títulos", isOn: $preferences.translateTitles)
            }
        }.navigationTitle("Metadata").navigationBarTitleDisplayMode(.inline).onAppear { key = preferences.tmdbKey }
    }
}
