import Observation
import SwiftUI

struct EBookNoteSnapshot: Sendable {
    let document: EBookAnnotationDocument
    let chapterID: String
    let chapterLabel: String
    let volumeLabel: String
}
enum EBookNotesRoute: Identifiable {
    case list, selection(EBookNoteSnapshot, Int), edit(EBookAnnotation)
    var id: String { switch self { case .list: "list"; case .selection(let snapshot, let block): "select:" + snapshot.chapterID + ":" + String(block); case .edit(let note): "edit:" + note.id } }
}
@MainActor @Observable final class EBookReaderNotes {
    var route: EBookNotesRoute?
    var failure: String?
    private(set) var store: EBookAnnotationStore?
    private(set) var paint: [Int: [EBookAnnotationPaint]] = [:]
    private(set) var snapshot: EBookNoteSnapshot?
    private var documentID: UUID?
    private var ownerKey: String?
    private var generation = UUID()
    private let program = EBookAnnotationProgram()
    var ready: Bool { store?.ready == true }
    func canSelect(revision: UUID) -> Bool { ready && snapshot?.document.paragraphs.isEmpty == false && documentID == revision }
    func caption(for paint: [EBookAnnotationPaint]) -> String? {
        guard let id = paint.first?.id, let note = store?.items.first(where: { $0.id == id }) else { return nil }
        return note.title.isEmpty ? DesktopInterfaceText.value(note.reference ? "Reference" : note.body.isEmpty ? "Highlight" : "Note") : note.title
    }
    var revision: Int { store?.revision ?? 0 }
    func prepare(owner: String, book: String) async {
        let key = EBookShelf.hash(owner + "\u{0}" + book)
        if ownerKey != key { ownerKey = key; generation = UUID(); store = nil; route = nil; paint = [:]; snapshot = nil; documentID = nil; failure = nil }
        do { if store == nil { store = try EBookAnnotationStore(owner: owner, book: book) }; await store?.load() }
        catch { failure = DesktopInterfaceText.value("Error") }
    }
    func update(blocks: [EBookBlock], revision: UUID, chapterID: String, chapterLabel: String, volumeLabel: String) async {
        let epoch = generation
        do {
            let document: EBookAnnotationDocument
            if documentID == revision, let snapshot { document = snapshot.document }
            else { document = await EBookAnnotationDocument.make(blocks: blocks) }
            try Task.checkCancellation(); guard epoch == generation else { return }
            snapshot = .init(document: document, chapterID: chapterID, chapterLabel: chapterLabel, volumeLabel: volumeLabel); documentID = revision
            let next = try await program.paint(document, chapterID: chapterID, annotations: store?.items ?? [])
            try Task.checkCancellation(); guard epoch == generation else { return }; paint = next
        } catch is CancellationError { return }
        catch { paint = [:]; failure = DesktopInterfaceText.value("Error") }
    }
    func select(block: Int) { guard ready, let snapshot else { return }; failure = nil; route = .selection(snapshot, block) }
    func edit(_ id: String) { guard let note = store?.items.first(where: { $0.id == id }) else { return }; failure = nil; route = .edit(note) }
    func draft(_ selection: EBookAnnotationSelection, snapshot: EBookNoteSnapshot, reference: Bool = false, color: String? = nil) -> EBookAnnotation {
        var note = EBookAnnotation(chapterID: snapshot.chapterID, chapterLabel: snapshot.chapterLabel, volumeLabel: snapshot.volumeLabel, ranges: selection.ranges, text: selection.text)
        note.reference = reference; if let color { note.color = color }; return note
    }
    func save(_ note: EBookAnnotation) async {
        guard let store else { return }
        let epoch = generation
        do { try await store.save(note); if epoch == generation { route = nil; failure = nil } }
        catch { if epoch == generation { failure = DesktopInterfaceText.value("Error") } }
    }
    func remove(_ note: EBookAnnotation) async {
        guard let store else { return }
        let epoch = generation
        do { if store.items.contains(where: { $0.id == note.id }) { try await store.remove(note.id) }; if epoch == generation { route = nil; failure = nil } }
        catch { if epoch == generation { failure = DesktopInterfaceText.value("Error") } }
    }
}

struct EBookNotesPresentation: ViewModifier {
    @Bindable var notes: EBookReaderNotes
    let bookTitle: String
    let rtl: Bool
    let jump: (EBookAnnotation) -> Bool
    func body(content: Content) -> some View {
        content.sheet(item: $notes.route) { route in
            Group {
            if let store = notes.store {
                switch route {
                case .list: EBookNotesListView(store: store) { notes.route = .edit($0); notes.failure = nil }
                case .selection(let snapshot, let block):
                    EBookAnnotationSelectionView(document: snapshot.document, block: block, busy: store.busy, failure: notes.failure) { selection, action in
                        let note = notes.draft(selection, snapshot: snapshot, reference: action == "reference", color: action.hasPrefix("#") ? action : nil)
                        if action.hasPrefix("#") { Task { await notes.save(note) } }
                        else { notes.route = .edit(note) }
                    }
                case .edit(let note): EBookAnnotationEditorView(note: note, bookTitle: bookTitle, busy: store.busy, failure: notes.failure,
                    save: { value in Task { await notes.save(value) } }, remove: { Task { await notes.remove(note) } }, jump: { if jump(note) { notes.route = nil } else { notes.failure = DesktopInterfaceText.value("Error") } }).id(note.id)
                }
            } else { ProgressView() }
            }.environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        }
    }
}

