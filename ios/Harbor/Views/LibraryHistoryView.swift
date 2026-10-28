import SwiftUI

struct LibraryHistoryContent: View {
    let app: AppModel
    let model: LibraryHistoryModel
    var metadata: (@MainActor (Media) async throws -> Media)? = nil
    private var display: LibraryDisplay { model.library.presentation.display }
    @State private var query = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    private func text(_ key: String, variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables, language: locale.identifier) }
    var body: some View {
        let entries = model.entries, indexed = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let records = LibraryListing.select(entries.map(\.listingRecord), display: historyDisplay, query: query)
        let groups = LibraryListing.groups(records, display: historyDisplay)
        VStack(alignment: .leading, spacing: 18) {
            if !entries.isEmpty { controls(entries) }
            HStack(spacing: 10) {
                Text(model.loading && entries.isEmpty ? text("Loading your history…") : text(entries.count == 1 ? "{n} item" : "{n} items", variables: ["n": String(entries.count)]))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("library-history-count")
                if model.loading && !entries.isEmpty { ProgressView().controlSize(.small) }
                Spacer()
                Button { Task { await model.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.disabled(model.loading).accessibilityLabel(text("Refresh")).accessibilityIdentifier("library-history-refresh")
            }
            if model.loading && entries.isEmpty { LibraryHistorySkeleton() }
            else if entries.isEmpty { emptyState }
            else if records.isEmpty { Text(text("No matches for these filters.")).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100).accessibilityIdentifier("library-history-no-matches") }
            else {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 14) {
                            if !group.title.isEmpty { Text(text(LibraryListing.sourceGroupTitle(group.title)).uppercased() + "  \(group.items.count)").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(.secondary) }
                            if display.historyView == .episodes {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 22) {
                                    ForEach(group.items) { record in if let entry = indexed[record.id] { card(entry, episodes: true) } }
                                }
                            } else {
                                PosterGrid(spacing: 22) { ForEach(group.items) { record in if let entry = indexed[record.id] { card(entry, episodes: false) } } }
                            }
                        }
                    }
                }.id(display.historyView).modifier(HistoryEntrance(reduceMotion: reduceMotion))
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text(error)).font(.caption).foregroundStyle(.orange)
                    Button(text("Retry")) { Task { await model.refresh(force: true) } }.frame(minHeight: 44)
                }.accessibilityIdentifier("library-history-error")
            }
        }.accessibilityIdentifier("library-history-content")
            .task(id: model.account.identity) { await model.refresh() }.onDisappear { model.cancel() }
    }
    private var historyDisplay: LibraryDisplay { var value = display; value.filter = .watched; return value }
    private func card(_ entry: LibraryHistoryEntry, episodes: Bool) -> some View {
        LibraryHistoryCard(app: app, model: model, entry: entry, episodes: episodes, metadata: metadata)
    }
    private func controls(_ entries: [LibraryHistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(LibraryKind.allCases) { kind in
                        let count = entries.filter { kind == .all || $0.media?.type == kind.rawValue }.count
                        HarborPill(title: text(kind.sourceTitle) + "  \(count)", selected: display.kind == kind) { model.library.changeDisplay { $0.kind = kind } }
                            .accessibilityIdentifier("library-history-kind-" + kind.rawValue)
                    }
                }
            }.scrollIndicators(.hidden)
            HarborSearchField(prompt: text("Search title…"), text: $query, dismissOnSubmit: true).accessibilityIdentifier("library-history-search")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(LibraryHistoryView.allCases) { mode in
                        HarborPill(title: text(mode.title), selected: display.historyView == mode) { model.library.changeDisplay { $0.historyView = mode } }
                            .accessibilityIdentifier("library-history-view-" + mode.rawValue)
                    }
                    Divider().frame(height: 24).padding(.horizontal, 5)
                    ForEach(LibrarySort.allCases) { sort in
                        HarborPill(title: text(sort.sourceTitle), selected: display.sort == sort) { model.library.changeDisplay { $0.sort = sort } }
                    }
                    if display.sort == .recent {
                        Divider().frame(height: 24).padding(.horizontal, 5)
                        HarborPill(title: text("Grouped"), selected: display.grouped) { model.library.changeDisplay { $0.grouped = true } }
                        HarborPill(title: text("One list"), selected: !display.grouped) { model.library.changeDisplay { $0.grouped = false } }
                    }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("library-history-options")
        }.disabled(!model.library.canChangePresentation)
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(text("Nothing watched yet")).font(.headline)
            Text(text("Press play on something. It'll show up here once you start watching.")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 56)
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
            .accessibilityIdentifier("library-history-empty")
    }
}

