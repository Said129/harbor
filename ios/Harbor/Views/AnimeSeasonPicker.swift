import SwiftUI

struct AnimeSeasonPicker: View {
    let entries: [AnimeFranchiseEntry]
    let activeID: String?
    let select: (AnimeFranchiseEntry) -> Void
    var loading = false
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var current: AnimeFranchiseEntry? { entries.first { $0.id == activeID } ?? entries.first { $0.current } }
    private var seasons: [AnimeFranchiseEntry] { entries.filter { !$0.extra } }

    var body: some View {
        if let current, seasons.contains(where: { $0.id != current.id }) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    Text(tag(current)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                    Text(current.media.name).font(HarborTheme.font(13.5, weight: .medium)).lineLimit(1)
                    if loading { ProgressView().controlSize(.mini) }
                    Image("episode-expand").resizable().scaledToFit().frame(width: 15, height: 15)
                        .rotationEffect(.degrees(open ? 180 : 0)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                }.padding(.leading, 16).padding(.trailing, 12).frame(minHeight: 44)
                    .background(HarborTheme.ink.opacity(0.06), in: Capsule())
            }.buttonStyle(.plain).disabled(loading).accessibilityIdentifier("anime-franchise-picker")
                .accessibilityValue(current.media.name)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: open)
                .popover(isPresented: $open) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(seasons) { entry in
                                Button {
                                    open = false
                                    if entry.id != activeID { select(entry) }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(tag(entry)).font(.system(size: 11, design: .monospaced)).foregroundStyle(ThemePreferences.shared.color("ink-subtle")).padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text(entry.media.name).font(HarborTheme.font(13.5, weight: .medium)).lineLimit(2)
                                                if entry.upcoming { Text(DesktopInterfaceText.value("Upcoming")).font(HarborTheme.font(10.5)).foregroundStyle(HarborTheme.accent) }
                                            }
                                            Text(detail(entry)).font(HarborTheme.font(11.5)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 54)
                                        .background(entry.id == activeID ? HarborTheme.ink.opacity(0.1) : .clear).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(entry.id == activeID ? [.isSelected] : [])
                                    .accessibilityIdentifier("anime-franchise-" + entry.id)
                            }
                        }.padding(.vertical, 6)
                    }.frame(idealWidth: 360, maxWidth: 380, minHeight: 160, idealHeight: min(480, CGFloat(seasons.count) * 72 + 12), maxHeight: 540)
                        .foregroundStyle(HarborTheme.ink).background(ThemePreferences.shared.color("elevated"))
                        .presentationCompactAdaptation(.sheet).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
        }
    }
    private func tag(_ entry: AnimeFranchiseEntry) -> String {
        if entry.extra { return "MOV" }
        return "S\((seasons.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1)"
    }
    private func detail(_ entry: AnimeFranchiseEntry) -> String {
        var values: [String] = []
        if let count = entry.episodeCount, count > 0 { values.append(DesktopInterfaceText.value(count == 1 ? "{n} ep" : "{n} eps", variables: ["n": String(count)])) }
        if let start = entry.startDate { values.append(String(start.prefix(4))) }
        else if entry.upcoming { values.append("TBA") }
        return values.joined(separator: " · ")
    }
}