struct EBookNotesListView: View {
    @Bindable var store: EBookAnnotationStore
    let selected: (EBookAnnotation) -> Void
    @Environment(\.dismiss) private var dismiss
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.busy { ProgressView() }
                    if let error = store.error { Text(error); Button(text("Retry")) { Task { await store.load() } } }
                    if store.ready && store.items.isEmpty { Text(text("Select a passage to add a highlight, note, or reference.")).foregroundStyle(.secondary).accessibilityIdentifier("ebook-notes-empty") }
                    ForEach(store.items) { note in
                        Button { selected(note) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Capsule().fill(Color(uiColor: EBookAnnotationStyle.color(note.color, alpha: note.density / 100))).frame(width: 40, height: 4)
                                HStack { Text(note.volumeLabel ?? text("Chapters")); Text(note.chapterLabel ?? text("Chapter")); Text(DesktopInterfaceText.value("Line {line}", variables: ["line": String((note.ranges.first?.line ?? 0) + 1)])) }.font(.caption2).foregroundStyle(.secondary)
                                Text(note.title.isEmpty ? text(note.reference ? "Reference" : note.body.isEmpty ? "Highlight" : "Note") : note.title).font(.subheadline.weight(.semibold))
                                Text(note.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                if !note.tags.isEmpty { Text(note.tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(16).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("ebook-note-card-" + note.id)
                    }
                }.padding(20)
            }.background(HarborTheme.background).navigationTitle(text("Notes & highlights")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(text("Close panel")) { dismiss() }.accessibilityIdentifier("ebook-notes-close") } }
        }
    }
}

struct EBookAnnotationEditorView: View {
    @State private var draft: EBookAnnotation
    @State private var tagText: String
    @State private var expandedQuote = false
    let bookTitle: String
    let busy: Bool
    let failure: String?
    let save: (EBookAnnotation) -> Void
    let remove: () -> Void
    let jump: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(note: EBookAnnotation, bookTitle: String, busy: Bool, failure: String?, save: @escaping (EBookAnnotation) -> Void, remove: @escaping () -> Void, jump: @escaping () -> Void) {
        _draft = State(initialValue: note); _tagText = State(initialValue: note.tags.joined(separator: ", ")); self.bookTitle = bookTitle; self.busy = busy; self.failure = failure; self.save = save; self.remove = remove; self.jump = jump
    }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(text(draft.reference ? "Reference passage" : "Highlighted passage")).font(.caption).foregroundStyle(HarborTheme.accent)
                    Text(draft.text).font(.title3).lineLimit(expandedQuote ? nil : 8).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: EBookAnnotationStyle.color(draft.color, alpha: draft.density / 100)), in: .rect(cornerRadius: 8)).accessibilityIdentifier("ebook-note-excerpt")
                    if draft.text.utf16.count > 400 { Button(text(expandedQuote ? "Show less" : "Show more")) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { expandedQuote.toggle() } } }
                    TextField(text("Title (optional)"), text: $draft.title).font(.title2).textFieldStyle(.roundedBorder).accessibilityIdentifier("ebook-note-title")
                    Text(text("Write here… nothing will interrupt you.")).font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.body).scrollContentBackground(.hidden).frame(minHeight: 180).padding(8).background(HarborTheme.surface, in: .rect(cornerRadius: 8)).accessibilityIdentifier("ebook-note-body")
                    Text(DesktopInterfaceText.value(draft.body.utf16.count == 1 ? "{count} character" : "{count} characters", variables: ["count": String(draft.body.utf16.count)])).font(.caption).foregroundStyle(.secondary)
                    Text(text("Ink colour")).font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(EBookAnnotation.inks, id: \.self) { ink in
                            Button { draft.color = ink } label: { Circle().fill(Color(uiColor: EBookAnnotationStyle.color(ink))).frame(width: 36, height: 36).padding(4).overlay(Circle().stroke(draft.color == ink ? .white : .clear, lineWidth: 2)) }
                                .accessibilityLabel(DesktopInterfaceText.value("Use {color} ink", variables: ["color": ink])).accessibilityIdentifier("ebook-note-ink-" + ink)
                        }
                    }
                    LabeledContent(text("Ink density"), value: "\(Int(draft.density))%")
                    Slider(value: $draft.density, in: 20...90, step: 5).accessibilityIdentifier("ebook-note-density")
                    Toggle(text("Reference"), isOn: $draft.reference).accessibilityIdentifier("ebook-note-reference")
                    Text(text(draft.reference ? "Marks every recurrence of this phrase" : "Saved to this passage")).font(.caption).foregroundStyle(.secondary)
                    TextField(text("study, character, quote"), text: $tagText).textFieldStyle(.roundedBorder).accessibilityLabel(text("Tags")).accessibilityIdentifier("ebook-note-tags")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: tagText) { _, value in draft.tags = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                    Text(bookTitle).font(.caption).foregroundStyle(.secondary)
                    Button(text("Go to passage"), action: jump).accessibilityIdentifier("ebook-note-jump")
                    if let failure { Text(failure).foregroundStyle(.orange).accessibilityIdentifier("ebook-note-error") }
                    HStack {
                        Button(text("Save")) { save(draft) }.buttonStyle(.borderedProminent).accessibilityIdentifier("ebook-note-save")
                        Button(role: .destructive, action: remove) { Label(text("Delete"), systemImage: "trash") }.buttonStyle(.bordered).accessibilityIdentifier("ebook-note-delete")
                    }.disabled(busy).frame(minHeight: 44)
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).navigationTitle(text(draft.reference ? "Reference" : "Annotation")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(text("Close")) { dismiss() }.accessibilityIdentifier("ebook-note-editor-close") } }
        }
    }
}
