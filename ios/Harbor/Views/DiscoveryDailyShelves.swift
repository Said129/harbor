import SwiftUI

struct DiscoveryDailyShelves: View {
    let app: AppModel
    let awards: [Media]
    let featuredIDs: Set<String>
    let refreshRevision: Int
    @AppStorage("uiLanguage") private var uiLanguage = "es"
    @State private var definitions: [DiscoveryDailyRow] = []
    @State private var activeSignature = ""
    @State private var filter: DiscoveryDailyFeed.Filter?
    @State private var loaded: [String: [Media]] = [:]
    @State private var pages: [String: Int] = [:]
    @State private var exhausted = Set<String>()
    @State private var failed = Set<String>()
    @State private var requests: [String: UUID] = [:]

    private var services: [StreamingServiceDefinition] { StreamingPreferences.forOwner(app.settingsOwner).enabled }
    private var configuration: MetadataConfiguration { MetadataPreferences.shared.configuration() }
    private var languages: [String] { SubtitleLanguages.preferredCodes(StreamPreferences.shared.streamLanguages) }
    private var signature: String {
        let metadata = configuration
        let key = DiscoveryDailyFeed.signature(tmdbKey: metadata.tmdbKey, tasteRevision: app.library.discovery.revision,
            region: metadata.region, enabledServices: services, preferredLanguages: languages, metadataLanguage: metadata.language,
            feedLocaleBias: InterfacePreferences.shared.feedLocaleBias, uiLanguage: uiLanguage, translateTitles: metadata.translateTitles,
            owner: app.accountOperationScope)
        return "\(key)|\(app.storageReady)|\(refreshRevision)"
    }

    var body: some View {
        let signature = signature
        LazyVStack(alignment: .leading, spacing: 24) {
            if activeSignature == signature, let filter {
                let ranked = visibleRows(filter: filter)
                ForEach(definitions) { row in
                    let items = ranked[row.id]
                    if let items, !items.isEmpty {
                        shelf(row, items: items, filter: filter, scope: app.accountOperationScope)
                    } else if row.endpoint != .awards, items == nil, !failed.contains(row.id) {
                        placeholder(row).task(id: signature) { await load(row, page: 1) }
                    }
                }
            }
        }.frame(minHeight: activeSignature == signature ? 0 : 1)
            .accessibilityIdentifier("discover-daily-shelves")
            .task(id: signature) {
                guard app.storageReady, !Task.isCancelled else { return }
                configure(signature)
            }
    }

    private func visibleRows(filter: DiscoveryDailyFeed.Filter) -> [String: [Media]] {
        var raw = loaded
        if let row = definitions.first(where: { $0.endpoint == .awards }) {
            raw[row.id] = filter.eligible(awards)
        }
        return DiscoveryDailyFeed.deduplicatedRows(rows: definitions, loaded: raw, featuredIDs: featuredIDs)
    }

    private func configure(_ signature: String) {
        guard activeSignature != signature else { return }
        let preferences = app.library.discovery
        let now = Date()
        let configuration = configuration
        let affinity = preferences.affinity(now: now)
        let downvotes = preferences.votes.compactMap { entry -> DiscoveryAffinityRules.Downvote? in
            guard entry.value.vote == .down else { return nil }
            return .init(id: entry.key, titleKey: DiscoveryPreferences.titleKey(entry.value.name))
        }
        let upvoted = Set(preferences.votes.filter { $0.value.vote == .up }.map(\.key))
        let locale = DiscoveryAffinityRules.localeBias(preferredLanguages: languages, metadataLanguage: configuration.language,
            region: configuration.region, enabled: InterfacePreferences.shared.feedLocaleBias)
        filter = .init(downvotes: downvotes, upvoted: upvoted,
            history: .init(StreamPlaybackHistory.remembered(owner: app.library.owner, now: now)), affinity: affinity, locale: locale)
        let base = DiscoveryFeedRandom.dayIndex(now)
        let recent = DiscoveryDailyFeedHistory.recentKeys(owner: app.personalOwner, base: base)
        definitions = DiscoveryDailyFeed.rows(tmdbKey: configuration.tmdbKey, affinity: affinity, region: configuration.region,
                                               enabledServices: services, now: now, recent: recent)
        if configuration.tmdbKey.isEmpty { definitions.append(DiscoveryDailyFeed.awardRow(base: base)) }
        loaded = [:]; pages = [:]; requests = [:]; exhausted = []; failed = []
        activeSignature = signature
    }

