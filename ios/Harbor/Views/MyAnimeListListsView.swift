import SwiftUI

/// Desktop's MyAnimeList lists (`views/library/mal-tab.tsx`). Read-only: status, progress and removal edits
/// (`lib/mal/mutations.ts`) are not ported yet.
struct MyAnimeListListsView: View {
    let app: AppModel
    @State private var account: MALAccount
    @State private var entries: [MALListEntry] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var kind = MALListKind.all
    @State private var query = ""
    @Environment(\.locale) private var locale

    @MainActor init(app: AppModel) {
        self.app = app
        _account = State(initialValue: MALAccount.forOwner(app.personalOwner))
    }

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key, language: locale.identifier) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if account.session == nil {
                    Text(text("Not connected")).foregroundStyle(.secondary)
                } else {
                    content
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HarborTheme.background)
        .foregroundStyle(HarborTheme.ink)
        .navigationTitle("MyAnimeList")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("mal-lists-scroll")
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if loading && entries.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text(text("Loading your MyAnimeList…")).foregroundStyle(.secondary)
            }
        } else if loadFailed && entries.isEmpty {
            errorBlock
        } else if entries.isEmpty {
            emptyBlock
        } else {
            filters
            sections
        }
    }

    private var errorBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Couldn't reach MyAnimeList. Try refreshing."))
                .font(.callout).foregroundStyle(.orange)
                .accessibilityIdentifier("mal-lists-error")
            Button(text("Retry")) { Task { await load() } }
                .frame(minHeight: 44)
                .accessibilityIdentifier("mal-lists-retry")
        }
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("Your MyAnimeList is empty")).font(HarborTheme.font(20, weight: .medium))
            Text(text("Add anime to your MyAnimeList and they show up here, grouped by status and ready to edit."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HarborSearchField(prompt: text("Search title…"), text: $query, dismissOnSubmit: true)
                .accessibilityIdentifier("mal-lists-search")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(MALListKind.allCases, id: \.self) { option in
                        HarborPill(title: pillTitle(option), selected: kind == option) { kind = option }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func pillTitle(_ option: MALListKind) -> String {
        let count = MALLists.count(entries, kind: option, query: query)
        return text(option.title) + " " + String(count)
    }

    private var sections: some View {
        ForEach(MALLists.groups(entries, kind: kind, query: query), id: \.section) { group in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(text(group.section.title)).font(HarborTheme.font(18, weight: .semibold))
                    Text(String(group.entries.count)).font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(group.entries, id: \.media.id) { entry in
                        if let media = MALLists.harborMedia(entry.media) {
                            listCard(entry, media)
                        }
                    }
                }
            }
        }
    }

    private func listCard(_ entry: MALListEntry, _ media: Media) -> some View {
        NavigationLink { DetailView(media: media, app: app) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Poster(media: media, width: nil)
                Text(media.name).font(HarborTheme.font(13, weight: .medium)).lineLimit(2)
                Text(MALLists.progressLabel(entry)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mal-list-entry")
    }

    /// Desktop's `fetchMalList`, after a session that has expired is refreshed first.
    private func load() async {
        if !account.ready { try? account.load() }
        guard let session = account.session else { return }
        loading = true
        loadFailed = false
        var token = session.accessToken
        let owner = account
        if !session.isActive(), let renewed = await owner.refresh() { token = renewed }
        do {
            let client = MALClient(transport: MALHTTPTransport())
            entries = try await MALListsService.fetchAll(token: token, client: client, refresh: { await owner.refresh() })
        } catch {
            loadFailed = true
        }
        loading = false
    }
}
