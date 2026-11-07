import SwiftUI

/// Desktop's AI search (`components/search/ai-search-section.tsx`) as its own screen: describe what you want, the model
/// names titles, and each one is matched to a title in the installed catalogs. The search screen opens it (see the report for the one-line hook).
struct AISearchView: View {
    let app: AppModel
    @State private var query: String
    @State private var keys: AISearchKeyStore
    @State private var preferences = AISearchPreferences.load()
    @State private var searchRun = AISearchRun()

    @MainActor init(app: AppModel, initialQuery: String = "") {
        self.app = app
        _query = State(initialValue: initialQuery)
        _keys = State(initialValue: AISearchKeyStore.forOwner(app.personalOwner))
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasKey: Bool { !preferences.activeKey(keys).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HarborSearchField(prompt: DesktopInterfaceText.value("AI search"), text: $query, dismissOnSubmit: true)
                if !hasKey {
                    missingKeyNote
                } else if !trimmedQuery.isEmpty {
                    askButton
                }
                content
            }
            .padding()
        }
        .onSubmit { startSearch() }
        .background(HarborTheme.background)
        .navigationTitle(DesktopInterfaceText.value("AI search"))
        .task { try? keys.load() }
    }

    private var missingKeyNote: some View {
        Text(preferences.service == .groq
             ? DesktopInterfaceText.value("Add your Groq API key in Settings, AI search to use this model.")
             : DesktopInterfaceText.value("Add your OpenRouter API key in Settings, AI search to use this model."))
            .font(HarborTheme.font(13)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var askButton: some View {
        Button { startSearch() } label: {
            Text(DesktopInterfaceText.value("Ask AI to find titles for \"{query}\"", variables: ["query": trimmedQuery]))
                .font(HarborTheme.font(15, weight: .semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
                .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai-search-ask")
    }

    @ViewBuilder private var content: some View {
        if searchRun.ranQuery == trimmedQuery {
            switch searchRun.status {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(DesktopInterfaceText.value("Reading your search")).font(HarborTheme.font(14)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ai-search-loading")
            case .failed(let error):
                failureButton(error)
            case .done:
                if searchRun.results.isEmpty {
                    Text(DesktopInterfaceText.value("AI didn't find anything for that. Try rephrasing."))
                        .font(HarborTheme.font(14)).foregroundStyle(.secondary)
                } else {
                    resultsList
                }
            }
        }
    }

    private func failureButton(_ error: AISearchError) -> some View {
        Button { startSearch() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(DesktopInterfaceText.value("AI search failed. Tap to retry.")).font(HarborTheme.font(14, weight: .semibold))
                Text(error.message).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let detail = error.detail {
                    Text(detail).font(HarborTheme.font(12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai-search-failed")
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DesktopInterfaceText.value("AI picks"))
                .font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(searchRun.results) { result in
                resultRow(result)
            }
        }
    }

    private func resultRow(_ result: AISearchResult) -> some View {
        NavigationLink { DetailView(media: result.media, app: app) } label: {
            HStack(spacing: 12) {
                Poster(media: result.media, width: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.media.name).font(HarborTheme.font(16, weight: .semibold)).multilineTextAlignment(.leading)
                    if let line = episodeLine(result) {
                        Text(line).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.media.name)
        .accessibilityIdentifier("ai-search-result")
    }

    private func episodeLine(_ result: AISearchResult) -> String? {
        guard let season = result.season, let episode = result.episode else { return nil }
        let numbers = DesktopInterfaceText.value("S{s} · E{e}", variables: ["s": String(season), "e": String(episode)])
        guard let title = result.episodeTitle, !title.isEmpty else { return numbers }
        return numbers + " · " + title
    }

    private func startSearch() {
        Task { await searchRun.run(query: trimmedQuery, app: app, keys: keys, preferences: preferences) }
    }
}
