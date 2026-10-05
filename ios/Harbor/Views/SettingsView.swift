import SwiftUI

struct SettingsView: View {
    let app: AppModel
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("resumePrompt") private var resumePrompt = false
    @AppStorage("mpvHwdec") private var hardwareDecoding = HardwareDecoding.auto
    @State private var export: URL?
    @State private var error: String?
    var body: some View {
        Form {
            Section("Cuenta") {
                Button(app.user?.displayName ?? "Iniciar sesión en Stremio") { app.showAccount = true }
                    .accessibilityIdentifier("settings-account")
                if app.user != nil { Text("Tus addons se recuperan al iniciar sesión y al abrir Harbor.") }
            }
            Section("Reproducción") {
                Picker("Decodificación de vídeo", selection: $hardwareDecoding) {
                    ForEach(HardwareDecoding.allCases) { mode in Text(mode.title).tag(mode) }
                }.accessibilityIdentifier("settings-hwdec")
                Text("Usa Software si una fuente presenta errores de imagen. También puedes cambiarlo desde el reproductor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Reanudación") {
                Toggle("Reanudar la reproducción", isOn: $resumePlayback)
                Toggle("Preguntar antes de reanudar", isOn: $resumePrompt).disabled(!resumePlayback)
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
