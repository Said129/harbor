import SwiftUI

struct EBookDetailView: View {
    let book: EBook
    let shelf: EBookShelf
    let candidates: [EBook]
    let app: AppModel?
    @Environment(\.readingPlugins) private var reading
    @State private var current: EBook
    @State private var expanded = false
    @State private var loading = false
    @State private var error: String?
    @State private var retry = UUID()
    @State private var resolved: [EBook] = []
    @State private var resolving = false
    init(book: EBook, shelf: EBookShelf, candidates: [EBook] = [], app: AppModel? = nil) {
        self.book = book; self.shelf = shelf; self.candidates = candidates; self.app = app
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
                listActions
                if let message = shelf.library.error {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button(text("Retry")) { shelf.library.reload() }
                }
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
                if current.readable && !current.isPDF { EBookChaptersView(book: current, shelf: shelf).id(current.id) }
                metadata
                if let reading { EBookRelatedView(book: book, shelf: shelf, manager: reading, candidates: candidates + sources, app: app) }
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
                try shelf.library.toggle(current, in: .saved)
            } catch { self.error = safeMessage(error) }
        } label: {
            Label(text(shelf.library.contains(current, in: .saved) ? "Bookmarked" : "Bookmark"), systemImage: shelf.library.contains(current, in: .saved) ? "bookmark.fill" : "bookmark").frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.bordered).disabled(!shelf.library.ready).accessibilityIdentifier("ebook-detail-save")
    }
    private var listActions: some View {
        HStack(spacing: 14) {
            ForEach([EBookLibraryList.favorites, .readLater], id: \.self) { list in
                let selected = shelf.library.contains(current, in: list)
                Button {
                    do { try shelf.library.toggle(current, in: list) } catch { self.error = safeMessage(error) }
                } label: {
                    Label(text(list.title), systemImage: list.symbol + (selected ? ".fill" : "")).font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).tint(selected ? HarborTheme.accent : .secondary).disabled(!shelf.library.ready)
                    .accessibilityAddTraits(selected ? [.isSelected] : []).accessibilityIdentifier("ebook-detail-list-" + list.rawValue)
            }
        }
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
        EBookInformationView(book: current)
        if let value = raw["siteUrl"].string, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link(text("More information"), destination: url) }
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
        do { _ = try await client.enrich([selected], onPartial: publish) } catch {}
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
