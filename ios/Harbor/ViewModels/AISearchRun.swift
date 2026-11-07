import Foundation
import Observation

/// One AI search: optional web context, the model's titles, then each title matched in the installed catalogs
/// (Desktop's `useAiSuggest`). A newer search makes older replies stale.
@MainActor @Observable final class AISearchRun {
    enum Status: Equatable { case idle, loading, done, failed(AISearchError) }

    private(set) var status: Status = .idle
    private(set) var results: [AISearchResult] = []
    private(set) var ranQuery = ""
    private var generation = 0

    func run(query: String, app: AppModel, keys: AISearchKeyStore, preferences: AISearchPreferences, transport: any AISearchTransport = AISearchHTTPTransport()) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = preferences.activeKey(keys)
        guard !text.isEmpty, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generation += 1
        let current = generation
        status = .loading
        results = []
        ranQuery = text
        let service = app.service
        let addons = app.addons
        do {
            var webContext: String?
            if preferences.webSearch {
                webContext = try? await AISearchWeb(transport: transport).context(for: text, jinaKey: keys.key(.jina))
            }
            let suggestions = try await AISearchClient(transport: transport).suggest(
                service: preferences.service, key: key, model: preferences.model, query: text, webContext: webContext
            )
            guard current == generation else { return }
            var found: [AISearchResult] = []
            if !suggestions.isEmpty {
                found = await AISearchResolver.resolve(suggestions) { title in
                    let providers = try await service.catalogProviders(addons)
                    let (rows, _) = try await service.catalogs(providers, search: title)
                    return rows.filter { $0.plan.kind != "addon_catalog" }.flatMap(\.metas)
                }
            }
            guard current == generation else { return }
            results = found
            status = .done
        } catch let error as AISearchError {
            guard current == generation else { return }
            status = .failed(error)
        } catch {
            guard current == generation else { return }
            status = .failed(AISearchError(failure: .unknown, detail: AISearchError.clippedDetail(error.localizedDescription)))
        }
    }
}
