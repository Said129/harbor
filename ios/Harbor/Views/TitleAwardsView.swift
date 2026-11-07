import SwiftUI

extension TitleAwardCeremony {
    /// Desktop's `TYPE_TITLE` in `src/components/awards-block.tsx`.
    var displayTitle: String {
        switch self {
        case .oscar: return DesktopInterfaceText.value("Academy Awards")
        case .emmy: return DesktopInterfaceText.value("Primetime Emmys")
        case .bafta: return DesktopInterfaceText.value("BAFTA Awards")
        case .baftaTV: return DesktopInterfaceText.value("BAFTA Television Awards")
        case .goldenGlobe: return DesktopInterfaceText.value("Golden Globes")
        case .sag: return DesktopInterfaceText.value("Screen Actors Guild Awards")
        case .criticsChoice: return DesktopInterfaceText.value("Critics' Choice Awards")
        case .cannes: return DesktopInterfaceText.value("Cannes Film Festival")
        case .venice: return DesktopInterfaceText.value("Venice Film Festival")
        case .berlin: return DesktopInterfaceText.value("Berlin Film Festival")
        case .cesar: return DesktopInterfaceText.value("César Awards")
        case .goya: return DesktopInterfaceText.value("Goya Awards")
        case .blueDragon: return DesktopInterfaceText.value("Blue Dragon Film Awards")
        case .baeksang: return DesktopInterfaceText.value("Baeksang Arts Awards")
        case .bifa: return DesktopInterfaceText.value("British Independent Film Awards")
        case .spirit: return DesktopInterfaceText.value("Independent Spirit Awards")
        case .annie: return DesktopInterfaceText.value("Annie Awards")
        case .saturn: return DesktopInterfaceText.value("Saturn Awards")
        case .other: return DesktopInterfaceText.value("Other Awards")
        }
    }
}

extension TitleAwardCeremonyGroup {
    /// Desktop's "N Wins · M Nominations" line.
    var countLine: String {
        var parts: [String] = []
        if winCount > 0 {
            let word = DesktopInterfaceText.value(winCount == 1 ? "Win" : "Wins")
            parts.append("\(winCount) \(word)")
        }
        if nominationCount > 0 {
            let word = DesktopInterfaceText.value(nominationCount == 1 ? "Nomination" : "Nominations")
            parts.append("\(nominationCount) \(word)")
        }
        return parts.joined(separator: " · ")
    }

    /// Desktop's `formatYearSpan`: one year, or the first and last year with an en dash.
    var yearSpan: String {
        guard let first = years.first, let last = years.last else { return "" }
        return first == last ? String(first) : "\(first)–\(last)"
    }
}

/// Loads the Wikidata awards of one title. The result is kept in memory for the session, as Desktop keeps it for 30 days.
@MainActor @Observable final class TitleAwardsModel {
    private(set) var result: TitleAwardsLoad?
    private static var cache: [String: TitleAwardsLoad] = [:]
    @ObservationIgnored private let client: TitleAwardsClient

    init(client: TitleAwardsClient = TitleAwardsClient(transport: TitleAwardsHTTPTransport())) {
        self.client = client
    }

    func refresh(imdbID: String?, isSeries: Bool) async {
        guard let imdbID, TitleAwardParser.isTitleID(imdbID) else {
            result = nil
            return
        }
        let key = imdbID + (isSeries ? "|series" : "|movie")
        if let cached = Self.cache[key] {
            result = cached
            return
        }
        let loaded = await client.load(imdbID: imdbID, isSeries: isSeries)
        guard !Task.isCancelled else { return }
        if loaded.complete { Self.cache[key] = loaded }
        result = loaded
    }
}

/// The awards block for a title's detail page. It shows nothing while loading or when Wikidata has no awards, as Desktop does.
struct TitleAwardsSection: View {
    let imdbID: String?
    let isSeries: Bool
    @State private var model = TitleAwardsModel()

    var body: some View {
        Group {
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(DesktopInterfaceText.value("Awards & Recognition"))
                        .font(HarborTheme.font(17, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(groups, id: \.ceremony) { group in
                        NavigationLink {
                            TitleAwardCeremonyView(group: group)
                        } label: {
                            TitleAwardCeremonyRow(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .accessibilityIdentifier("detail-title-awards")
            }
        }
        .task(id: imdbID) { await model.refresh(imdbID: imdbID, isSeries: isSeries) }
    }

    private var groups: [TitleAwardCeremonyGroup] {
        TitleAwardParser.groups(model.result?.entries ?? [])
    }
}

/// One ceremony in the detail section. Tapping it opens the ceremony's own page.
struct TitleAwardCeremonyRow: View {
    let group: TitleAwardCeremonyGroup

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.ceremony.displayTitle)
                    .font(HarborTheme.font(16, weight: .medium))
                    .foregroundStyle(HarborTheme.ink)
                Text(group.countLine)
                    .font(HarborTheme.font(12, weight: .medium))
                    .foregroundStyle(HarborTheme.ink.opacity(0.6))
                if !group.yearSpan.isEmpty {
                    Text(group.yearSpan)
                        .font(HarborTheme.font(11))
                        .foregroundStyle(HarborTheme.ink.opacity(0.45))
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HarborTheme.ink.opacity(0.4))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The drill-down page for one ceremony: its won rows, then its nominations, as Desktop's `AwardGroup` lists them.
struct TitleAwardCeremonyView: View {
    let group: TitleAwardCeremonyGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(group.countLine)
                    .font(HarborTheme.font(13, weight: .medium))
                    .foregroundStyle(HarborTheme.ink.opacity(0.6))
                rows(group.wins, won: true)
                if !group.nominations.isEmpty {
                    if !group.wins.isEmpty {
                        Text(DesktopInterfaceText.value("Also Nominated"))
                            .font(HarborTheme.font(11, weight: .semibold))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(HarborTheme.ink.opacity(0.5))
                    }
                    rows(group.nominations, won: false)
                }
                if group.wins.isEmpty && group.nominations.isEmpty {
                    Text(DesktopInterfaceText.value("Recognized at the {award}.", variables: ["award": group.ceremony.displayTitle.lowercased()]))
                        .font(HarborTheme.font(14))
                        .foregroundStyle(HarborTheme.ink.opacity(0.6))
                }
            }
            .padding(20)
        }
        .navigationTitle(group.ceremony.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rows(_ entries: [TitleAward], won: Bool) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries.indices, id: \.self) { index in
                    TitleAwardEntryRow(entry: entries[index], won: won)
                }
            }
        }
    }
}

struct TitleAwardEntryRow: View {
    let entry: TitleAward
    let won: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.year.map { String($0) } ?? "–")
                .font(HarborTheme.font(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(won ? HarborTheme.accent : HarborTheme.ink.opacity(0.5))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.category ?? entry.awardName)
                    .font(HarborTheme.font(14, weight: .medium))
                    .foregroundStyle(HarborTheme.ink)
                if !entry.recipients.isEmpty {
                    Text(entry.recipients.joined(separator: ", "))
                        .font(HarborTheme.font(12))
                        .foregroundStyle(HarborTheme.ink.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HarborTheme.ink.opacity(0.08)).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}
