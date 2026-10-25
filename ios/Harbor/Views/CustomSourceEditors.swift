import SwiftUI
import UniformTypeIdentifiers

struct CustomSourceImportView: View {
    let customization: PageCustomization
    private let expected: NavigationScope
    private let activation: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "url"
    @State private var url = ""
    @State private var raw = ""
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @FocusState private var focused: Bool
    @MainActor init(customization: PageCustomization) {
        self.customization = customization; expected = customization.scope; activation = AppProfileContext.shared.activationID
    }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(text("Add Custom Source"), selection: $mode) {
                        Text(text("JSON URL")).tag("url"); Text(text("Paste JSON")).tag("json")
                    }.pickerStyle(.segmented).accessibilityIdentifier("source-import-mode")
                    if mode == "url" {
                        TextField("https://example.com/sources.json", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().focused($focused).privacySensitive().accessibilityIdentifier("source-import-url")
                    } else {
                        TextEditor(text: $raw).font(.system(.caption, design: .monospaced)).frame(minHeight: 220)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).privacySensitive().accessibilityIdentifier("source-import-json")
                    }
                    Button(text("Import file")) { focused = false; importing = true }.accessibilityIdentifier("source-import-file")
                } footer: { Text(text("Provide a JSON link or paste it directly.")) }
                if let error { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("source-import-error") } }
                if busy { Section { ProgressView(text("Loading...")) } }
            }.scrollContentBackground(.hidden).background(HarborTheme.background).tint(HarborTheme.accent)
                .navigationTitle(text("Add Custom Source")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { operation?.cancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(text("Add Source"), action: save).disabled(busy).accessibilityIdentifier("source-import-save") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(text("Done")) { focused = false } }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                    do {
                        let files = try result.get()
                        guard let file = files.first else { throw HarborError(code: "custom-source-import") }
                        raw = try CustomSourceDocumentFile.read(file); mode = "json"; error = nil
                    } catch { self.error = text("Invalid SourceRow JSON format") }
                }.onDisappear { operation?.cancel() }
        }
    }
    private func save() {
        guard !busy else { return }; focused = false; error = nil; busy = true
        let value = mode == "url" ? url.trimmingCharacters(in: .whitespacesAndNewlines) : raw
        let fromURL = mode == "url"
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = text(fromURL ? "URL cannot be empty" : "JSON cannot be empty"); return }
                let contents: String
                if fromURL {
                    guard let parts = URLComponents(string: value), ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
                          parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { throw HarborError(code: "custom-source-import") }
                    let json = try await HTTPClient().sourceDocument(value)
                    contents = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
                } else { contents = value }
                try Task.checkCancellation()
                guard activation == AppProfileContext.shared.activationID else { throw HarborError(code: "account-changed") }
                _ = try customization.importSources(contents, expected: expected); dismiss()
            } catch is CancellationError { return }
            catch { self.error = text((error as? HarborError)?.code == "account-changed" ? "Profile changed. Please try again." : "Invalid SourceRow JSON format") }
        }
    }
}

struct SourceFolderImagesEditor: View {
    let row: DesktopSourceRow
    let folder: DesktopSourceFolder
    let customization: PageCustomization
    private let expected: NavigationScope
    private let activation: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var cover: String
    @State private var focus: String
    @State private var error: String?
    @MainActor init(row: DesktopSourceRow, folder: DesktopSourceFolder, customization: PageCustomization) {
        self.row = row; self.folder = folder; self.customization = customization; expected = customization.scope
        activation = AppProfileContext.shared.activationID
        _cover = State(initialValue: folder.cover ?? ""); _focus = State(initialValue: folder.focus ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(DesktopInterfaceText.value("Cover Image URL"), text: $cover).accessibilityIdentifier("source-cover-url")
                    TextField(DesktopInterfaceText.value("Focus GIF URL"), text: $focus).accessibilityIdentifier("source-focus-url")
                }.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if let error { Text(error).foregroundStyle(.orange) }
            }.scrollContentBackground(.hidden).background(HarborTheme.background).tint(HarborTheme.accent)
                .navigationTitle(DesktopInterfaceText.value("Edit Folder Images")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(DesktopInterfaceText.value("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(DesktopInterfaceText.value("Save")) {
                            do {
                                guard activation == AppProfileContext.shared.activationID else { throw HarborError(code: "account-changed") }
                                try customization.editSourceImages(rowID: row.id, folderID: folder.id, cover: cover, focus: focus, expected: expected); dismiss()
                            }
                            catch { self.error = safeMessage(error) }
                        }.accessibilityIdentifier("source-images-save")
                    }
                }
        }
    }
}
