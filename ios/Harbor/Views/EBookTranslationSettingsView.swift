import SwiftUI

struct EBookTranslationSettingsView: View {
    let owner: String
    @State private var settings = EBookTranslationSettings()
    @State private var ready = false
    @State private var testing = false
    @State private var task: Task<Void, Never>?
    @State private var message: String?
    @State private var failed = false
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        Form {
            Section(text("Translation")) {
                Picker(text("Translate to"), selection: $settings.targetLanguage) {
                    ForEach(InterfaceLanguage.all) { language in Text(language.nativeLabel).tag(language.code) }
                }.accessibilityIdentifier("ebook-translation-language")
                Text(text("Translation runs when a chapter opens and keeps the original if a request fails or is truncated.")).font(.caption).foregroundStyle(.secondary)
            }
            Section("DeepSeek") {
                Toggle(text("DeepSeek chapter translation"), isOn: $settings.enabled).accessibilityIdentifier("ebook-translation-enabled")
                Text(text("Sends only the chapter you open to DeepSeek. Volumes, chapters, and metadata stay unchanged.")).font(.caption).foregroundStyle(.secondary)
                Picker(text("Model"), selection: $settings.model) {
                    Text("DeepSeek V4 Flash").tag("deepseek-v4-flash")
                    Text("DeepSeek V4 Pro").tag("deepseek-v4-pro")
                    if !["deepseek-v4-flash", "deepseek-v4-pro"].contains(settings.model) { Text(settings.model).tag(settings.model) }
                }.accessibilityIdentifier("ebook-translation-model")
                SecureField(text("DeepSeek API key (sk-...)"), text: $settings.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("ebook-translation-key")
                Button(text("Test")) { test() }.disabled(!ready || testing || settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("ebook-translation-test")
                Button(text("Save")) {
                    do { try settings.save(owner: owner); failed = false; message = text("Saved") }
                    catch { failed = true; message = text("Translation failed") }
                }.disabled(!ready || testing).accessibilityIdentifier("ebook-translation-save")
                Link("DeepSeek Platform", destination: URL(string: "https://platform.deepseek.com/")!)
            }.disabled(!ready)
            if testing { ProgressView(text("Translation")).accessibilityIdentifier("ebook-translation-testing") }
            if let message { Text(message).foregroundStyle(failed ? Color.orange : Color.secondary).accessibilityIdentifier("ebook-translation-message") }
        }.navigationTitle(text("Translation")).navigationBarTitleDisplayMode(.inline)
            .task {
                do { settings = try EBookTranslationSettings.load(owner: owner); ready = true }
                catch { failed = true; message = text("Translation failed") }
            }
            .onDisappear { task?.cancel(); settings.apiKey = "" }
    }
    private func test() {
        guard ready, !testing else { return }
        let draft = settings; testing = true; message = nil; failed = false
        task = Task {
            defer { testing = false }
            do {
                let client = try EBookTranslationClient(owner: owner)
                _ = try await client.translate(source: "A quiet harbor welcomes every reader.", title: "Translation test", settings: draft, manual: true, cacheResult: false)
                try Task.checkCancellation(); message = text("DeepSeek model is working.")
            } catch is CancellationError { return }
            catch { failed = true; message = (error as? EBookTranslationError)?.errorDescription ?? text("Translation test failed") }
        }
    }
}
