import SwiftUI

struct EBookChaptersView: View {
    let book: EBook
    let shelf: EBookShelf
    @Environment(\.readingPlugins) private var reading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("harbor.ebook.chapterview") private var presentation = "grid"
    @State private var program = EBookDetailProgram()
    @State private var publication: EBookPublication?
    @State private var groups: [EBookVolume] = []
    @State private var selectedVolume: String?
    @State private var ordered: [EBookChapter] = []
    @State private var query = ""
    @State private var newest = false
    @State private var limit = 30
    @State private var loading = false
    @State private var failure: String?
    @State private var loadRequested = false
    @State private var retry = UUID()
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    private var automatic: Bool { book.pluginID != nil || book.id.hasPrefix("local:") }
    private var hasVolumes: Bool { groups.contains { !$0.volume.isEmpty } }
    private var selection: String { [selectedVolume ?? "<none>", query, String(newest), presentation].joined(separator: "\u{0}") }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !hasVolumes { Text(text("Chapters")).font(.title3.weight(.semibold)) }
            if loading { ProgressView(text("Loading chapters...")).frame(maxWidth: .infinity, minHeight: 64) }
            else if let failure {
                Text(failure).font(.callout).foregroundStyle(.secondary)
                Button(text("Retry")) { retry = UUID() }
            } else if publication == nil {
                Button(text("Chapters")) { loadRequested = true }.buttonStyle(.bordered).frame(minHeight: 44)
            } else {
                if hasVolumes { volumes }
                if hasVolumes && selectedVolume == nil { Text(text("Select a volume to see its chapters.")).font(.callout).foregroundStyle(.secondary).padding(.vertical, 20) }
                else { chapters }
            }
        }
            .task(id: String(reading?.ready ?? false) + String(loadRequested) + retry.uuidString) {
                if automatic || loadRequested { await load() }
            }
            .task(id: selection + String(publication != nil)) { await order() }
    }
    private var volumes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(text("Volumes")).font(.title3.weight(.semibold)); Text(String(groups.filter { !$0.volume.isEmpty }.count)).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155))], spacing: 12) {
                ForEach(groups) { group in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selectedVolume = group.volume }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(volumeLabel(group)).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(DesktopInterfaceText.value("{count} chapters", variables: ["count": String(group.chapters.count)])).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                            .background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedVolume == group.volume ? HarborTheme.accent : Color.secondary.opacity(0.2)))
                    }.buttonStyle(.plain).accessibilityAddTraits(selectedVolume == group.volume ? [.isSelected] : [])
                        .accessibilityIdentifier("ebook-volume-" + group.volume)
                }
            }
        }
    }
    private var chapters: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasVolumes { Text(text("Chapters")).font(.title3.weight(.semibold)) }
            ViewThatFits(in: .horizontal) {
                HStack { presentationPicker; sortPicker }
                VStack(alignment: .leading) { presentationPicker; sortPicker }
            }
            HarborSearchField(prompt: text("Search chapters..."), text: $query, dismissOnSubmit: true).accessibilityIdentifier("ebook-chapter-search")
            if ordered.isEmpty {
                Text(text(publication?.chapters.isEmpty == true ? "This source returned no chapters for this title." : "No chapters match your search.")).font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            } else if presentation == "list" {
                LazyVStack(spacing: 0) { ForEach(ordered.prefix(limit)) { chapter in chapterLink(chapter); Divider() } }
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 12))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                    ForEach(ordered.prefix(limit)) { chapter in chapterLink(chapter).background(HarborTheme.surface, in: .rect(cornerRadius: 12)) }
                }
            }
            if limit < ordered.count {
                HStack {
                    Button(text("Show more chapters")) { limit = min(limit + 30, ordered.count) }.buttonStyle(.bordered)
                    Spacer()
                    Button(text("Show all")) { limit = ordered.count }
                }.frame(minHeight: 44)
                Text(DesktopInterfaceText.value("{count} remaining", variables: ["count": String(ordered.count - limit)])).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var presentationPicker: some View {
        Picker(text("View"), selection: $presentation) {
            Label(text("List view"), systemImage: "list.bullet").tag("list")
            Label(text("Grid view"), systemImage: "square.grid.2x2").tag("grid")
        }.pickerStyle(.segmented).accessibilityIdentifier("ebook-chapter-view")
    }
    private var sortPicker: some View {
        Picker(text("Sort by"), selection: $newest) { Text(text("Oldest")).tag(false); Text(text("Newest")).tag(true) }
            .pickerStyle(.segmented).accessibilityIdentifier("ebook-chapter-sort")
    }
    private func chapterLink(_ chapter: EBookChapter) -> some View {
        NavigationLink {
            EBookReaderView(book: book, shelf: shelf, initialChapterID: chapter.path, initialPublication: publication).environment(\.readingPlugins, reading)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    if let number = chapter.number { Text(DesktopInterfaceText.value("Ch. {chapter}", variables: ["chapter": number])).font(.caption).foregroundStyle(.secondary) }
                    Text(chapter.sourceTitle ?? chapter.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    let facts = [chapter.publishAt, chapter.views.map { views in
                        let count = views.string ?? views.integer.map { $0.formatted() } ?? ""
                        return count.isEmpty ? "" : DesktopInterfaceText.value("{count} views", variables: ["count": count])
                    }].compactMap { $0 }.filter { !$0.isEmpty }
                    if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "book").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(14).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("ebook-chapter-" + chapter.path)
    }
    private func volumeLabel(_ group: EBookVolume) -> String {
        if group.volume.isEmpty { return text("Other") }
        if let number = group.number {
            let value = number.formatted(.number.grouping(.never))
            if group.label == "Volume " + value { return DesktopInterfaceText.value("Volume {number}", variables: ["number": value]) }
        }
        return group.label
    }
    private func load() async {
        guard !loading, publication == nil else { return }
        loading = true; failure = nil
        defer { loading = false }
        do {
            let value: EBookPublication
            if book.pluginID != nil {
                guard let reading, reading.ready else { return }
                value = try await reading.ebookPublication(book, allowEmpty: true)
            } else { value = try await EBookService.shared.open(book, owner: shelf.owner) }
            let groups = try await program.groups(value.chapters)
            try Task.checkCancellation(); self.groups = groups; publication = value
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { failure = safeMessage(error) } }
    }
    private func order() async {
        guard let publication else { return }
        let signature = selection
        do {
            let values = try await program.ordered(publication.chapters, volume: selectedVolume ?? "", query: query, newest: newest)
            try Task.checkCancellation(); guard selection == signature else { return }
            ordered = values; limit = 30
        } catch {}
    }
}
