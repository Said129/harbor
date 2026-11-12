import SwiftUI

/// Desktop's switcher "Filters" menu for what the native picker lacked: the source format, cached only,
/// "my languages only" and flagged streams. The numbers and the rules for when a row appears come from the
/// picker, which follows `filters-menu.tsx`: a row shows only while it would change the list, or while it is on.
struct StreamSwitcherFiltersView: View {
    @Binding var filters: StreamSwitcherFilters
    let groups: [StreamSwitcherFilters.SourceGroup]
    let hasDebrid: Bool
    let uncachedHidden: Int
    /// The preferred languages as "EN, ES"; empty when none are chosen.
    let languages: String
    let languageHidden: Int
    let flaggedCount: Int
    let busy: Bool
    @State private var open = false

    private var showsCached: Bool { hasDebrid && (uncachedHidden > 0 || filters.cachedOnly) }
    private var showsLanguage: Bool { !languages.isEmpty && (languageHidden > 0 || filters.preferredLanguageOnly) }
    private var showsFlagged: Bool { flaggedCount > 0 || filters.showFlagged }
    private var hasAnything: Bool { !groups.isEmpty || showsCached || showsLanguage || showsFlagged || filters.activeCount > 0 }

    var body: some View {
        if hasAnything {
            VStack(alignment: .leading, spacing: 12) {
                toggleButton
                if open { panel }
            }.frame(maxWidth: .infinity, alignment: .leading).disabled(busy)
        }
    }

    private var toggleButton: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 15)).accessibilityHidden(true)
                Text(DesktopInterfaceText.value("Filters")).font(HarborTheme.font(13, weight: .semibold))
                if filters.activeCount > 0 {
                    Text(String(filters.activeCount)).font(HarborTheme.font(11, weight: .bold)).foregroundStyle(HarborTheme.background)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18).background(HarborTheme.accent, in: .capsule)
                }
                Image("settings-chevron-down").resizable().scaledToFit().frame(width: 12, height: 12)
                    .rotationEffect(.degrees(open ? 180 : 0)).accessibilityHidden(true)
            }.padding(.horizontal, 14).frame(minHeight: 44)
                .background(ThemePreferences.shared.color("elevated").opacity(0.6), in: .capsule)
                .overlay { Capsule().stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityValue(String(filters.activeCount)).accessibilityIdentifier("stream-switcher-filters")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !groups.isEmpty { formatSection }
            if showsCached {
                HarborSettingsToggle("Cached only",
                                     note: DesktopInterfaceText.value("{n} uncached hidden", variables: ["n": String(uncachedHidden)]),
                                     isOn: $filters.cachedOnly)
                    .accessibilityIdentifier("stream-switcher-cached-only")
            }
            if showsLanguage {
                HarborSettingsToggle(DesktopInterfaceText.value("{langs} only", variables: ["langs": languages]),
                                     note: DesktopInterfaceText.value("{n} hidden", variables: ["n": String(languageHidden)]),
                                     isOn: $filters.preferredLanguageOnly)
                    .accessibilityIdentifier("stream-switcher-languages-only")
            }
            if showsFlagged {
                HarborSettingsToggle("Show flagged",
                                     note: DesktopInterfaceText.value("{n} hidden by trust filter", variables: ["n": String(flaggedCount)]),
                                     isOn: $filters.showFlagged)
                    .accessibilityIdentifier("stream-switcher-show-flagged")
            }
            if filters.activeCount > 0 {
                Button { filters = StreamSwitcherFilters() } label: {
                    Text(DesktopInterfaceText.value("Reset filters")).font(HarborTheme.font(13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("stream-switcher-reset")
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(ThemePreferences.shared.color("elevated").opacity(0.4), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThemePreferences.shared.color("edge-soft").opacity(0.6), lineWidth: 1) }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DesktopInterfaceText.value("Format")).font(HarborTheme.font(11, weight: .bold)).tracking(2).textCase(.uppercase)
                .foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
            StreamChipLayout(spacing: 8) {
                chip(DesktopInterfaceText.value("Any"), count: nil, active: filters.sourceGroup == nil) { filters.sourceGroup = nil }
                ForEach(groups) { group in
                    chip(group.name, count: group.count, active: filters.sourceGroup == group.name) { filters.sourceGroup = group.name }
                }
            }
        }
    }

    private func chip(_ title: String, count: Int?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                if let count { Text(String(count)).opacity(0.7) }
            }.font(HarborTheme.font(12, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(active ? HarborTheme.background : ThemePreferences.shared.color("ink-muted"))
                .background(active ? HarborTheme.ink : ThemePreferences.shared.color("elevated").opacity(0.5), in: .capsule)
        }.buttonStyle(.plain).accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// Desktop's "Filtered" badge on a stream that is listed only because "Show flagged" is on.
struct StreamFlaggedMark: ViewModifier {
    let flagged: Bool

    /// The badge sits above the row, so it never covers the row's download or play button.
    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if flagged {
                Text(DesktopInterfaceText.value("Filtered")).font(HarborTheme.font(10, weight: .bold)).textCase(.uppercase)
                    .foregroundStyle(Color.red).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.red.opacity(0.15), in: .capsule).padding(.horizontal, 16).padding(.top, 8)
                    .allowsHitTesting(false)
            }
            content
        }
    }
}
