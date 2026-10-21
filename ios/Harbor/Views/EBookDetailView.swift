import SwiftUI

struct EBookDetailView: View {
    let book: EBook
    let shelf: EBookShelf
    @Environment(\.readingPlugins) private var reading
    @State private var current: EBook
    @State private var expanded = false
    @State private var loading = false
    @State private var error: String?
    @State private var retry = UUID()
    init(book: EBook, shelf: EBookShelf) {
        self.book = book; self.shelf = shelf
        var primary = book; primary.alternativeSources = nil
        _current = State(initialValue: primary)
    }
    private var sources: [EBook] { book.alternativeSources ?? [book] }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actions
                if sources.count > 1 { sourcePicker }
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
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).navigationTitle(current.title).navigationBarTitleDisplayMode(.inline)
            .task(id: current.id + retry.uuidString) { await detail() }
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
    private var read: some View {
        NavigationLink { BookReaderDestination(book: current, shelf: shelf) } label: {
            Label(text(shelf.record(current) == nil ? "Read" : "Continue reading"), systemImage: "book.pages").frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.borderedProminent).tint(HarborTheme.accent).accessibilityIdentifier("ebook-detail-read")
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
                    var next = source; next.alternativeSources = nil
                    current = next; error = nil
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
        let values = [attribute(raw, "status", name: "Status"), attribute(raw, "originalLanguage", name: "Original language"), attribute(raw, "year", name: "Year"), attribute(raw, "chapters", name: "Chapters"), attribute(raw, "volumes", name: "Volumes"), attribute(raw, "score", name: "Rating"), attribute(raw, "pages", name: "Pages")].compactMap { $0 }
        if !values.isEmpty {
            VStack(spacing: 12) { ForEach(values, id: \.name) { value in HStack { Text(text(value.name)).foregroundStyle(.secondary); Spacer(); Text(value.value) } } }.font(.subheadline)
        }
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
        guard current.pluginID != nil, let reading else { return }
        let id = current.id, selected = current
        loading = true; error = nil
        defer { if current.id == id { loading = false } }
        do {
            let result = try await reading.ebookDetail(selected)
            try Task.checkCancellation()
            guard current.id == id else { return }
            current = result
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, current.id == id else { return }
            // Sources with no optional detail method remain readable from their catalog entry.
            if let failure = error as? HarborPluginRuntimeError, failure.detail.contains("no method: detail") { return }
            self.error = HarborPluginMessages.error(error)
        }
    }
}
