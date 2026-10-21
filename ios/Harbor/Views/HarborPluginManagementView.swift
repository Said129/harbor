import SwiftUI
import UIKit
import ImageIO

struct HarborPluginManagementView: View {
    let app: AppModel
    @State private var manager: HarborStreamPluginManager?
    @State private var failure: String?
    @State private var kind = "streams"
    @State private var reading: HarborReadingPluginManager?
    @State private var readingFailure: String?
    @MainActor init(app: AppModel, kind: HarborReadingPluginKind? = nil) {
        self.app = app; _kind = State(initialValue: kind?.rawValue ?? "streams")
    }
    var body: some View {
        VStack(spacing: 0) {
            HarborSettingsSegmented(selection: $kind, choices: [(DesktopInterfaceText.value("Streams"), "streams"), ("Manga", "manga"), (DesktopInterfaceText.value("Books"), "ebook")])
                .padding(.horizontal, 20).padding(.vertical, 12).accessibilityIdentifier("plugin-kind")
            if let selected = HarborReadingPluginKind(rawValue: kind) {
                if let reading, reading.ready { HarborReadingPluginManagementView(manager: reading, kind: selected).id(selected) }
                else {
                    VStack(spacing: 18) {
                        if let readingFailure { Text(readingFailure); Button(DesktopInterfaceText.value("Retry")) { Task { await openReading() } } }
                        else { ProgressView(DesktopInterfaceText.value("Loading plugins...")) }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let manager, manager.ready, let runtime = app.plugins.runtime { HarborPluginCatalogSettings(manager: manager, runtime: runtime, pause: { app.plugins.runtime?.cancelCalls() }) }
            else {
                VStack(spacing: 18) {
                    if let failure {
                        Text(failure).font(HarborTheme.font(14)).multilineTextAlignment(.center)
                        Button(DesktopInterfaceText.value("Retry")) { Task { await open() } }.buttonStyle(HarborAccountButtonStyle())
                    } else { ProgressView(DesktopInterfaceText.value("Loading plugins...")) }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(DesktopInterfaceText.value("Plugins")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("plugin-management")
            .task(id: app.accountOperationScope + "|" + String(app.storageReady)) { await open() }
            .task(id: kind + "|" + app.accountOperationScope) { if kind != "streams" { await openReading() } }
    }
    private func open() async {
        manager = nil; failure = nil
        guard let scope = app.pluginExecutionScope else { return }
        do {
            let next = try await app.plugins.open(scope: scope, currentScope: { [weak app] in
                app?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation)
            })
            try Task.checkCancellation()
            guard app.pluginExecutionScope == scope else { return }
            manager = next
        } catch { if !Task.isCancelled, app.pluginExecutionScope == scope { failure = HarborPluginMessages.error(error) } }
    }
    private func openReading() async {
        reading = nil; readingFailure = nil
        do { reading = try await app.openReadingPlugins() }
        catch { if !Task.isCancelled { readingFailure = HarborPluginMessages.error(error) } }
    }
}

private struct HarborPluginCatalogSettings: View {
    private enum Removal {
        case repository(HarborStreamRepositoryRecord)
        case plugin(HarborInstalledStreamPlugin)
    }
    @Bindable var manager: HarborStreamPluginManager
    let runtime: HarborStreamPluginPool
    let pause: @MainActor () -> Void
    @AppStorage("pluginsEnabled") private var enabled = true
    @AppStorage("pluginsGroupByRepo") private var groupByRepository = false
    @State private var tab = "plugins"
    @State private var link = ""
    @State private var query = ""
    @State private var failure: String?
    @State private var running = false
    @State private var editing: HarborInstalledStreamPlugin?
    @State private var activity: HarborInstalledStreamPlugin?
    @State private var remove: Removal?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HarborSettingsSegmented(selection: $tab, choices: [(text("Plugins"), "plugins"), (text("Repositories"), "repositories")])
                HarborSearchField(prompt: text("Search"), text: $query)
                if let failure { Text(failure).font(HarborTheme.font(14)).foregroundStyle(ThemePreferences.shared.color("danger")) }
                if running { ProgressView() }
                if tab == "repositories" { repositoryForm }
                if tab == "plugins" { options; installed }
                else { repositories }
            }.padding(20).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tab)
            .sheet(item: $editing) { plugin in HarborPluginSettingsView(manager: manager, plugin: plugin) }
            .sheet(item: $activity) { plugin in HarborPluginActivityView(plugin: plugin, manager: manager, runtime: runtime) }
            .onChange(of: enabled) { _, value in if !value { pause() } }
            .confirmationDialog(text("Remove"), isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible) {
                if let target = remove {
                    Button(text("Remove"), role: .destructive) {
                        act {
                            switch target {
                            case .repository(let repository): try await manager.removeRepository(repository.url)
                            case .plugin(let plugin): try await manager.uninstall(plugin.id)
                            }
                        }
                        remove = nil
                    }.accessibilityIdentifier("plugin-confirm-remove")
                }
                Button(text("Cancel"), role: .cancel) { remove = nil }
            }.onChange(of: manager.ready) { _, ready in if !ready { editing = nil; activity = nil; link = ""; failure = nil } }
    }
    private var options: some View {
        HarborSettingsSection("Use plugins") {
            Toggle(text("Use plugins"), isOn: $enabled).tint(HarborTheme.accent).frame(minHeight: 44)
                .accessibilityIdentifier("plugin-use-all")
            Text(text("Plugins look for streams on sites Harbor does not know about. Everything here was installed by you, from repositories you chose."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary)
            if !enabled { Text(text("Plugins are paused. Turn on Use plugins above to run them.")).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
            Toggle(text("Group by repository"), isOn: $groupByRepository).tint(HarborTheme.accent).frame(minHeight: 44)
                .accessibilityIdentifier("plugin-group-repository")
            Text(text("Show one source per repository in the picker instead of one per plugin. Useful when a repository ships many small providers."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary)
        }
    }
    private var repositoryForm: some View {
        HarborSettingsSection("Add a repository") {
            Text(text("Repository link")).font(HarborTheme.font(14, weight: .semibold))
            TextField("https://github.com/user/repo", text: $link)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .font(HarborTheme.font(15)).padding(14).frame(minHeight: 48)
                .background(HarborTheme.surface, in: .rect(cornerRadius: 8)).privacySensitive()
                .accessibilityIdentifier("plugin-repository-link")
            Button(text("Add")) {
                let links = HarborPluginManifest.splitLinks(link)
                act {
                    var last: Error?
                    for url in links {
                        do { try await manager.addRepository(url) }
                        catch is CancellationError { throw CancellationError() }
                        catch { last = error }
                    }
                    if let last { throw last }
                    link = ""
                }
            }.buttonStyle(HarborAccountButtonStyle()).disabled(running || HarborPluginManifest.splitLinks(link).isEmpty)
                .accessibilityIdentifier("plugin-repository-add")
        }
    }
    private var installed: some View {
        Group {
            let visible = manager.document.plugins.filter { matches($0.entry.name + " " + $0.repoName) }
            if visible.isEmpty { Text(text("Nothing installed yet")).font(HarborTheme.font(14)).foregroundStyle(.secondary).accessibilityIdentifier("plugin-empty") }
            ForEach(visible) { plugin in
                VStack(alignment: .leading, spacing: 14) {
                    pluginHeading(plugin.entry, repository: plugin.repoName)
                    if !plugin.listed { Text(text("No longer listed by its repository.")).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
                    if plugin.autoPaused { Text(DesktopInterfaceText.value("Stopped after {n} failures.", variables: ["n": "3"])).font(HarborTheme.font(13)).foregroundStyle(ThemePreferences.shared.color("danger")) }
                    Toggle(text("Enabled"), isOn: Binding(get: { plugin.enabled }, set: { enabled in act { try await manager.setEnabled(plugin.id, enabled) } }))
                        .tint(HarborTheme.accent).frame(minHeight: 44).disabled(running)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { actions(plugin) }
                        VStack(alignment: .leading, spacing: 10) { actions(plugin) }
                    }
                }.padding(18).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
            }
        }
    }
    @ViewBuilder private func actions(_ plugin: HarborInstalledStreamPlugin) -> some View {
        Button(text(plugin.autoPaused ? "Try again" : "Recent activity")) { editing = nil; activity = plugin }
            .buttonStyle(HarborAccountButtonStyle()).disabled(running)
            .accessibilityIdentifier("plugin-activity-" + plugin.entry.id)
        if plugin.entry.settings {
            Button(text("Settings")) { editing = plugin }.buttonStyle(HarborAccountButtonStyle()).disabled(running)
                .accessibilityIdentifier("plugin-configure-" + plugin.entry.id)
        }
        if plugin.updateVersion != nil {
            Button(text("Update")) { act { try await manager.install(repository: plugin.repoURL, entryID: plugin.entry.id) } }
                .buttonStyle(HarborAccountButtonStyle()).disabled(running || !plugin.listed)
        }
        if plugin.previous != nil {
            Button(text("Revert")) { act { try await manager.revert(plugin.id) } }.buttonStyle(HarborAccountButtonStyle()).disabled(running)
        }
        Button(text("Remove"), role: .destructive) { remove = .plugin(plugin) }.buttonStyle(HarborAccountButtonStyle()).disabled(running)
            .accessibilityIdentifier("plugin-remove-" + plugin.entry.id)
    }
    private var repositories: some View {
        ForEach(manager.document.repositories, id: \.url) { repository in
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(repository.manifest.name).font(HarborTheme.font(19, weight: .semibold))
                    Spacer(minLength: 8)
                    Text("\(repository.manifest.entries.count)").font(HarborTheme.font(14)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(text("Refresh")) { act { try await manager.refreshRepository(repository.url) } }.buttonStyle(HarborAccountButtonStyle()).disabled(running)
                    Button(text("Remove"), role: .destructive) { remove = .repository(repository) }.buttonStyle(HarborAccountButtonStyle()).disabled(running)
                }
                if let error = repository.error { Text(HarborPluginMessages.error(HarborPluginRepositoryError(error))).font(HarborTheme.font(13)).foregroundStyle(ThemePreferences.shared.color("danger")) }
                ForEach(repository.manifest.entries.filter { matches($0.name + " " + repository.manifest.name) }) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().overlay(ThemePreferences.shared.color("edge-soft"))
                        pluginHeading(entry, repository: nil)
                        let id = HarborPluginManifest.pluginID(repository: repository.url, entry: entry.id)
                        if manager.document.plugins.contains(where: { $0.id == id }) {
                            Text(text("Installed")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                        } else if entry.format != .androidExtension {
                            Button(text("Install")) { act { try await manager.install(repository: repository.url, entryID: entry.id) } }
                                .buttonStyle(HarborAccountButtonStyle()).disabled(running || !entry.enabled)
                        }
                    }
                }
            }.padding(18).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
        }
    }
    private func pluginHeading(_ entry: HarborStreamPluginEntry, repository: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HarborInstalledPluginIcon(icon: entry.icon)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(HarborTheme.font(16, weight: .semibold))
                Text([repository, entry.version, entry.author].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(HarborTheme.font(12.5)).foregroundStyle(.secondary)
                if let description = entry.description { Text(description).font(HarborTheme.font(13)).foregroundStyle(.secondary).lineLimit(4) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedCaseInsensitiveContains(query) }
    private func act(_ action: @escaping @MainActor () async throws -> Void) {
        guard !running, manager.ready else { return }
        running = true; failure = nil
        Task {
            defer { running = false }
            do { try await action() }
            catch { if manager.ready, !Task.isCancelled { failure = HarborPluginMessages.error(error) } }
        }
    }
}

private struct HarborInstalledPluginIcon: View {
    let icon: String?
    private var image: UIImage? {
        guard let icon, icon.hasPrefix("data:image/"), let comma = icon.firstIndex(of: ","),
              let data = Data(base64Encoded: String(icon[icon.index(after: comma)...])), data.count <= 512 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) else { return nil }
        return UIImage(cgImage: preview)
    }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "puzzlepiece.extension").resizable().scaledToFit().padding(10).foregroundStyle(.secondary) }
        }.frame(width: 44, height: 44).background(HarborTheme.background, in: .rect(cornerRadius: 8)).accessibilityHidden(true)
    }
}