    private func load(_ row: DiscoveryDailyRow, page: Int) async {
        let expectedSignature = activeSignature
        guard expectedSignature == signature, let filter, requests[row.id] == nil,
              !exhausted.contains(row.id), page == (pages[row.id] ?? 0) + 1, page <= 10 else { return }
        let request = UUID()
        requests[row.id] = request
        failed.remove(row.id)
        defer { if requests[row.id] == request { requests[row.id] = nil } }
        if page == 1 {
            DiscoveryDailyFeedHistory.record(owner: app.personalOwner, base: DiscoveryFeedRandom.dayIndex(Date()), row: row.id)
        }
        do {
            let incoming = try await DiscoveryDailyFeed.fetch(row, page: page, configuration: configuration, filter: filter)
            try Task.checkCancellation()
            guard expectedSignature == activeSignature, expectedSignature == signature, requests[row.id] == request else { return }
            var current = loaded[row.id] ?? []
            var ids = Set(current.map(\.id))
            let fresh = incoming.filter { ids.insert($0.id).inserted }
            current.append(contentsOf: fresh)
            loaded[row.id] = current
            pages[row.id] = page
            if incoming.count < 4 || fresh.isEmpty || page == 10 || row.endpoint.isSinglePage { exhausted.insert(row.id) }
        } catch {
            guard !Task.isCancelled, expectedSignature == activeSignature, expectedSignature == signature else { return }
            failed.insert(row.id)
        }
    }

    private func shelf(_ row: DiscoveryDailyRow, items: [Media], filter: DiscoveryDailyFeed.Filter, scope: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                heading(row)
                Spacer(minLength: 4)
                NavigationLink(DesktopInterfaceText.value("View all")) {
                    DiscoveryGrid(rail: gridRail(row, items: items, filter: filter, scope: scope), app: app)
                        .toolbar(.visible, for: .navigationBar)
                }.font(HarborTheme.font(12)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("discover-daily-browse-" + row.id)
            }.padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items, id: \.identity) { media in
                        NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain)
                    }
                    if let page = pages[row.id], !exhausted.contains(row.id) {
                        if failed.contains(row.id) {
                            Button(DesktopInterfaceText.value("Retry")) { Task { await load(row, page: page + 1) } }
                                .frame(minWidth: 70, minHeight: 44)
                        } else {
                            Color.clear.frame(width: 10, height: 1).id(page)
                                .task { await load(row, page: page + 1) }
                        }
                    }
                }.padding(.horizontal)
            }.scrollIndicators(.hidden).posterRowBehavior()
        }
    }

    private func gridRail(_ row: DiscoveryDailyRow, items: [Media], filter: DiscoveryDailyFeed.Filter, scope: String) -> DiscoveryRail {
        let configuration = configuration
        var rail = row.rail
        rail.personal = .init(available: { app.accountOperationScope == scope }, page: { page in
            guard page <= 10, app.accountOperationScope == scope else { return [] }
            if row.endpoint.isSinglePage { return page == 1 ? items : [] }
            return try await DiscoveryDailyFeed.fetch(row, page: page, configuration: configuration, filter: filter)
        })
        return rail
    }

    private func heading(_ row: DiscoveryDailyRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.rail.title).font(HarborTheme.font(18, weight: .semibold))
            if let kicker = row.kicker { Text(kicker).font(HarborTheme.font(12)).foregroundStyle(.secondary) }
        }.accessibilityAddTraits(.isHeader)
    }

    private func placeholder(_ row: DiscoveryDailyRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(row)
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 10).fill(HarborTheme.surface).frame(width: 104, height: 156) }
            }.accessibilityHidden(true)
        }.padding(.horizontal)
    }
}

private extension DiscoveryDailyEndpoint {
    var isSinglePage: Bool {
        switch self {
        case .awards, .cinemeta: true
        case .discover, .trending: false
        }
    }
}
