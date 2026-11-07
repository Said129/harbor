import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Desktop "Your themes": saved themes with apply, rename, export and remove, plus save-current and import.
struct ThemeLibrarySection: View {
    @Bindable var preferences: ThemePreferences
    @State private var naming = false
    @State private var renaming: ThemeLibraryEntry?
    @State private var importing = false
    @State private var shareFile: ThemeShareFile?
    @State private var error: String?

    var body: some View {
        HarborSettingsSection(DesktopInterfaceText.value("Your themes")) {
            ForEach(preferences.library.entries) { entry in
                ThemeLibraryRow(
                    entry: entry,
                    apply: {
                        error = nil
                        preferences.applyLibraryTheme(entry)
                    },
                    export: { export(entry) },
                    remove: {
                        error = nil
                        preferences.removeLibraryTheme(id: entry.id)
                    },
                    rename: {
                        error = nil
                        renaming = entry
                    }
                )
            }
            HStack(spacing: 12) {
                Button(DesktopInterfaceText.value("Save theme")) {
                    error = nil
                    naming = true
                }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-library-save")
                Button(DesktopInterfaceText.value("Import a theme")) {
                    error = nil
                    importing = true
                }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-library-import")
            }
            if let error {
                Text(error).font(HarborTheme.font(15.5)).foregroundStyle(ThemePreferences.shared.color("danger"))
            }
        }
        .sheet(isPresented: $naming) {
            ThemeNameSheet(
                title: DesktopInterfaceText.value("Save theme"),
                initialName: "",
                confirmLabel: DesktopInterfaceText.value("Save theme")
            ) { name in
                try preferences.saveCurrentTheme(named: name)
            }
        }
        .sheet(item: $renaming) { entry in
            ThemeNameSheet(
                title: DesktopInterfaceText.value("Rename"),
                initialName: entry.name,
                confirmLabel: DesktopInterfaceText.value("Rename")
            ) { name in
                try preferences.renameLibraryTheme(id: entry.id, to: name)
            }
        }
        .sheet(item: $shareFile) { file in ThemeShareSheet(items: [file.url]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importFile(result)
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            error = DesktopInterfaceText.value("Could not read file")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = DesktopInterfaceText.value("Could not read file")
            return
        }
        switch ThemeFileCodec.decode(data) {
        case .failure(let problem):
            error = themeProblemText(problem)
        case .success(let imported):
            do {
                try preferences.importTheme(imported)
            } catch {
                self.error = themeProblemText(error)
            }
        }
    }

    private func export(_ entry: ThemeLibraryEntry) {
        error = nil
        let image = entry.hasBackground ? ThemeBackgroundStore.shared.read(ThemeBackgroundStore.name(for: entry.id)) : nil
        guard let data = try? ThemeFileCodec.encode(entry, imageData: image),
              let url = ThemeBackgroundStore.shared.exportFile(data, fileName: ThemeFileCodec.fileName(for: entry.name)) else {
            error = DesktopInterfaceText.value("Could not read file")
            return
        }
        shareFile = ThemeShareFile(url: url)
    }
}

/// Maps a validation failure to Desktop's English message, passed through DesktopInterfaceText.value.
private func themeProblemText(_ problem: Error) -> String {
    guard let problem = problem as? ThemeFileError else {
        return DesktopInterfaceText.value("Could not read file")
    }
    switch problem {
    case .unreadable:
        return DesktopInterfaceText.value("This file isn't a readable theme.")
    case .notATheme:
        return DesktopInterfaceText.value("This file isn't a Harbor theme.")
    case .missingName:
        return DesktopInterfaceText.value("Theme is missing a name.")
    case .invalidSwatch:
        return DesktopInterfaceText.value("This theme's preview colors look invalid.")
    case .missingColors:
        return DesktopInterfaceText.value("This theme is missing its colors.")
    case .missingColor(let key):
        return DesktopInterfaceText.value("This theme is missing a color ({color}).", variables: ["color": key])
    }
}

private struct ThemeLibraryRow: View {
    let entry: ThemeLibraryEntry
    let apply: () -> Void
    let export: () -> Void
    let remove: () -> Void
    let rename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(["canvas", "elevated", "accent", "ink"], id: \.self) { token in
                    Circle().fill(swatch(token)).frame(width: 18, height: 18)
                }
                Text(entry.name).font(HarborTheme.font(16.5, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
            }
            if !entry.blurb.isEmpty {
                Text(entry.blurb).font(HarborTheme.font(14)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button(DesktopInterfaceText.value("Apply"), action: apply)
                    .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-library-apply")
                Button(DesktopInterfaceText.value("Rename"), action: rename)
                    .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-library-rename")
                Button(DesktopInterfaceText.value("Export"), action: export)
                    .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-library-export")
                Button(DesktopInterfaceText.value("Remove"), action: remove)
                    .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-library-remove")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 10))
    }

    private func swatch(_ token: String) -> Color {
        guard let values = entry.tokens[token], values.count == 4 else { return .gray }
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values[3])
    }
}

/// Name entry for "Save theme" and "Rename". `onConfirm` throws ThemeFileError.missingName for an empty name.
private struct ThemeNameSheet: View {
    let title: String
    let initialName: String
    let confirmLabel: String
    let onConfirm: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(DesktopInterfaceText.value("Theme name")) {
                    TextField(DesktopInterfaceText.value("Name your theme"), text: $name)
                        .accessibilityIdentifier("theme-library-name")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(ThemePreferences.shared.color("danger"))
                    }
                }
            }
            .scrollContentBackground(.hidden).background(HarborTheme.background).tint(HarborTheme.accent)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DesktopInterfaceText.value("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel, action: save)
                        .accessibilityIdentifier("theme-library-name-confirm")
                }
            }
            .onAppear { if name.isEmpty { name = initialName } }
        }
    }

    private func save() {
        do {
            try onConfirm(name)
            dismiss()
        } catch {
            self.error = themeProblemText(error)
        }
    }
}

struct ThemeShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

@MainActor private struct ThemeShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
