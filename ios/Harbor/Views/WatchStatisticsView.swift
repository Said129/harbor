import SwiftUI

/// Desktop's Stats screen (`src/views/wrapped.tsx` and `src/views/wrapped/cards.tsx`), computed on this device from the library history.
/// Genres, cast and the title posters from Desktop's network enrichment (`src/lib/wrapped/enrich.ts`) are not ported.
struct WatchStatisticsView: View {
    let app: AppModel
    let history: LibraryHistoryModel
    @Environment(\.locale) private var locale
    private var calendar: Calendar { Calendar.current }

    private func text(_ key: String, variables: [String: String] = [:]) -> String {
        DesktopInterfaceText.value(key, variables: variables, language: locale.identifier)
    }

    /// Nil when there is nothing to count, which shows Desktop's empty state.
    private var current: WatchStatistics? {
        let entries = history.entries
        let events = Self.events(from: entries)
        guard !events.isEmpty else { return nil }
        let remote = entries.contains { $0.localID == nil }
        let year = calendar.component(.year, from: Date())
        return WatchStatistics.resolved(events: events, source: remote ? .trakt : .local, year: year, calendar: calendar)
    }

    var body: some View {
        let snapshot = current
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let stats = snapshot {
                    heroCard(stats)
                    highlightsCard(stats)
                    splitCard(stats)
                    if !stats.topTitles.isEmpty { topTitlesCard(stats) }
                    heatmapCard(stats)
                } else if history.loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    emptyState
                }
            }.padding()
        }
        .background(HarborTheme.background)
        .navigationTitle(text("Stats"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: history.account.identity) { await history.refresh() }
    }

    /// Desktop's `collectWatchEvents`: one event per eligible history entry, with an accurate kind for movies.
    static func events(from entries: [LibraryHistoryEntry]) -> [WatchStatistics.Event] {
        entries.compactMap { entry -> WatchStatistics.Event? in
            guard let media = entry.media, !media.name.isEmpty, let watchedAt = entry.watchedAt, watchedAt > 0 else { return nil }
            let watchKind = kind(of: media)
            return WatchStatistics.Event(id: entry.record.id, title: media.name, kind: watchKind, watchedAt: Date(timeIntervalSince1970: watchedAt / 1_000), poster: media.poster)
        }
    }

    static func kind(of media: Media) -> WatchStatistics.Kind {
        if AnimeLibraryDetection.hasDirectEvidence(media) { return .anime }
        return media.type == "movie" ? .movie : .series
    }

    private func card<Content: View>(tint: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(tint ? HarborTheme.accent.opacity(0.12) : HarborTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func label(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(.secondary)
    }

    private func heroCard(_ stats: WatchStatistics) -> some View {
        card(tint: true) {
            HStack(alignment: .bottom, spacing: 16) {
                statValue(stats.estimatedHours.formatted(), unit: text("hours watched"), big: true)
                statValue(stats.totalTitles.formatted(), unit: text("titles"), big: false)
                statValue(stats.totalPlays.formatted(), unit: text("plays"), big: false)
            }
            if stats.source == .local {
                Text(text("Estimated from your local history. Connect Trakt or Simkl for the full picture."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statValue(_ value: String, unit: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(HarborTheme.displayFont(big ? 56 : 38))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit).font(HarborTheme.font(13)).foregroundStyle(.secondary)
        }
    }

    private func highlightsCard(_ stats: WatchStatistics) -> some View {
        card(tint: true) {
            label(text("Highlights"))
            highlightRow(icon: "sparkles", title: text(stats.archetype.label), body: text(stats.archetype.blurb, variables: stats.archetype.blurbVariables))
            if let binge = stats.longestBinge, binge.count > 1 {
                let count = text("{n} in a day", variables: ["n": String(binge.count)])
                let date = binge.day.formatted(.dateTime.month(.abbreviated).day())
                highlightRow(icon: "flame", title: text("Longest binge"), body: count + " · " + date)
            }
            if let first = stats.firstPlay {
                highlightRow(icon: "calendar.badge.clock", title: text("Where it started"), body: first.title)
            }
        }
    }

    private func highlightRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 36, height: 36)
                .foregroundStyle(HarborTheme.accent)
                .background(HarborTheme.background, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(HarborTheme.font(14, weight: .semibold))
                Text(body).font(HarborTheme.font(13)).foregroundStyle(.secondary)
            }
        }
    }

    private func splitCard(_ stats: WatchStatistics) -> some View {
        let total = Double(max(stats.split.movies + stats.split.series + stats.split.anime, 1))
        return card {
            label(text("What you watched"))
            splitRow(icon: "film", title: text("Movies"), count: stats.split.movies, fraction: Double(stats.split.movies) / total, color: Color(red: 0.22, green: 0.74, blue: 0.97))
            splitRow(icon: "tv", title: text("Series"), count: stats.split.series, fraction: Double(stats.split.series) / total, color: Color(red: 0.65, green: 0.55, blue: 0.98))
            splitRow(icon: "cat.fill", title: text("Anime"), count: stats.split.anime, fraction: Double(stats.split.anime) / total, color: Color(red: 0.20, green: 0.83, blue: 0.60))
        }
    }

    private func splitRow(icon: String, title: String, count: Int, fraction: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
            Text(title).font(HarborTheme.font(13)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(HarborTheme.ink.opacity(0.08))
                    Capsule().fill(color).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 10)
            Text(count.formatted()).font(HarborTheme.font(13, weight: .semibold)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    private func topTitlesCard(_ stats: WatchStatistics) -> some View {
        card {
            label(text("Top titles"))
            ForEach(Array(stats.topTitles.prefix(10).enumerated()), id: \.offset) { index, title in
                topTitleRow(rank: index + 1, title: title)
            }
        }
    }

    static func media(for title: WatchStatistics.TopTitle) -> Media {
        var value = Media(id: title.id, type: title.kind.rawValue, name: title.title)
        value.poster = title.poster
        return value
    }

    private func topTitleRow(rank: Int, title: WatchStatistics.TopTitle) -> some View {
        let media = Self.media(for: title)
        return NavigationLink { DetailView(media: media, app: app) } label: {
            HStack(spacing: 12) {
                Text("\(rank)").font(HarborTheme.displayFont(15)).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                Poster(media: media, width: 36)
                Text(title.title).font(HarborTheme.font(14)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(title.count.formatted()).font(HarborTheme.font(13, weight: .semibold)).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func heatmapCard(_ stats: WatchStatistics) -> some View {
        let columns = heatmapColumns(stats)
        let maximum = max(stats.days.map(\.count).max() ?? 1, 1)
        return card {
            label(text("Your watch year"))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: 3) {
                            ForEach(Array(column.enumerated()), id: \.offset) { _, count in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColor(count, maximum: maximum))
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The last 364 days, oldest first, in weeks of seven like Desktop's grid.
    private func heatmapColumns(_ stats: WatchStatistics) -> [[Int]] {
        let counts = Dictionary(stats.days.map { ($0.day, $0.count) }, uniquingKeysWith: { first, _ in first })
        let today = calendar.startOfDay(for: Date())
        let days: [Date] = (0..<364).reversed().map { offset in
            calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        }
        let values: [Int] = days.map { counts[$0] ?? 0 }
        return stride(from: 0, to: values.count, by: 7).map { start in
            Array(values[start..<min(start + 7, values.count)])
        }
    }

    private func heatColor(_ count: Int, maximum: Int) -> Color {
        if count == 0 { return HarborTheme.ink.opacity(0.08) }
        let ratio = Double(count) / Double(max(maximum, 1))
        if ratio > 0.75 { return HarborTheme.accent }
        if ratio > 0.5 { return HarborTheme.accent.opacity(0.7) }
        if ratio > 0.25 { return HarborTheme.accent.opacity(0.45) }
        return HarborTheme.accent.opacity(0.25)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar").font(.system(size: 26)).foregroundStyle(.secondary)
            Text(text("Nothing to show yet")).font(HarborTheme.displayFont(22)).multilineTextAlignment(.center)
            Text(text("Connect Trakt or Simkl, or start watching, and your stats will build themselves."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
    }
}
