import SwiftUI

struct HarborReadingHTMLDraft: Identifiable {
    let id = UUID()
    var plugin: HarborInstalledReadingPlugin?
}

struct HarborReadingHTMLEditor: View {
    let manager: HarborReadingPluginManager
    let kind: HarborReadingPluginKind
    let draft: HarborReadingHTMLDraft
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var logo: String
    @State private var language: String
    @State private var raw: String
    @State private var error: String?
    @State private var saving = false
    @State private var operation: Task<Void, Never>?
    init(manager: HarborReadingPluginManager, kind: HarborReadingPluginKind, draft: HarborReadingHTMLDraft) {
        self.manager = manager; self.kind = kind; self.draft = draft
        let plugin = draft.plugin
        _name = State(initialValue: plugin?.entry.name ?? "")
        _logo = State(initialValue: plugin?.entry.icon ?? "")
        _language = State(initialValue: plugin?.entry.language ?? "all")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let existing = plugin?.entry.raw["htmlConfig"]
        let text = existing.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        _raw = State(initialValue: text ?? Self.example(kind))
    }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text("Source name"), text: $name).accessibilityIdentifier("reading-html-name")
                    TextField(text(kind == .manga ? "Logo URL (optional, auto-detected if blank)" : "Logo URL (optional)"), text: $logo).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker(text("Language"), selection: $language) {
                        Text(text("All languages")).tag("all")
                        ForEach(InterfaceLanguage.all, id: \.code) { item in Text(item.nativeLabel).tag(item.code) }
                    }
                }
                Section {
                    TextEditor(text: $raw).font(.system(.caption, design: .monospaced)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .frame(minHeight: 320).privacySensitive().accessibilityIdentifier("reading-html-config")
                } header: { Text(text("Configuration")) } footer: {
                    Text(text("Describe the site's lists, details and chapters using CSS selectors. Use {query} and {page} in the search and browse paths."))
                }
                if let error { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("reading-html-error") } }
                if saving { Section { ProgressView(text("Saving")) } }
            }.scrollContentBackground(.hidden).background(HarborTheme.background).tint(HarborTheme.accent)
                .navigationTitle(text(draft.plugin == nil ? "Add source" : "Edit source")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { operation?.cancel(); dismiss() }.accessibilityIdentifier("reading-html-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(text(draft.plugin == nil ? "Add source" : "Save changes"), action: save)
                            .disabled(saving || manager.busy).accessibilityIdentifier("reading-html-save")
                    }
                }
                .onDisappear { operation?.cancel() }
        }
    }
    private func save() {
        guard !saving else { return }; saving = true; error = nil
        operation = Task {
            defer { saving = false; operation = nil }
            do {
                try await manager.saveHTML(kind: kind, raw: raw, name: name, logo: logo, language: language, replacing: draft.plugin)
                try Task.checkCancellation(); dismiss()
            } catch is CancellationError { return }
            catch {
                if Task.isCancelled { return }
                if error is DecodingError || (error as? HarborPluginRuntimeError)?.code == "plugin-runtime" {
                    self.error = text(kind == .manga ? "That config is not valid. Check baseUrl, popularPath, list, chapters, and pages." : "The config is missing a required field.")
                } else { self.error = HarborPluginMessages.error(error) }
            }
        }
    }
    private static func example(_ kind: HarborReadingPluginKind) -> String {
        var value: [String: JSONValue] = [
            "name": .string("My Source"), "baseUrl": .string("https://example.org"),
            "popularPath": .string("/browse?page={page}"), "searchPath": .string("/search?q={query}&page={page}"),
            "list": .object(["item": .string("article.card"), "title": .string("a.title"), "link": .string("a@href"), "cover": .string("img@data-src|img@src")]),
            "detail": .object(["title": .string("h1"), "author": .string("a.author"), "cover": .string("img.poster@src"), "description": .string(".summary")]),
            "chapters": .object(["item": .string(".chapters a"), "title": .string("span.name"), "link": .string("@href")])]
        if kind == .manga { value["pages"] = .object(["image": .string(".reader img@src")]) }
        else { value["content"] = .object(["body": .string(".reader")]) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(JSONValue.object(value))).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
