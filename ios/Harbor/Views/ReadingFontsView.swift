import CoreText
import SwiftUI
import UniformTypeIdentifiers

struct ReadingFontsView: View {
    let owner: String
    @Binding var font: String
    @Binding var selectedID: String
    @State private var fonts: [ReadingCustomFont] = []
    @State private var importing = false
    @State private var busy = false
    @State private var failure: String?
    @State private var operation: Task<Void, Never>?
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        List {
            Section {
                Button {
                    font = "literary"; selectedID = ""
                } label: { Label(text("Default"), systemImage: selectedID.isEmpty ? "checkmark.circle.fill" : "circle") }
                ForEach(fonts) { value in
                    Button { selectedID = value.id; font = "custom" } label: {
                        HStack {
                            Text(value.name).foregroundStyle(.primary)
                            Spacer()
                            if selectedID == value.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(HarborTheme.accent) }
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("reading-font-" + value.id).accessibilityLabel(value.name)
                        .accessibilityAddTraits(selectedID == value.id ? [.isSelected] : [])
                }.onDelete { indices in
                    let selected = indices.compactMap { fonts.indices.contains($0) ? fonts[$0] : nil }
                    operation?.cancel()
                    operation = Task {
                        do {
                            for value in selected {
                                try await ReadingFontStore.shared.remove(id: value.id, owner: owner)
                                if selectedID == value.id { font = "literary"; selectedID = "" }
                            }
                            fonts = try await ReadingFontStore.shared.list(owner: owner)
                        } catch { if !Task.isCancelled { failure = text("Could not remove font.") } }
                    }
                }
                Button { importing = true } label: { Label(text(busy ? "Importing font…" : "Import font"), systemImage: "square.and.arrow.down").frame(minHeight: 44) }
                    .disabled(busy).accessibilityIdentifier("reading-font-import")
            } footer: { Text("TTF · OTF · WOFF · WOFF2 · 32 MB") }
            if let failure { Section { Text(failure).font(.callout).foregroundStyle(.secondary) } }
            if !selectedID.isEmpty { Section(text("Preview")) { ReadingFontPreview(owner: owner, id: selectedID) } }
        }.navigationTitle(text("Custom font"))
            .task {
                do { fonts = try await ReadingFontStore.shared.list(owner: owner) }
                catch { if !Task.isCancelled { failure = text("Could not load fonts.") } }
            }
            .onDisappear { operation?.cancel() }
            .fileImporter(isPresented: $importing, allowedContentTypes: ["ttf", "otf", "woff", "woff2"].map { UTType(filenameExtension: $0) ?? .data }, allowsMultipleSelection: false) { result in
                guard case .success(let files) = result, let file = files.first else { return }
                operation?.cancel()
                operation = Task {
                    busy = true; failure = nil
                    defer { busy = false }
                    do {
                        let value = try await ReadingFontStore.shared.importFont(file, owner: owner)
                        let values = try await ReadingFontStore.shared.list(owner: owner)
                        try Task.checkCancellation(); fonts = values; selectedID = value.id; font = "custom"
                    } catch {
                        if !Task.isCancelled { failure = text((error as? HarborError)?.code == "reading-font-size" ? "That font is over 32 MB. Try a lighter file." : "That file is not a valid font.") }
                    }
                }
            }
    }
}

private struct ReadingFontPreview: View {
    let owner: String
    let id: String
    @State private var graphic: CGFont?
    var body: some View {
        Group {
            if let graphic {
                Text("Harbor · Aa Bb Cc 0123456789\nEspañol · العربية · 日本語")
                    .font(Font(CTFontCreateWithGraphicsFont(graphic, 22, nil, nil))).padding(.vertical, 12).accessibilityIdentifier("reading-font-preview")
            } else { ProgressView(DesktopInterfaceText.value("Loading font…")) }
        }
            .task(id: id) {
                graphic = nil
                guard let data = try? await ReadingFontStore.shared.data(id: id, owner: owner), !Task.isCancelled, let provider = CGDataProvider(data: data as CFData) else { return }
                graphic = CGFont(provider)
            }
    }
}
