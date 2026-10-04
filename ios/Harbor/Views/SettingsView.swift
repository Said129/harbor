import SwiftUI

struct SettingsView: View {
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("resumePrompt") private var resumePrompt = false
    @State private var export: URL?
    @State private var error: String?
    var body: some View {
        Form {
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
