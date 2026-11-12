import SwiftUI

/// Desktop's AniList lists (`views/library/anilist-tab.tsx`) and its recommended rail (`lib/use-anilist-anime-rails.ts`).
/// Each card's menu changes the status, moves the episode count on or removes the entry (`TrackerListEdit`).
struct AniListListsView: View {
    let app: AppModel
    @State private var account: AniListAccount
    @State private var entries: [AniListListEntry] = []
    @State private var recommended: [Media] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var actionFailed = false
    @State private var kind = AniListListKind.all
    @State private var query = ""
    @Environment(\.locale) private var locale

    @MainActor init(app: AppModel) {
        self.app = app
        _account = State(initialValue: AniListAccount.forOwner(app.personalOwner))
    }

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key, language: locale.identifier) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if account.session == nil {
                    Text(text("Browse your anime lists in Harbor and update your episode progress as you watch. Sign in to AniList to connect."))
                        .foregroundStyle(.secondary)
                } else {
                    if actionFailed {
                        Text(text("Couldn't reach AniList. Try refreshing.")).font(.callout).foregroundStyle(.orange)
                            .accessibilityIdentifier("anilist-list-action-error")
                    }
                    content
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HarborTheme.background)
        .foregroundStyle(HarborTheme.ink)
        .navigationTitle("AniList")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("anilist-lists-scroll")
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if loading && entries.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text(text("Loading your AniList…")).foregroundStyle(.secondary)
            }
        } else if loadFailed && entries.isEmpty {
            errorBlock
        } else if entries.isEmpty {
            emptyBlock
        } else {
            recommendations
            filters
            sections
        }
    }

    private var errorBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Couldn't reach AniList. Try refreshing."))
                .font(.callout).foregroundStyle(.orange)
                .accessibilityIdentifier("anilist-lists-error")
            Button(text("Retry")) { Task { await load() } }
                .frame(minHeight: 44)
                .accessibilityIdentifier("anilist-lists-retry")
        }
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("Your AniList is empty")).font(HarborTheme.font(20, weight: .medium))
            Text(text("Add anime to your AniList and they show up here, grouped by status and ready to edit."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var recommendations: some View {
        if !recommended.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(text("Recommended for you")).font(HarborTheme.font(18, weight: .semibold))
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(recommended, id: \.identity) { media in
                            NavigationLink { DetailView(media: media, app: app) } label: { Poster(media: media) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("anilist-recommendation")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HarborSearchField(prompt: text("Search title…"), text: $query, dismissOnSubmit: true)
                .accessibilityIdentifier("anilist-lists-search")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(AniListListKind.allCases, id: \.self) { option in
                        HarborPill(title: pillTitle(option), selected: kind == option) { kind = option }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func pillTitle(_ option: AniListListKind) -> String {
        let count = AniListLists.count(entries, kind: option, query: query)
        return text(option.title) + " " + String(count)
    }

    private var sections: some View {
        ForEach(AniListLists.groups(entries, kind: kind, query: query), id: \.section) { group in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(text(group.section.title)).font(HarborTheme.font(18, weight: .semibold))
                    Text(String(group.entries.count)).font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(group.entries, id: \.media.id) { entry in
                        if let media = AniListLists.harborMedia(entry.media) {
                            listCard(entry, media)
                        }
                    }
                }
            }
        }
    }

    private func listCard(_ entry: AniListListEntry, _ media: Media) -> some View {
        NavigationLink { DetailView(media: media, app: app) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Poster(media: media, width: nil)
                Text(media.name).font(HarborTheme.font(13, weight: .medium)).lineLimit(2)
                Text(AniListLists.progressLabel(entry)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { entryMenu(entry) }
        .accessibilityIdentifier("anilist-list-entry")
    }

    /// Desktop's entry menu: each status, the next episode, and removal from the list.
    @ViewBuilder private func entryMenu(_ entry: AniListListEntry) -> some View {
        ForEach(TrackerListEdit.aniListChoices, id: \.status) { choice in
            Button(text(choice.label)) {
                Task { await perform { token, client in try await TrackerListEdit.aniListSave(mediaID: entry.media.id, status: choice.status, token: token, client: client) } }
            }
        }
        if let next = TrackerListEdit.nextProgress(entry.progress, total: entry.media.episodes) {
            Button(text("Mark next episode")) {
                Task { await perform { token, client in try await TrackerListEdit.aniListProgress(mediaID: entry.media.id, progress: next, token: token, client: client) } }
            }
        }
        Button(text("Remove from list"), role: .destructive) {
            Task { await perform { token, client in try await TrackerListEdit.aniListRemove(mediaID: entry.media.id, token: token, client: client) } }
        }
    }

    /// Runs one list edit with the stored token, then reloads the lists. A rejected token is validated, as on load.
    private func perform(_ operation: (String, AniListClient) async throws -> Void) async {
        guard let session = account.session else { return }
        let client = AniListClient(transport: AniListHTTPTransport())
        do {
            try await operation(session.accessToken, client)
            actionFailed = false
            await load()
        } catch {
            if let apiError = error as? AniListAPIError, apiError.isAuthenticationError { await account.validate() }
            actionFailed = true
        }
    }

    /// Loads the lists first, then the recommended rail, as Desktop's rails hook does: the lists never wait for it.
    private func load() async {
        if !account.ready { try? account.load() }
        guard let session = account.session else { return }
        loading = true
        loadFailed = false
        let client = AniListClient(transport: AniListHTTPTransport())
        do {
            entries = try await AniListListsService.collection(userID: session.userId, token: session.accessToken, client: client)
            TrackerListProgressStore.forOwner(account.owner).replace(TrackerListWatched.aniListProgress(entries))
        } catch {
            if let apiError = error as? AniListAPIError, apiError.isAuthenticationError { await account.validate() }
            loadFailed = true
            loading = false
            return
        }
        loading = false
        let seeds = AniListLists.recommendationSeeds(entries)
        let excluded = AniListLists.excludedIDs(entries)
        recommended = (try? await AniListListsService.recommendations(seeds: seeds, excluded: excluded, client: client)) ?? []
    }
}