private struct HistoryEntrance: ViewModifier {
    let reduceMotion: Bool
    var delay = 0.0
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(reduceMotion || shown ? 1 : 0).offset(y: reduceMotion || shown ? 0 : 10)
            .onAppear { withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.44).delay(delay)) { shown = true } }
    }
}
private struct LibraryHistorySkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach([14, 8], id: \.self) { count in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(HarborTheme.ink.opacity(0.08)).frame(width: 96, height: 12).modifier(HistorySweep(cornerRadius: 3))
                    PosterGrid(spacing: 22) {
                        ForEach(0..<count, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 12).fill(HarborTheme.ink.opacity(0.08)).aspectRatio(2.0 / 3, contentMode: .fit).modifier(HistorySweep())
                                RoundedRectangle(cornerRadius: 3).fill(HarborTheme.ink.opacity(0.08)).frame(height: 10).padding(.trailing, 24).modifier(HistorySweep(cornerRadius: 3))
                            }.modifier(HistoryEntrance(reduceMotion: reduceMotion, delay: Double(min(index, 12)) * 0.035))
                        }
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}
private struct HistorySweep: ViewModifier {
    var cornerRadius: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sweep = false
    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion && scenePhase == .active {
                GeometryReader { bounds in
                    LinearGradient(stops: [.init(color: .clear, location: 0.25), .init(color: .white.opacity(0.07), location: 0.5), .init(color: .clear, location: 0.75)], startPoint: .init(x: 0, y: 0.41), endPoint: .init(x: 1, y: 0.59))
                        .offset(x: bounds.size.width * (sweep ? 1 : -1))
                        .onAppear { sweep = false; withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) { sweep = true } }
                        .onDisappear { sweep = false }
                }
            }
        }.clipShape(.rect(cornerRadius: cornerRadius))
    }
}
private struct LibraryHistoryCard: View {
    let app: AppModel
    let model: LibraryHistoryModel
    let entry: LibraryHistoryEntry
    let episodes: Bool
    let metadata: (@MainActor (Media) async throws -> Media)?
    @State private var hydrated: Media?
    @State private var confirm = false
    @Environment(\.locale) private var locale
    private var media: Media? { hydrated ?? entry.media }
    private var episode: Episode? { hydrated?.videos?.first { $0.season == entry.season && $0.episode == entry.episode } }
    private func text(_ key: String, variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables, language: locale.identifier) }
    private var episodeCaption: String? {
        guard let hint = entry.episodeHint else { return nil }
        return text("S{season} E{episode}", variables: ["season": String(hint.season ?? 0), "episode": String(hint.episode ?? 0)])
    }
    var body: some View {
        Group {
            if let media {
                NavigationLink { DetailView(media: media, app: app, metadataLoaded: hydrated != nil, episodeHint: entry.episodeHint) } label: {
                    if episodes { episodeCard(media) } else { Poster(media: media, width: nil) }
                }.buttonStyle(.plain).accessibilityLabel(media.name).accessibilityIdentifier("library-history-media")
                    .accessibilityValue(episodes ? episodeCaption ?? "" : "")
                    .overlay(alignment: .topTrailing) {
                        if entry.localID != nil {
                            Button { confirm = true } label: {
                                Image(systemName: "trash").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 28, height: 28).background(.black.opacity(0.8), in: .circle).frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.library.busy).accessibilityLabel(text("Remove from history") + ": " + media.name).accessibilityIdentifier("library-history-remove")
                        }
                    }
                    .confirmationDialog(text("Confirm remove from history"), isPresented: $confirm, titleVisibility: .visible) {
                        Button(text("Remove"), role: .destructive) { Task { await model.remove(entry) } }
                        Button(text("Cancel"), role: .cancel) { }
                    }
                    .task(id: app.accountOperationScope + "|" + media.identity) {
                        let scope = app.accountOperationScope
                        let value: Media?
                        if let metadata { value = try? await metadata(media) } else { value = try? await app.continuationMetadata(media) }
                        guard var value, !Task.isCancelled, scope == app.accountOperationScope else { return }
                        value.id = media.id; hydrated = value
                        if episodes && media.episodic && metadata == nil {
                            value.videos = await AnimeEpisodeService.shared.episodes(for: value, grouping: .seasons)
                            guard !Task.isCancelled, scope == app.accountOperationScope else { return }; hydrated = value
                        }
                    }
            }
        }
    }
    private func episodeCard(_ media: Media) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(url: episode?.thumbnail ?? media.background, fallback: media.poster, maxPixels: 500)
                .aspectRatio(16 / 9, contentMode: .fit).clipped()
                .overlay(alignment: .bottomLeading) {
                    if entry.watched || !remaining.isEmpty {
                        Label(entry.watched ? text("Watched") : remaining, systemImage: entry.watched ? "arrow.counterclockwise" : "play.fill")
                            .font(HarborTheme.font(11, weight: .medium)).foregroundStyle(entry.watched ? Color.green : Color.white)
                            .padding(.horizontal, 8).padding(.vertical, 5).background(HarborTheme.background.opacity(0.95), in: .rect(cornerRadius: 6)).padding(8)
                    }
                }.overlay(alignment: .bottom) {
                    if entry.progress > 0 { GeometryReader { bounds in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.black.opacity(0.4)); Rectangle().fill(HarborTheme.accent).frame(width: bounds.size.width * CGFloat(entry.progress))
                        }
                    }.frame(height: 4) }
                }.clipShape(.rect(cornerRadius: 12))
            if let caption = episodeCaption {
                Text(media.name.uppercased()).font(HarborTheme.font(10, weight: .semibold)).tracking(1).foregroundStyle(.secondary).lineLimit(1)
                Text(caption + (episode?.name.map { " — " + $0 } ?? "")).font(HarborTheme.font(13, weight: .medium)).lineLimit(1)
            } else { Text(media.name).font(HarborTheme.font(13, weight: .medium)).lineLimit(1) }
            if let date = entry.watchedAt { Text(Date(timeIntervalSince1970: date / 1_000), format: .dateTime.month(.twoDigits).day(.twoDigits).year()).font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private var remaining: String {
        guard entry.durationMs > 0, !entry.watched else { return "" }
        let value = max(0, ((entry.durationMs - entry.timeOffsetMs) / 60_000).rounded())
        guard value.isFinite, value < Double(Int.max) else { return "" }; let minutes = Int(value)
        if minutes < 60 { return text("{m}m left", variables: ["m": String(minutes)]) }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? text("{h}h left", variables: ["h": String(hours)]) : text("{h}h {m}m left", variables: ["h": String(hours), "m": String(rest)])
    }
}
