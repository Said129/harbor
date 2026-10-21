import SwiftUI

struct HarborPluginActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: HarborPluginActivityModel
    @State private var checking: Task<Void, Never>?
    @AppStorage("pluginsEnabled") private var enabled = true

    init(plugin: HarborInstalledStreamPlugin, manager: HarborStreamPluginManager, runtime: HarborStreamPluginPool) {
        _model = State(initialValue: HarborPluginActivityModel(id: plugin.id, manager: manager, runtime: runtime))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let plugin = model.plugin {
                        Text(plugin.entry.name).font(HarborTheme.font(24, weight: .semibold))
                        HarborSettingsSection("Plugin files") {
                            Text(plugin.repoName + " · v" + plugin.entry.version).font(HarborTheme.font(14)).textSelection(.enabled)
                            if plugin.autoPaused { Text(text("Stopped after {n} failures.", ["n": "3"])).foregroundStyle(ThemePreferences.shared.color("danger")) }
                            if plugin.filesChanged { Text(text("Plugin files changed on disk. Reinstall it from its repository.")).font(HarborTheme.font(13)) }
                        }
                        HarborSettingsSection("Reaches") {
                            Text(plugin.entry.hosts.isEmpty ? text("Any public website. This plugin did not say which sites it uses.") : plugin.entry.hosts.joined(separator: ", "))
                                .font(HarborTheme.font(14)).textSelection(.enabled)
                            let hosts = Array(Set(plugin.learnedHosts + (model.health?.seenHosts ?? []))).sorted()
                            if !hosts.isEmpty { Text(text("Seen so far: {hosts}", ["hosts": hosts.joined(separator: ", ")])).font(HarborTheme.font(13)).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                        HarborSettingsSection("Check it works") {
                            Text(checkDescription).font(HarborTheme.font(14)).accessibilityIdentifier("plugin-check-result")
                            if let error = model.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(ThemePreferences.shared.color("danger")) }
                            if !enabled { Text(text("Plugins are paused. Turn on Use plugins above to run them.")).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
                            Button {
                                checking = Task { await model.check() }
                            } label: {
                                HStack(spacing: 10) {
                                    if model.checking { ProgressView() }
                                    Text(text(model.checking ? "Checking…" : plugin.autoPaused ? "Try again" : "Check it works"))
                                }
                            }.buttonStyle(HarborAccountButtonStyle()).disabled(!model.canCheck || model.checking)
                                .accessibilityIdentifier("plugin-check-now")
                        }
                        HarborSettingsSection("Recent activity") {
                            Text(activityDescription).font(HarborTheme.font(14)).accessibilityIdentifier("plugin-recent-activity")
                            if let date = model.health?.lastAt { Text(Date(timeIntervalSince1970: date / 1000), format: .dateTime.hour().minute().second()).font(HarborTheme.font(12)).foregroundStyle(.secondary) }
                            if !model.logs.isEmpty {
                                Text(model.logs.map { line in
                                    Date(timeIntervalSince1970: line.at / 1000).formatted(date: .omitted, time: .standard) + " " + line.level + " " + line.text
                                }.joined(separator: "\n"))
                                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).environment(\.layoutDirection, .leftToRight)
                                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(HarborTheme.surface, in: .rect(cornerRadius: 8)).accessibilityIdentifier("plugin-activity-log")
                            }
                        }
                    }
                }.padding(20).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
                .navigationTitle(text("Recent activity")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Close")) { dismiss() } } }
        }.accessibilityIdentifier("plugin-activity")
            .onChange(of: model.manager.ready) { _, ready in if !ready { dismiss() } }
            .onDisappear { checking?.cancel(); checking = nil; model.clear() }
    }
    private var checkDescription: String {
        guard let result = model.result else { return text("Runs this plugin on a real title and shows what came back.") }
        if result.count == 0 { return text("No streams came back.") }
        return text("Found {count} streams in {seconds}s.", ["count": String(result.count), "seconds": String(format: "%.1f", Double(result.milliseconds) / 1000)])
            + " " + text("{requests} requests", ["requests": String(result.requests)])
    }
    private var activityDescription: String {
        guard let health = model.health else { return "—" }
        if let error = health.error { return text("Stopped with: {error}", ["error": error]) }
        if let skipped = health.skipped { return text("Skipped: {reason}", ["reason": skipped]) }
        guard let count = health.count, let title = health.title else { return "—" }
        return count == 0 ? text("No streams for {title}", ["title": title]) : text("Found {count} streams for {title} in {seconds}s", ["count": String(count), "title": title, "seconds": String(format: "%.1f", Double(health.milliseconds ?? 0) / 1000)])
    }
    private func text(_ key: String, _ variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }
}
