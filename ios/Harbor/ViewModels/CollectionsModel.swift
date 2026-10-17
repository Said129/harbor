import Foundation
import Observation

@MainActor @Observable
final class CollectionsModel {
    var items: [MovieCollection] = []
    var loading = false
    var error: String?
    var finished = false
    private var page = 1
    private var generation = 0
    func load(query: String, reset: Bool) async {
        if reset { generation += 1; page = 1; finished = false; items = [] }
        else if loading || finished { return }
        let current = generation
        loading = true; error = nil
        defer { if current == generation { loading = false } }
        do {
            if reset { try await Task.sleep(for: .milliseconds(350)) }
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await TMDBService().collections(query: value.isEmpty ? "collection" : value, page: page, configuration: MetadataPreferences.shared.configuration())
            try Task.checkCancellation()
            guard current == generation else { return }
            var seen = Set(items.map(\.id)); let fresh = result.items.filter { seen.insert($0.id).inserted }
            items.append(contentsOf: fresh)
            finished = page >= result.totalPages || result.items.isEmpty
            page += 1
        } catch is CancellationError { return }
        catch { if current == generation { self.error = safeMessage(error) } }
    }
}
