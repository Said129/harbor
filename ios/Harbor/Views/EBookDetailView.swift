import SwiftUI

struct EBookDetailView: View {
    let book: EBook
    let shelf: EBookShelf
    let candidates: [EBook]
    @Environment(\.readingPlugins) private var reading
    @State private var current: EBook
    @State private var expanded = false
    @State private var loading = false
    @State private var error: String?
    @State private var retry = UUID()
    @State private var resolved: [EBook] = []
    @State private var resolving = false
    init(book: EBook, shelf: EBookShelf, candidates: [EBook] = []) {
        self.book = book; self.shelf = shelf; self.candidates = candidates
        _current = State(initialValue: book.withoutAlternatives)
    }
    private var sources: [EBook] {
        var seen = Set<String>()
        return ((book.alternativeSources ?? [book]).filter(\.readable) + resolved).filter { seen.insert($0.id).inserted }
    }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actions
                if sources.count > 1 || !book.readable { sourcePicker }
                if resolving { ProgressView(text("Finding sources...")).font(.caption).frame(maxWidth: .infinity).accessibilityIdentifier("ebook-resolving-sources") }
                if !resolving && sources.isEmpty && !current.readable { Text(text("No sources found")).font(.caption).foregroundStyle(.secondary) }
                if loading { ProgressView().frame(maxWidth: .infinity).accessibilityLabel(text("Loading")) }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button(text("Retry")) { retry = UUID() }
                }
                if !current.description.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(text("About")).font(.title3.weight(.semibold))
                        Text(current.description).foregroundStyle(.secondary).lineLimit(expanded ? nil : 6).textSelection(.enabled)
                        Button(text(expanded ? "Show less" : "Read more")) { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
                    }
                }
                metadata
                if let reading { EBookRelatedView(book: book, shelf: shelf, manager: reading, candidates: candidates + sources) }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).navigationTitle(current.title).navigationBarTitleDisplayMode(.inline)
            .task(id: current.id + "|" + String(reading?.ready ?? false) + retry.uuidString) { await detail() }
            .task(id: book.id + "|" + String(reading?.ready ?? false) + retry.uuidString) { await resolveSources() }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            EBookCover(book: current, owner: shelf.owner).aspectRatio(2.0 / 3.0, contentMode: .fit).frame(width: 118).clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 10) {
                Text(current.title).font(.system(.title2, design: .serif).weight(.semibold)).textSelection(.enabled).accessibilityIdentifier("ebook-detail-title")
                if !current.authors.isEmpty { Text(current.authors.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary) }
                Text(current.source).font(.caption).foregroundStyle(.secondary)
                if let language = current.language { Text(Locale.current.localizedString(forLanguageCode: language) ?? language).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { read; save }
            VStack(spacing: 12) { read; save }
        }
    }
    @ViewBuilder private var read: some View {
        if current.readable {
            NavigationLink { BookReaderDestination(book: current, shelf: shelf).environment(\.readingPlugins, reading) } label: {
                Label(text(shelf.record(current) == nil ? "Read" : "Continue reading"), systemImage: "book.pages").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).tint(HarborTheme.accent).accessibilityIdentifier("ebook-detail-read")
        }
    }
    private var save: some View {
        Button {
            do {
                if shelf.record(current) == nil { try shelf.addImported(current) }
                else { try shelf.remove(current) }
            } catch { self.error = safeMessage(error) }
        } label: {
            Label(text(shelf.record(current) == nil ? "Save to shelf" : "Remove from shelf"), systemImage: shelf.record(current) == nil ? "bookmark" : "bookmark.fill").frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.bordered).accessibilityIdentifier("ebook-detail-save")
    }
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Sources")).font(.headline)
            ForEach(sources) { source in
                Button {
                    current = source.withoutAlternatives; error = nil
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.source).font(.subheadline.weight(.medium))
                            Text(source.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: current.id == source.id ? "checkmark.circle.fill" : "circle").foregroundStyle(current.id == source.id ? HarborTheme.accent : .secondary)
                    }.padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("ebook-detail-source-" + source.id)
            }
        }
    }
    @ViewBuilder private var metadata: some View {
        let raw = current.metadata ?? .null
        let genres = raw["genres"].array.compactMap(\.string)
        if !genres.isEmpty { Text(genres.map(text).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
        let keys = [("status", "Status"), ("originalLanguage", "Original language"), ("year", "Year"), ("chapters", "Chapters"), ("volumes", "Volumes"), ("score", "Rating"), ("pages", "Pages"), ("editionCount", "Editions"), ("readerRating", "Reader rating"), ("readerRatingCount", "Ratings"), ("shelvedBy", "Readers"), ("archiveCopies", "Archive copies"), ("isbn", "ISBN")]
        let values = keys.compactMap { attribute(raw, $0.0, name: $0.1) }
        if !values.isEmpty {
            VStack(spacing: 12) { ForEach(values, id: \.name) { value in HStack { Text(text(value.name)).foregroundStyle(.secondary); Spacer(); Text(value.value) } } }.font(.subheadline)
        }
        ForEach(["people", "places", "periods", "languages"], id: \.self) { key in
            let values = raw[key].array.compactMap(\.string)
            if !values.isEmpty { Text(values.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
        }
        if let value = raw["siteUrl"].string, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link(text("More information"), destination: url) }
    }
    private struct Attribute { let name: String; let value: String }
    private func attribute(_ raw: JSONValue, _ key: String, name: String) -> Attribute? {
        switch raw[key] {
        case .string(let value) where !value.isEmpty: return .init(name: name, value: value)
        case .integer(let value): return .init(name: name, value: String(value))
        case .number(let value): return .init(name: name, value: value.formatted())
        default: return nil
        }
    }
    private func detail() async {
        guard let reading else { return }
        let id = current.id, selected = current
        loading = true; error = nil
        defer { if current.id == id { loading = false } }
        do {
            let result: EBook
            if selected.pluginID != nil { result = try await reading.ebookDetail(selected) }
            else if selected.id.hasPrefix("openlibrary:") || selected.id.hasPrefix("anilist:") {
                let raw = try await reading.ebookMetadata().query("detail", arguments: ["id": .string(id)])
                result = EBookMetadataMapping.detail(raw, preserving: selected)
            } else { result = selected }
            try Task.checkCancellation()
            guard current.id == id else { return }
            if selected.pluginID != nil, let client = try? reading.ebookMetadata() {
                let values = try await client.books("merge", arguments: ["books": .array([EBookMetadataMapping.raw(result)]), "metadata": .array([EBookMetadataMapping.raw(selected)])], preserving: [result])
                guard !Task.isCancelled, current.id == id else { return }
                current = values.first ?? result
            } else { current = result }
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, current.id == id else { return }
            // Sources with no optional detail method remain readable from their catalog entry.
            if !((error as? HarborPluginRuntimeError)?.detail.contains("no method: detail") ?? false) { self.error = HarborPluginMessages.error(error) }
        }
        if current.id == id { loading = false; await enrichDetail() }
    }
    private func enrichDetail() async {
        guard let reading, let client = try? reading.ebookMetadata() else { return }
        let selected = current, id = current.id
        func publish(_ books: [EBook]) async {
            guard !Task.isCancelled, current.id == id, let value = books.first else { return }
            current = value.withoutAlternatives
        }
        do { let result = try await client.enrich([selected], onPartial: publish); await publish(result) } catch {}
    }
    private func resolveSources() async {
        guard let reading else { return }
        resolving = true; defer { resolving = false }
        do {
            _ = try await reading.resolveEBook(book, candidates: candidates + shelf.records.map(\.book)) { rows in
                guard !Task.isCancelled else { return }
                resolved = rows
                if !current.readable, let first = rows.first { current = first.withoutAlternatives }
            }
        } catch is CancellationError { return }
        catch { if !Task.isCancelled && sources.isEmpty { self.error = "No se pudieron consultar las fuentes de lectura. Vuelve a intentarlo." } }
    }
}
