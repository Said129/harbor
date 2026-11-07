import SwiftUI

/// Desktop's AI search settings (`settings/ai-search-section.tsx`): provider, model, keys, and the live web toggle.
/// The keys stay in the Keychain for this profile; the choices are saved on this device.
struct AISearchSettingsView: View {
    private let app: AppModel
    @State private var keys: AISearchKeyStore
    @State private var preferences = AISearchPreferences.load()
    @State private var drafts: [AISearchKeyStore.Key: String] = [:]
    @State private var savedKey: AISearchKeyStore.Key?
    @State private var customModel = ""

    @MainActor init(app: AppModel) {
        self.app = app
        _keys = State(initialValue: AISearchKeyStore.forOwner(app.personalOwner))
    }

    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection("AI search") {
                    providerBlock
                    modelBlock
                    customModelBlock
                    if preferences.service == .groq {
                        keyBlock(.groq, label: text("AI Search · Groq LPU inference"), placeholder: text("Groq API key (gsk-...)"))
                        keyNote(.groq)
                    } else {
                        keyBlock(.openRouter, label: text("AI Search · natural-language search"), placeholder: text("OpenRouter API key (sk-or-...)"))
                        keyNote(.openRouter)
                    }
                }
                HarborSettingsSection("Live web") {
                    liveWebBlock
                }
            }
            .padding()
        }
        .background(HarborTheme.background)
        .navigationTitle(text("AI search"))
        .task { loadKeys() }
    }

    // MARK: Provider and model

    private var providerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Provider")).font(HarborTheme.font(14, weight: .semibold))
            Text(text("Type what you want in plain language and let a model find it. Bring your own API key from either service."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HarborSettingsSegmented(selection: serviceBinding, choices: [("OpenRouter", AISearchService.openrouter), ("Groq", AISearchService.groq)])
        }
    }

    private var modelBlock: some View {
        let models = preferences.service == .groq ? AISearchCatalog.groqModels : AISearchCatalog.openRouterModels
        return HarborSettingsChoice(text("AI model"), selection: modelBinding, choices: models.map { ($0.label, $0.id) }, localizeChoices: false, identifier: "ai-search-model")
    }

    private var customModelBlock: some View {
        let groq = preferences.service == .groq
        return VStack(alignment: .leading, spacing: 10) {
            Text(text("Custom model id")).font(HarborTheme.font(14, weight: .semibold))
            Text(text(groq ? "Any model id from console.groq.com/docs/models works here." : "Any model id from openrouter.ai/models works here, including :free variants."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField(groq ? "llama-3.3-70b-versatile" : "vendor/model-name:free", text: $customModel)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(HarborTheme.font(15))
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
                Button(text("Use model")) { useCustomModel() }
                    .font(HarborTheme.font(15, weight: .semibold)).frame(minHeight: 44)
                    .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("ai-search-use-model")
            }
        }
    }

    private var serviceBinding: Binding<AISearchService> {
        Binding(get: { preferences.service }, set: { choose($0) })
    }

    private var modelBinding: Binding<String> {
        Binding(get: { preferences.resolvedModel }, set: { setModel($0) })
    }

    /// Desktop's `setTab`: keep the model when it already belongs to the new service, otherwise take that service's first model.
    private func choose(_ service: AISearchService) {
        guard service != preferences.service else { return }
        var next = preferences
        next.service = service
        if AISearchCatalog.service(for: preferences.model) != service {
            next.model = service == .groq ? (AISearchCatalog.groqModels.first?.id ?? "") : AISearchCatalog.defaultModel
        }
        preferences = next
        preferences.save()
    }

    private func setModel(_ id: String) {
        var next = preferences
        next.model = id
        preferences = next
        preferences.save()
    }

    private func useCustomModel() {
        let id = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        setModel(id)
        customModel = ""
    }

    // MARK: Keys

    private func keyBlock(_ key: AISearchKeyStore.Key, label: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(HarborTheme.font(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                SecureField(placeholder, text: draftBinding(key))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .font(HarborTheme.font(15)).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
                    .accessibilityIdentifier("ai-search-key-\(key.rawValue)")
                Button(text(savedKey == key ? "Saved" : "Save")) { save(key) }
                    .font(HarborTheme.font(15, weight: .semibold)).frame(minHeight: 44)
                    .accessibilityIdentifier("ai-search-save-\(key.rawValue)")
            }
        }
    }

    /// The help under a key field. Desktop writes the service's key page as a link.
    @ViewBuilder private func keyNote(_ key: AISearchKeyStore.Key) -> some View {
        let groq = key == .groq
        VStack(alignment: .leading, spacing: 6) {
            Text(text("Adds an \"Ask AI\" button to search, so you can type things like a plain-language request."))
            HStack(spacing: 4) {
                Text(text("Get a key at"))
                externalLink(groq ? "console.groq.com/keys" : "openrouter.ai/keys")
                Text(".")
            }
            Text(text(groq ? "Groq runs open-source models on its LPU hardware with a generous free tier; every model listed below runs on the free tier." : "It only runs when you tap that button, so it never costs anything unless you ask."))
        }
        .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func draftBinding(_ key: AISearchKeyStore.Key) -> Binding<String> {
        Binding(get: { drafts[key] ?? "" }, set: { drafts[key] = $0 })
    }

    private func loadKeys() {
        do {
            try keys.load()
            drafts = Dictionary(uniqueKeysWithValues: AISearchKeyStore.Key.allCases.map { ($0, keys.key($0)) })
        } catch {
            drafts = [:]
        }
    }

    private func save(_ key: AISearchKeyStore.Key) {
        do {
            try keys.set(drafts[key] ?? "", for: key)
            drafts[key] = keys.key(key)
            savedKey = key
            Task {
                try? await Task.sleep(for: .milliseconds(1_800))
                if savedKey == key { savedKey = nil }
            }
        } catch {
            savedKey = nil
        }
    }

    // MARK: Live web

    private var liveWebBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text("Jina Reader")).font(HarborTheme.font(14, weight: .semibold))
                Text(text("Augments AI picks with current web results before asking the model. Powered by") + " Jina Reader. " + text("Works without a key at low volume; add a key for higher quotas."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HarborSettingsToggle(text("Use live web context"), note: text("Fetches DuckDuckGo results and feeds top hits into the model prompt."), isOn: webBinding)
                .accessibilityIdentifier("ai-search-web")
            VStack(alignment: .leading, spacing: 10) {
                keyBlock(.jina, label: text("Jina API key (optional)"), placeholder: text("jina_..."))
                HStack(spacing: 4) {
                    Text(text("Get a key at"))
                    externalLink("jina.ai/reader")
                    Text(text("for higher rate limits; leave blank for the free anonymous tier."))
                }
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var webBinding: Binding<Bool> {
        Binding(get: { preferences.webSearch }, set: { value in
            var next = preferences
            next.webSearch = value
            preferences = next
            preferences.save()
        })
    }

    @ViewBuilder private func externalLink(_ address: String) -> some View {
        if let url = URL(string: "https://" + address) {
            Link(address, destination: url).font(HarborTheme.font(13, weight: .semibold))
        } else {
            Text(address)
        }
    }
}
