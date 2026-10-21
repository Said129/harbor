import SwiftUI

struct HarborReadingPluginManagementView: View {
    private enum Removal { case plugin(HarborInstalledReadingPlugin), repository(HarborReadingPluginRepository) }
    @Bindable var manager: HarborReadingPluginManager
    let kind: HarborReadingPluginKind
    @State private var tab = "plugins"
    @State private var link = ""
    @State private var query = ""
    @State private var failure: String?
    @State private var removal: Removal?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HarborSettingsSegmented(selection: $tab, choices: [(text("Plugins"), "plugins"), (text("Repositories"), "repositories")])
                HarborSearchField(prompt: text("Search"), text: $query)
                if let failure { Text(failure).font(HarborTheme.font(14)).foregroundStyle(ThemePreferences.shared.color("danger")) }
                if manager.busy { ProgressView() }
                if tab == "plugins" { installed }
                else { repositoryForm; repositories }
            }.padding(20).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tab)
            .accessibilityIdentifier("reading-plugin-management-" + kind.rawValue)
            .confirmationDialog(text("Remove"), isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                if let removal {
                    Button(text("Remove"), role: .destructive) {
                        act {
                            switch removal {
                            case .plugin(let plugin): try await manager.remove(plugin)
                            case .repository(let repository): try await manager.removeRepository(repository)
                            }
                        }; self.removal = nil
                    }.accessibilityIdentifier("reading-plugin-confirm-remove")
                }
                Button(text("Cancel"), role: .cancel) { removal = nil }
            }.onChange(of: manager.ready) { _, ready in if !ready { link = ""; failure = nil; removal = nil } }
    }
    private var installed: some View {
        Group {
            let plugins = manager.document.plugins.filter { $0.kind == kind && matches($0.entry.name + " " + $0.repositoryName) }
            if plugins.isEmpty { Text(text("Nothing installed yet")).foregroundStyle(.secondary).accessibilityIdentifier("reading-plugin-empty") }
            ForEach(plugins) { plugin in
                VStack(alignment: .leading, spacing: 14) {
                    heading(plugin.entry, repository: plugin.repositoryName)
                    Toggle(text("Enabled"), isOn: Binding(get: { plugin.enabled }, set: { value in act { try await manager.setEnabled(plugin, value) } }))
                        .tint(HarborTheme.accent).frame(minHeight: 44).disabled(manager.busy)
                        .accessibilityIdentifier("reading-plugin-enabled-" + plugin.entry.id)
                    if let repository = manager.document.repositories.first(where: { $0.kind == kind && $0.url == plugin.repository }),
                       let entry = repository.entries.first(where: { $0.id == plugin.entry.id }), entry.version != plugin.entry.version {
                        Button(text("Update") + " · " + entry.version) { act { try await manager.install(entry, repository: repository) } }
                            .buttonStyle(HarborAccountButtonStyle()).disabled(manager.busy)
                    }
                    Button(text("Remove"), role: .destructive) { removal = .plugin(plugin) }
                        .buttonStyle(HarborAccountButtonStyle()).disabled(manager.busy).accessibilityIdentifier("reading-plugin-remove-" + plugin.entry.id)
                }.padding(18).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
            }
        }
    }
    private var repositoryForm: some View {
        HarborSettingsSection("Add a repository") {
            Text(text("Repository link")).font(HarborTheme.font(14, weight: .semibold))
            TextField("https://github.com/user/repo", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .font(HarborTheme.font(15)).padding(14).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 8)).privacySensitive()
                .accessibilityIdentifier("reading-plugin-repository-link")
            Button(text("Add")) {
                let links = HarborPluginManifest.splitLinks(link)
                act {
                    var last: Error?
                    for url in links {
                        do { try await manager.addRepository(url, kind: kind) }
                        catch is CancellationError { throw CancellationError() } catch { last = error }
                    }
                    if let last { throw last }; link = ""
                }
            }.buttonStyle(HarborAccountButtonStyle()).disabled(manager.busy || HarborPluginManifest.splitLinks(link).isEmpty)
                .accessibilityIdentifier("reading-plugin-repository-add")
        }
    }
    private var repositories: some View {
        ForEach(manager.document.repositories.filter { $0.kind == kind }) { repository in
            VStack(alignment: .leading, spacing: 16) {
                Text(repository.name).font(HarborTheme.font(19, weight: .semibold))
                Text(repository.url).font(HarborTheme.font(12)).foregroundStyle(.secondary).textSelection(.enabled).privacySensitive()
                ViewThatFits(in: .horizontal) {
                    HStack { repositoryActions(repository) }
                    VStack(alignment: .leading, spacing: 8) { repositoryActions(repository) }
                }
                if repository.entries.isEmpty {
                    if repository.foreign == "tachiyomi" {
                        Text(text("Conexión Suwayomi") + "\n" + text("Usa el servidor que ya tienes configurado en Harbor. En la red local, permite el acceso cuando iOS lo solicite.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    } else { Text(text("Nothing installed yet")).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
                }
                ForEach(repository.entries.filter { matches($0.name) }) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        heading(entry, repository: nil)
                        let installed = manager.document.plugins.first(where: { $0.kind == kind && $0.entry.id == entry.id })
                        let current = installed?.entry.version == entry.version
                        Button(text(current ? "Installed" : installed == nil ? "Install" : "Update")) { act { try await manager.install(entry, repository: repository) } }
                            .buttonStyle(HarborAccountButtonStyle()).disabled(manager.busy || current)
                            .accessibilityIdentifier("reading-plugin-install-" + entry.id)
                    }.padding(.vertical, 12)
                    Divider().overlay(HarborTheme.ink.opacity(0.1))
                }
            }.padding(18).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
        }
    }
    @ViewBuilder private func repositoryActions(_ repository: HarborReadingPluginRepository) -> some View {
        Button(text("Refresh")) { act { try await manager.refresh(repository) } }.buttonStyle(HarborAccountButtonStyle()).disabled(manager.busy)
        if repository.entries.contains(where: { $0.mangayomi }) {
            Button(text("Install all")) {
                act { for entry in repository.entries { try Task.checkCancellation(); try await manager.install(entry, repository: repository) } }
            }.buttonStyle(HarborAccountButtonStyle()).disabled(manager.busy)
        }
        Button(text("Remove"), role: .destructive) { removal = .repository(repository) }.buttonStyle(HarborAccountButtonStyle()).disabled(manager.busy)
    }
    private func heading(_ entry: HarborReadingPluginEntry, repository: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: entry.icon.flatMap(URL.init(string:))) { image in image.resizable().scaledToFit() }
                placeholder: { Image(systemName: "puzzlepiece.extension").resizable().scaledToFit().padding(10).foregroundStyle(.secondary) }
                .frame(width: 44, height: 44).background(HarborTheme.background, in: .rect(cornerRadius: 8)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(HarborTheme.font(16, weight: .semibold))
                Text([repository, entry.version, entry.language.uppercased(), entry.mangayomi ? "Mangayomi" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(HarborTheme.font(12)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedCaseInsensitiveContains(query) }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    private func act(_ action: @escaping @MainActor () async throws -> Void) {
        guard manager.ready, !manager.busy else { return }; failure = nil
        Task { do { try await action() } catch { if manager.ready, !Task.isCancelled { failure = HarborPluginMessages.error(error) } } }
    }
}
