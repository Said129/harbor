import SwiftUI

/// Desktop's "Ask AI" entry in search (`search-overlay.tsx` shows it only when an AI key is saved): a link to the AI search
/// screen for the current query, hidden until the person has saved an OpenRouter or Groq key.
struct SearchAILink: View {
    let app: AppModel
    let query: String
    @State private var keys: AISearchKeyStore

    init(app: AppModel, query: String) {
        self.app = app
        self.query = query
        _keys = State(initialValue: AISearchKeyStore.forOwner(app.personalOwner))
    }

    private var hasKey: Bool { !keys.key(.openRouter).isEmpty || !keys.key(.groq).isEmpty }
    private var title: String { DesktopInterfaceText.value("Ask AI to find titles for \"{query}\"", variables: ["query": query]) }

    var body: some View {
        Group {
            if hasKey {
                NavigationLink { AISearchView(app: app, initialQuery: query) } label: {
                    Label(title, systemImage: "sparkles").lineLimit(2).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.padding(.horizontal).accessibilityIdentifier("search-ai")
            }
        }.task { if !keys.ready { try? keys.load() } }
    }
}
