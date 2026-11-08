import SwiftUI

@MainActor
struct MangaExtensionRepositoriesSection: View {
    let client: SuwayomiClient
    let onChanged: () async -> Void

    @State private var repositories: [MangaExtensionRepository]?
    @State private var input = ""
    @State private var busy = false
    @State private var refreshPending = false
    @State private var error: String?

    private static let suggestions = [
        (name: "Keiyoushi", description: "The largest community catalog", url: "https://github.com/keiyoushi/extensions"),
        (name: "Suwayomi", description: "Official Suwayomi extensions", url: "https://github.com/Suwayomi/tachiyomi-extension"),
    ]

    var body: some View {
        Group {
            if let repositories {
                Section(DesktopInterfaceText.value("Extension repositories")) {
                    ForEach(repositories) { repository in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(repository.name)
                                Text(repository.location).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { remove(repository) } label: {
                                Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(DesktopInterfaceText.value("Remove {name}", variables: ["name": repository.name]))
                        }
                    }
                    TextField("https://github.com/keiyoushi/extensions", text: $input)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { add(input) }
                    Button(DesktopInterfaceText.value("Add")) { add(input) }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(Self.suggestions.indices, id: \.self) { position in
                        let suggestion = Self.suggestions[position]
                        if let index = MangaExtensionRepository.indexURL(for: suggestion.url),
                           !repositories.contains(where: { $0.indexURL.caseInsensitiveCompare(index) == .orderedSame }) {
                            Button { add(suggestion.url) } label: {
                                VStack(alignment: .leading) {
                                    Text(suggestion.name)
                                    Text(DesktopInterfaceText.value(suggestion.description)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }.disabled(busy || refreshPending)
            }
            if busy { ProgressView() }
            if let error {
                Text(error).foregroundStyle(.orange)
                if refreshPending {
                    Button(DesktopInterfaceText.value("Retry")) { perform { await refreshAfterChange() } }.disabled(busy)
                } else if repositories == nil {
                    Button(DesktopInterfaceText.value("Retry")) { perform { await load() } }.disabled(busy)
                }
            }
        }.task { await load() }
    }

    private func load() async {
        do {
            let entries = try await client.extensionRepositories()
            try Task.checkCancellation()
            repositories = entries
        } catch is CancellationError {
        } catch {
            self.error = safeMessage(error)
        }
    }

    private func add(_ value: String) {
        guard !busy, !refreshPending else { return }
        guard let index = MangaExtensionRepository.indexURL(for: value) else {
            error = DesktopInterfaceText.value("That does not look like a repository URL")
            return
        }
        perform {
            do {
                try await client.addExtensionRepository(index)
                input = ""
                await refreshAfterChange()
            } catch {
                self.error = DesktopInterfaceText.value("The server could not load that repository")
            }
        }
    }

    private func remove(_ repository: MangaExtensionRepository) {
        guard !refreshPending else { return }
        perform {
            do {
                try await client.removeExtensionRepository(repository)
                await refreshAfterChange()
            } catch {
                self.error = safeMessage(error)
            }
        }
    }

    private func refreshAfterChange() async {
        refreshPending = true
        do {
            try await client.refreshExtensionIndex()
            refreshPending = false
            await onChanged()
            await load()
        } catch {
            await load()
            self.error = safeMessage(error)
        }
    }

    private func perform(_ action: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            await action()
            busy = false
        }
    }
}
