import SwiftUI

/// Desktop's category pins and hidden categories for one Live TV list (`src/views/live/category-sidebar.tsx`).
struct LiveCategoryManageView: View {
    let preferences: LiveTVPreferences
    let sourceID: String
    let groups: [String]
    /// Channels per category in this list, shown as Desktop's sidebar counts.
    var counts: [String: Int] = [:]
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        let prefs = preferences.groupPrefs(for: sourceID)
        return NavigationStack {
            List {
                Section {
                    ForEach(groups.filter { !prefs.hidden.contains($0) }, id: \.self) { group in
                        HStack(spacing: 12) {
                            Text(group).lineLimit(2)
                            Spacer()
                            Text("\(counts[group] ?? 0)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Button { act { try preferences.toggleGroupPin(source: sourceID, group: group) } } label: { Image(systemName: prefs.pinned.contains(group) ? "pin.fill" : "pin") }
                                .accessibilityLabel(DesktopInterfaceText.value(prefs.pinned.contains(group) ? "Unpin category" : "Pin category to top"))
                            Button { act { try preferences.toggleGroupHidden(source: sourceID, group: group) } } label: { Image(systemName: "eye.slash") }
                                .accessibilityLabel(DesktopInterfaceText.value("Hide category"))
                        }.buttonStyle(.borderless)
                    }
                }
                if !prefs.hidden.isEmpty {
                    Section(DesktopInterfaceText.value("{n} hidden", variables: ["n": "\(prefs.hidden.count)"])) {
                        ForEach(prefs.hidden, id: \.self) { group in
                            HStack(spacing: 12) {
                                Text(group).foregroundStyle(.secondary).lineLimit(2)
                                Spacer()
                                Button { act { try preferences.toggleGroupHidden(source: sourceID, group: group) } } label: { Image(systemName: "eye") }
                                    .accessibilityLabel(DesktopInterfaceText.value("Unhide {name}", variables: ["name": group]))
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            .navigationTitle(DesktopInterfaceText.value("Channel categories"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() } } }
        }
    }
    private func act(_ change: () throws -> Void) {
        do { try change() } catch { self.error = safeMessage(error) }
    }
}
