import SwiftUI
import UniformTypeIdentifiers

/// The profile's own subtitle fonts, shown under the built-in choices: pick one, import another, remove one (Desktop's `FontPicker`).
/// mpv reads its font folder when a video opens, so a font imported now is drawn from the next video on.
struct SubtitleCustomFontChoices: View {
    @Binding var selection: String
    @State private var fonts: [SubtitleCustomFont] = []
    @State private var importing = false
    @State private var busy = false
    @State private var imported = false
    @State private var failure: String?
    @State private var confirming: SubtitleCustomFont?

    private var owner: String { MetadataPreferences.shared.settingsOwner ?? "guest" }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    private func removeTitle(_ name: String) -> String { DesktopInterfaceText.value("Remove {name}", variables: ["name": name]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !fonts.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(fonts) { font in
                        fontRow(font)
                    }
                }
            }
            Button { importing = true } label: {
                Label(text(busy ? "Importing font…" : "Import font"), systemImage: "square.and.arrow.down").frame(minHeight: 44)
            }
            .disabled(busy).accessibilityIdentifier("subtitle-font-import")
            Text("TTF · OTF · WOFF · WOFF2 · 32 MB").font(HarborTheme.font(12)).foregroundStyle(.secondary)
            if imported {
                Text(text("A new font applies the next time a video opens.")).font(HarborTheme.font(12)).foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure).font(HarborTheme.font(13)).foregroundStyle(.secondary)
            }
        }
        .task { await reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: false) { result in
            guard case .success(let files) = result, let file = files.first else { return }
            runImport(file)
        }
        .confirmationDialog(removeTitle(confirming?.name ?? ""), isPresented: confirmationBinding, titleVisibility: .visible) {
            Button(text("Remove"), role: .destructive) {
                if let font = confirming { remove(font) }
                confirming = nil
            }
            Button(text("Cancel"), role: .cancel) { confirming = nil }
        }
    }

    private static var importTypes: [UTType] {
        ["ttf", "otf", "woff", "woff2"].map { UTType(filenameExtension: $0) ?? UTType.data }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { shown in if !shown { confirming = nil } })
    }

    private func fontRow(_ font: SubtitleCustomFont) -> some View {
        let value = SubtitleFontSelection.selection(forID: font.id)
        let selected = selection == value
        return HStack(spacing: 6) {
            Button { selection = value } label: {
                Text(font.name).font(.custom(font.postScript, size: 16.5).weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? HarborTheme.accent : HarborTheme.ink.opacity(0.1), lineWidth: 1) }
            }
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("subtitle-font-" + font.id)
            Button { confirming = font } label: {
                Image(systemName: "xmark").frame(width: 44, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeTitle(font.name))
        }
    }

    private func reload() async {
        let owner = self.owner
        let listed = await Task.detached(priority: .utility) { () -> [SubtitleCustomFont] in
            SubtitleFontStore.shared.list(owner: owner)
        }.value
        fonts = listed
    }

    private func runImport(_ file: URL) {
        let owner = self.owner
        busy = true
        failure = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<SubtitleCustomFont, Error> in
                do {
                    return .success(try SubtitleFontStore.shared.importFont(from: file, owner: owner))
                } catch {
                    return .failure(error)
                }
            }.value
            busy = false
            switch outcome {
            case .success(let font):
                await reload()
                selection = SubtitleFontSelection.selection(forID: font.id)
                imported = true
            case .failure(let error):
                let tooLarge = (error as? HarborError)?.code == "subtitle-font-size"
                failure = text(tooLarge ? "That font is over 32 MB. Try a lighter file." : "That file is not a valid font.")
            }
        }
    }

    private func remove(_ font: SubtitleCustomFont) {
        let owner = self.owner
        Task {
            let remaining = await Task.detached(priority: .utility) { () -> [SubtitleCustomFont]? in
                do {
                    try SubtitleFontStore.shared.remove(id: font.id, owner: owner)
                    return SubtitleFontStore.shared.list(owner: owner)
                } catch {
                    return nil
                }
            }.value
            guard let remaining else {
                failure = text("Could not remove font.")
                return
            }
            fonts = remaining
            // Desktop: a removed font that was selected goes back to Inter.
            if selection == SubtitleFontSelection.selection(forID: font.id) { selection = SubtitleStyleFont.inter.rawValue }
        }
    }
}
