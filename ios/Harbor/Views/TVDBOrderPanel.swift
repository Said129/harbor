import SwiftUI

extension TVDBEpisodeOrderKind {
    var localizedLabel: String {
        switch self {
        case .aired: return DesktopInterfaceText.value("Aired")
        case .dvd: return "DVD"
        case .absolute: return DesktopInterfaceText.value("Absolute")
        case .tvdbabsolute: return "TVDB " + DesktopInterfaceText.value("Absolute")
        case .alternate: return DesktopInterfaceText.value("Alternate")
        case .regional: return DesktopInterfaceText.value("Regional")
        }
    }
}

extension EpisodeOrderSection {
    var label: String {
        if let name, !name.isEmpty { return name }
        if id == "extras" { return DesktopInterfaceText.value("Extras") }
        if joined { return DesktopInterfaceText.value("All") }
        return DesktopInterfaceText.value(number == 0 ? "Specials" : "Season {n}", variables: ["n": String(number)])
    }
}

struct TVDBOrderPanel: View {
    let sections: [EpisodeOrderSection]
    let options: [TVDBEpisodeOrderOption]
    let activeKind: TVDBEpisodeOrderKind
    @Binding var selection: String
    let selectOrder: (TVDBEpisodeOrderKind) -> Void
    var loading = false
    @State private var open = false
    @State private var showExtras = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var current: EpisodeOrderSection? { sections.first { $0.id == selection } ?? sections.first }
    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    var body: some View {
        Button { withAnimation(animation) { open.toggle() } } label: {
            HStack(spacing: 8) {
                Text(current?.label ?? DesktopInterfaceText.value("Seasons")).font(HarborTheme.font(13.5, weight: .medium)).lineLimit(1)
                if loading { ProgressView().controlSize(.mini) }
                Image("episode-expand").resizable().scaledToFit().frame(width: 15, height: 15)
                    .foregroundStyle(ThemePreferences.shared.color("ink-muted")).rotationEffect(.degrees(open ? 180 : 0))
            }.padding(.leading, 16).padding(.trailing, 12).frame(minHeight: 44)
                .background(HarborTheme.ink.opacity(0.06), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Seasons"))
            .accessibilityValue(current?.label ?? "").accessibilityIdentifier("episode-order-panel")
            .animation(animation, value: open)
            .popover(isPresented: $open) {
                panel.frame(idealWidth: 340, maxWidth: 380)
                    .background(ThemePreferences.shared.color("elevated"))
                    .presentationCompactAdaptation(.sheet).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if options.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(options) { option in
                            Button { selectOrder(option.kind) } label: {
                                Text(option.label == option.kind.label ? option.kind.localizedLabel : option.label.replacingOccurrences(of: #"\s*Order$"#, with: "", options: .regularExpression))
                                    .font(HarborTheme.font(12.5, weight: .medium)).lineLimit(1)
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .foregroundStyle(option.kind == activeKind ? HarborTheme.background : ThemePreferences.shared.color("ink-muted"))
                                    .background(option.kind == activeKind ? HarborTheme.ink : .clear, in: Capsule())
                            }.buttonStyle(.plain).disabled(loading)
                                .accessibilityAddTraits(option.kind == activeKind ? [.isSelected] : [])
                                .accessibilityIdentifier("episode-order-" + option.id)
                        }
                    }.padding(8)
                }.scrollIndicators(.hidden).background(HarborTheme.ink.opacity(0.03)).accessibilityIdentifier("episode-order-tabs")
            }
            HStack {
                Text(DesktopInterfaceText.value("Season")); Spacer(); Text(DesktopInterfaceText.value("Episodes"))
            }.font(HarborTheme.font(10.5, weight: .semibold)).textCase(.uppercase).tracking(1.4)
                .foregroundStyle(ThemePreferences.shared.color("ink-subtle")).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections.filter { !$0.extra }) { row($0) }
                    if sections.contains(where: \.extra) {
                        Button { withAnimation(animation) { showExtras.toggle() } } label: {
                            HStack {
                                Text(DesktopInterfaceText.value("Movies & Specials")).textCase(.uppercase).tracking(1.4)
                                Spacer()
                                Image("episode-expand").resizable().scaledToFit().frame(width: 13, height: 13).rotationEffect(.degrees(showExtras ? 180 : 0))
                            }.font(HarborTheme.font(10.5, weight: .semibold)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                                .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("episode-order-extras")
                    }
                    if showExtras { ForEach(sections.filter(\.extra)) { row($0) } }
                }.padding(.bottom, 8)
            }.accessibilityIdentifier("episode-order-season-scroll")
        }.foregroundStyle(HarborTheme.ink).frame(minHeight: 180, idealHeight: min(480, CGFloat(sections.count) * 66 + 110), maxHeight: 540)
            .onAppear { if current?.extra == true { showExtras = true } }
            .onChange(of: selection) { _, _ in if current?.extra == true { showExtras = true } }
            .animation(animation, value: showExtras)
    }

    private func row(_ section: EpisodeOrderSection) -> some View {
        let ongoing = isOngoing(section.to)
        return Button {
            selection = section.id
            withAnimation(animation) { open = false }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.label).font(HarborTheme.font(13.5, weight: section.id == selection ? .semibold : .medium)).lineLimit(2)
                    let dates = dateSubtitle(section, ongoing: ongoing)
                    if !dates.isEmpty { Text(dates).font(HarborTheme.font(11.5)).foregroundStyle(ThemePreferences.shared.color("ink-subtle")) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if ongoing {
                    HStack(spacing: 4) {
                        Circle().fill(HarborTheme.accent).frame(width: 5, height: 5)
                        Text(DesktopInterfaceText.value("Ongoing")).font(HarborTheme.font(10.5))
                    }.foregroundStyle(HarborTheme.accent)
                }
                Text(String(section.episodes.count)).font(HarborTheme.font(13)).monospacedDigit().foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
            }.padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 52)
                .background(section.id == selection ? HarborTheme.ink.opacity(0.1) : .clear).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
            .accessibilityAddTraits(section.id == selection ? [.isSelected] : [])
            .accessibilityIdentifier("episode-order-season-" + section.id)
    }

    private func parsed(_ value: String?) -> Date? {
        value.flatMap { ISO8601DateParser.shared.date($0) ?? ISO8601DateParser.shared.date(String($0.prefix(10)) + "T00:00:00Z") }
    }
    private func isOngoing(_ value: String?) -> Bool {
        guard let date = parsed(value) else { return false }
        let calendar = Calendar.current
        return calendar.compare(date, to: Date(), toGranularity: .month) != .orderedAscending
    }
    private func dateSubtitle(_ section: EpisodeOrderSection, ongoing: Bool) -> String {
        guard let first = parsed(section.from), let last = parsed(section.to) else { return String((section.from ?? section.to ?? "").prefix(4)) }
        let start = first.formatted(.dateTime.month(.abbreviated).year()), end = last.formatted(.dateTime.month(.abbreviated).year())
        if ongoing { return start + " – " + DesktopInterfaceText.value("Current") }
        return start == end ? start : start + " – " + end
    }
}
