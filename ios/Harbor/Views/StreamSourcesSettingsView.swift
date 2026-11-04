import SwiftUI

/// Desktop's "Streaming sources" panel (`streaming-sources-panel.tsx`): Services, Filters,
/// Sorting and Picker. Home servers (Jellyfin, Emby and Plex video libraries) is not ported yet.
struct StreamSourcesSettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case services, filters, sorting, picker
        var id: String { rawValue }
        var title: String {
            switch self {
            case .services: "Services"
            case .filters: "Filters"
            case .sorting: "Sorting"
            case .picker: "Picker"
            }
        }
    }

    let app: AppModel
    @Bindable private var sources = StreamPreferences.shared
    @State private var tab = Tab.services
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(text("Streaming sources")).font(HarborTheme.displayFont(30)).accessibilityAddTraits(.isHeader)
                HarborSettingsSegmented(selection: $tab, choices: Tab.allCases.map { (text($0.title), $0) })
                    .accessibilityIdentifier("streaming-sources-tabs")
                switch tab {
                case .services: services
                case .filters: filters
                case .sorting: sorting
                case .picker: picker
                }
            }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).buttonStyle(.plain)
            .navigationTitle(text("Streaming sources")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("streaming-sources-settings")
    }

    // MARK: Services

    @ViewBuilder private var services: some View {
        HarborSettingsSection("Debrid services", note: "Real-Debrid, TorBox, AllDebrid, Premiumize, Debrid-Link. Cached streams play direct. Keys stay local.") {
            if let scope = app.pluginExecutionScope {
                NavigationLink { DebridSettingsView(app: app, scope: scope).toolbar(.visible, for: .navigationBar) } label: {
                    SettingsRow(title: text("Debrid services"), icon: "nav-download")
                }.background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("streaming-sources-debrid")
            }
        }
    }

    // MARK: Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 28) {
            HarborSettingsSection("Stream safety filter") {
                detailText("Choose which addon results appear when you pick a stream.")
                // The iPhone picker lists every source so nothing is hidden behind an extra
                // button; the level decides what automatic playback may start.
                detailText("On iPhone the picker lists every source; this filter decides which ones automatic playback may start.")
                VStack(alignment: .leading, spacing: 10) {
                    option("Strict", detail: "Hide suspicious files, mismatched releases, likely camera recordings and trailers. Also check file sizes and season packs.",
                           selected: sources.filterLevel == "strict", isDefault: true, identifier: "settings-stream-filter-strict") { sources.filterLevel = "strict" }
                    option("Balanced", detail: "Keep the suspicious-file and release checks, but allow more results, including larger files and season packs.",
                           selected: sources.filterLevel == "balanced", identifier: "settings-stream-filter-balanced") { sources.filterLevel = "balanced" }
                    option("Off", detail: "Show all results returned by addons, including releases that do not match or may be suspicious.",
                           selected: sources.filterLevel == "off", identifier: "settings-stream-filter-off") { sources.filterLevel = "off" }
                }
            }
            HarborSettingsSection("Addon wait time", note: "Results appear as they arrive. Increase the wait time if an addon often needs a refresh before its results appear.") {
                HarborSettingsChoice("Addon wait time", selection: $sources.addonTimeoutSeconds, choices: timeoutChoices, localizeChoices: false,
                                     identifier: "settings-addon-timeout")
                detailText("How long Harbor waits for each addon to return results.")
            }
        }
    }

    private var timeoutChoices: [(String, Int)] {
        let current = StreamSourceSettings.clamped(sources.addonTimeoutSeconds)
        return Array(Set(StreamSourceSettings.timeoutChoices + [current])).sorted().map { seconds in
            (seconds == StreamSourceSettings.defaultTimeoutSeconds ? text("30 seconds (default)")
                : DesktopInterfaceText.value("{seconds} seconds", variables: ["seconds": String(seconds)]), seconds)
        }
    }

    // MARK: Sorting

    private var sorting: some View {
        HarborSettingsSection("Result order") {
            detailText("Harbor ranking puts the best-scoring sources first. Addon order keeps each addon's results in the order it returned them, like the Stremio and Vidi apps. Stream priority below decides which addon leads, in both modes.")
            VStack(alignment: .leading, spacing: 10) {
                option("Harbor ranking", detail: "Default. Harbor parses and scores every source and surfaces the best quality first.",
                       selected: !sources.addonOrder, identifier: "settings-stream-sort-harbor") { sources.addonOrder = false }
                option("Addon order", detail: "Show each addon's results in the order it returned them, grouped by your addon list. Matches the Stremio and Vidi apps.",
                       selected: sources.addonOrder, identifier: "settings-stream-sort-addon") { sources.addonOrder = true }
            }
            priorityCard
            HStack(alignment: .top, spacing: 12) {
                Image("desktop-info").resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(text("Aggregator addons")).font(HarborTheme.font(14, weight: .semibold))
                    detailText("Using AIOStreams or another aggregator addon? Its own sorting and filtering happen inside the addon before Harbor ever sees the results, then Harbor applies the stream filter and result order above on top. If results look thinner than expected, keep one side permissive: either relax the addon's internal filters or set Harbor's stream filter to Balanced or Off.")
                }
            }
        }
    }

    private var priorityEntries: [(entry: StreamPriorityEntry, installed: Bool)] {
        StreamAddonPriority.entries(addons: app.addons, priority: sources.priority)
    }

    private var priorityCard: some View {
        let entries = priorityEntries
        let streaming = StreamAddonPriority.streamAddons(app.addons).count
        let others = app.addons.count - streaming
        let custom = !sources.priority.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(text("Stream priority")).font(HarborTheme.font(16, weight: .semibold))
                Text(String(entries.count)).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if custom {
                    Button(text("Use addon order")) {
                        sources.priority = []
                        announce(text("Following addon order"))
                    }.font(HarborTheme.font(14, weight: .semibold)).frame(minHeight: 44).accessibilityIdentifier("settings-stream-priority-reset")
                }
                Text(text(custom ? "Custom" : "Following addon order")).font(HarborTheme.font(11, weight: .bold)).textCase(.uppercase)
                    .padding(.horizontal, 8).frame(height: 22).background(HarborTheme.surface, in: .rect(cornerRadius: 6))
            }
            detailText("Results from addons higher in this list come first. If one finds nothing, the next fills in.")
            if streaming < 2 {
                Text(text("Priority applies once you have two or more stream addons.")).font(HarborTheme.font(14)).foregroundStyle(.secondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(ThemePreferences.shared.color("edge-soft"), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().overlay(ThemePreferences.shared.color("edge-soft").opacity(0.4)) }
                        priorityRow(item.entry, installed: item.installed, index: index, count: entries.count)
                    }
                }.background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12))
            }
            if others > 0 {
                Text(DesktopInterfaceText.value("{n} addons don't provide streams and aren't listed.", variables: ["n": String(others)]))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary)
            }
        }.padding(.top, 6)
    }

    private func priorityRow(_ entry: StreamPriorityEntry, installed: Bool, index: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(String(index + 1)).font(HarborTheme.font(13)).monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(HarborTheme.font(15, weight: .semibold)).lineLimit(1)
                Text(installed ? entry.key : text("Not installed")).font(HarborTheme.font(12)).foregroundStyle(.secondary).lineLimit(1)
            }.opacity(installed ? 1 : 0.6).frame(maxWidth: .infinity, alignment: .leading)
            if index > 0 {
                iconButton("chevron.up.2", label: "Move to top") { move(from: index, to: 0) }
                iconButton("chevron.up", label: "Move up") { move(from: index, to: index - 1) }
            }
            if index < count - 1 { iconButton("chevron.down", label: "Move down") { move(from: index, to: index + 1) } }
            if !installed { iconButton("xmark", label: "Remove from list") { remove(at: index) } }
        }.padding(.horizontal, 12).padding(.vertical, 6).accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings-stream-priority-\(entry.key)")
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
        }.accessibilityLabel(text(label))
    }

    /// Desktop's `moveItem`, then the whole visible order becomes the saved order.
    private func move(from: Int, to: Int) {
        var entries = priorityEntries.map(\.entry)
        let target = max(0, min(entries.count - 1, to))
        guard entries.indices.contains(from), from != target else { return }
        let moved = entries.remove(at: from)
        entries.insert(moved, at: target)
        sources.priority = Array(entries.prefix(64))
        announce(DesktopInterfaceText.value("Moved {name} to position {n} of {total}",
                                            variables: ["name": moved.name, "n": String(target + 1), "total": String(entries.count)]))
    }

    private func remove(at index: Int) {
        var entries = priorityEntries.map(\.entry)
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        sources.priority = Array(entries.prefix(64))
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: Picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 28) {
            HarborSettingsSection("Picker layout", note: "Condensed shows a top pick, quality tiles, and a drawer. Stremio is a flat list grouped by addon, no scoring.") {
                HarborSettingsSegmented(selection: $sources.pickerLayout, choices: [(text("Condensed"), "condensed"), (text("Stremio"), "stremio")])
                    .accessibilityIdentifier("settings-picker-layout")
            }
            HarborSettingsSection("Source mode") {
                Text(text("Prefer these sources")).font(HarborTheme.font(15, weight: .semibold))
                // Desktop's third choice puts peer-to-peer results first. The iPhone has no
                // torrent engine, so those results only start through a debrid service.
                detailText("Both shows direct, debrid, and peer-to-peer results together. Direct/debrid keeps P2P results out of the way unless nothing else is available. P2P puts them first.")
                HarborSettingsSegmented(selection: $sources.sourceMode, choices: [(text("Both"), StreamMode.both), (text("Direct/debrid"), StreamMode.addons)])
                    .accessibilityIdentifier("settings-source-mode")
            }
            HarborSettingsSection("Picker details") {
                HarborSettingsToggle("Move Refresh next to Back", note: "Groups Refresh beside Back at the start of the picker header. Off keeps it at the far end, across from Back.",
                                     isOn: $sources.pickerRefreshNextToBack).accessibilityIdentifier("settings-picker-refresh-position")
                HarborSettingsToggle("Show release name", note: "Show release filenames in the Condensed picker and Big Picture.",
                                     isOn: $sources.pickerShowFilename).accessibilityIdentifier("settings-picker-filename")
                HarborSettingsToggle("Show full descriptions", note: "Show complete addon descriptions in the Stremio picker, downloads, and Big Picture.",
                                     isOn: $sources.fullStreamDescription).accessibilityIdentifier("settings-picker-descriptions")
            }
        }
    }

    // MARK: Shared rows

    private func detailText(_ key: String) -> some View {
        Text(text(key)).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func option(_ title: String, detail: String, selected: Bool, isDefault: Bool = false, identifier: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.system(size: 20))
                    .foregroundStyle(selected ? HarborTheme.accent : ThemePreferences.shared.color("ink-subtle")).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(text(title)).font(HarborTheme.font(15, weight: .semibold))
                        if isDefault { Text(text("Default")).font(HarborTheme.font(12)).foregroundStyle(.secondary) }
                    }
                    Text(text(detail)).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                .background(selected ? HarborTheme.surface : HarborTheme.surface.opacity(0.35), in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? HarborTheme.ink.opacity(0.25) : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
        }.accessibilityAddTraits(selected ? [.isSelected] : []).accessibilityIdentifier(identifier)
    }
}
