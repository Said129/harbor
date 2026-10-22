import SwiftUI

struct EBookRelatedView: View {
    let book: EBook
    let shelf: EBookShelf
    let manager: HarborReadingPluginManager
    let candidates: [EBook]
    @State private var recommendations: [EBook] = []
    @State private var collections: [JSONValue] = []
    @State private var adaptations: JSONValue = .null
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(collections.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 14) {
                    Text(row["collection"]["name"].string ?? text("Collection")).font(.title3.weight(.semibold))
                    EBookGrid(books: EBookMetadataMapping.books(row["collection"]["books"], preserving: candidates), shelf: shelf, candidates: candidates)
                }
            }
            if !recommendations.isEmpty { Text(text("You may also like")).font(.title3.weight(.semibold)); EBookGrid(books: recommendations, shelf: shelf, candidates: candidates) }
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
            let url = row["siteUrl"].string.flatMap(URL.init(string:))
            HStack(spacing: 14) {
                AsyncImage(url: row["poster"].string.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(HarborTheme.surface) }
                    .frame(width: 48, height: 72).clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 6) {
                    if let url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link(title, destination: url) }
                    else { Text(title) }
                    let description = [row["format"].string, row["relation"].string, row["year"].integer.map(String.init)].compactMap { $0 }.joined(separator: " · ")
                    if !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
        }
    }
    private func load() async {
        guard let client = try? manager.ebookMetadata() else { return }
        let raw = EBookMetadataMapping.raw(book)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                do {
                    let value = try await client.query("recommendations", arguments: ["book": raw])
                    let linked = try await client.query("attach", arguments: ["books": value, "sources": .array(candidates.map(EBookMetadataMapping.raw))])
                    try Task.checkCancellation(); recommendations = EBookMetadataMapping.books(linked, preserving: candidates)
                } catch {}
            }
            group.addTask { @MainActor in
                do {
                    let value = try await client.query("collections", arguments: ["books": .array([raw])])
                    var linked: [JSONValue] = []
                    for row in value.array {
                        var fields = row.objectValue, collection = row["collection"].objectValue
                        collection["books"] = try await client.query("attach", arguments: ["books": row["collection"]["books"], "sources": .array(candidates.map(EBookMetadataMapping.raw))])
                        fields["collection"] = .object(collection); linked.append(.object(fields))
                    }
                    try Task.checkCancellation(); collections = linked
                } catch {}
            }
            group.addTask { @MainActor in
                do { let value = try await client.query("adaptations", arguments: ["book": raw]); try Task.checkCancellation(); adaptations = value } catch {}
            }
        }
    }
}
