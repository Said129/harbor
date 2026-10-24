import SwiftUI

private enum EBookRelatedResult: Sendable {
    case recommendations(JSONValue), collections([JSONValue]), adaptations(JSONValue)
}

struct EBookRelatedView: View {
    let book: EBook
    let shelf: EBookShelf
    let manager: HarborReadingPluginManager
    let candidates: [EBook]
    var app: AppModel? = nil
    @State private var recommendations: [EBook] = []
    @State private var collections: [JSONValue] = []
    @State private var adaptations: JSONValue = .null
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(collections.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 14) {
                    Text(row["collection"]["name"].string ?? text("Collection")).font(.title3.weight(.semibold))
                    EBookGrid(books: EBookMetadataMapping.books(row["collection"]["books"], preserving: candidates), shelf: shelf, manager: manager, candidates: candidates, app: app)
                }
            }
            if !recommendations.isEmpty { Text(text("You may also like")).font(.title3.weight(.semibold)); EBookGrid(books: recommendations, shelf: shelf, manager: manager, candidates: candidates, app: app) }
            ForEach(["manga", "anime", "liveAction"], id: \.self) { kind in
                let entries = adaptations[kind].array
                if !entries.isEmpty {
                    Text(text(kind == "liveAction" ? "Live action" : kind == "manga" ? "Manga" : "Anime")).font(.title3.weight(.semibold))
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, row in adaptation(row) }
                }
            }
        }.task(id: book.id) { await load() }
    }
    @ViewBuilder private func adaptation(_ row: JSONValue) -> some View {
        if let title = row["title"].string {
            if let app, ["anime", "manga"].contains(row["kind"].string ?? "") {
                NavigationLink { EBookAdaptationDestination(item: row, book: book, manager: manager, app: app) } label: { adaptationLabel(row, title: title) }
                    .buttonStyle(.plain).accessibilityIdentifier("ebook-adaptation-" + (row["id"].string ?? title))
            } else if let value = row["siteUrl"].string, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                Link(destination: url) { adaptationLabel(row, title: title) }
            } else { adaptationLabel(row, title: title) }
        }
    }
    private func adaptationLabel(_ row: JSONValue, title: String) -> some View {
        HStack(spacing: 14) {
                AsyncImage(url: row["poster"].string.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(HarborTheme.surface) }
                    .frame(width: 48, height: 72).clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                    let description = [row["format"].string, row["relation"].string, row["year"].integer.map(String.init)].compactMap { $0 }.joined(separator: " · ")
                    if !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
        }
    }
    @MainActor private func load() async {
        guard let client = try? manager.ebookMetadata() else { return }
        let raw = EBookMetadataMapping.raw(book)
        let sources: JSONValue = .array(candidates.map(EBookMetadataMapping.raw))
        await withTaskGroup(of: EBookRelatedResult.self) { group in
            group.addTask { @Sendable in
                do {
                    let value = try await client.query("recommendations", arguments: ["book": raw])
                    let linked = try await client.query("attach", arguments: ["books": value, "sources": sources])
                    return .recommendations(linked)
                } catch { return .recommendations(.array([])) }
            }
            group.addTask { @Sendable in
                do {
                    let value = try await client.query("collections", arguments: ["books": .array([raw])])
                    var linked: [JSONValue] = []
                    for row in value.array {
                        var fields = row.objectValue, collection = row["collection"].objectValue
                        collection["books"] = try await client.query("attach", arguments: ["books": row["collection"]["books"], "sources": sources])
                        fields["collection"] = .object(collection); linked.append(.object(fields))
                    }
                    return .collections(linked)
                } catch { return .collections([]) }
            }
            group.addTask { @Sendable in
                do { return .adaptations(try await client.query("adaptations", arguments: ["book": raw])) }
                catch { return .adaptations(.null) }
            }
            for await result in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                switch result {
                case .recommendations(let value): recommendations = EBookMetadataMapping.books(value, preserving: candidates)
                case .collections(let value): collections = value
                case .adaptations(let value): adaptations = value
                }
            }
        }
    }
}
