import SwiftUI

/// Desktop's provider keys for ratings (OMDb, MDBList) and the Details column of its ratings matrix
/// (`library-panel/provider-keys.tsx`, `ratings-matrix.tsx`). The Cards column lives in `CardBadgesSettingsView`.
struct RatingProvidersSettingsView: View {
    @State private var store: ProviderKeyStore
    @Bindable private var interface = InterfacePreferences.shared
    @State private var loadFailed = false
    private let owner: String
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    init(owner: String) { self.owner = owner; _store = State(initialValue: ProviderKeyStore.forOwner(owner)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection(text("Set up rating providers"),
                                      note: text("Choose which ratings appear on cards and detail pages. Locked card ratings need a provider key in Metadata.")) {
                    ForEach([ProviderKeyStore.Provider.omdb, .mdblist], id: \.self) { provider in
                        RatingProviderKeyField(store: store, provider: provider)
                    }
                    if loadFailed { Button(text("Retry")) { load() }.frame(minHeight: 44).accessibilityIdentifier("rating-keys-reload") }
                }
                HarborSettingsSection(text("Cards"), note: text("The little score chip printed on poster cards across your rows and grids.")) {
                    NavigationLink { CardBadgesSettingsView(owner: owner).toolbar(.visible, for: .navigationBar) } label: {
                        SettingsRow(title: text("Cards"), icon: "nav-catalogs")
                    }.background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12)).accessibilityIdentifier("rating-cards-settings")
                }
                HarborSettingsSection(text("Details"), note: text("The ratings row on a title's detail page, next to runtime and genre.")) {
                    ForEach(DetailRatings.sources) { source in
                        HarborSettingsToggle(source.name, isOn: Binding(get: { !interface.detailRatingsHidden.contains(source.id) }, set: { shown in
                            if shown { interface.detailRatingsHidden.remove(source.id) } else { interface.detailRatingsHidden.insert(source.id) }
                        })).accessibilityIdentifier("ratings-detail-" + source.id)
                    }
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Set up rating providers")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("rating-providers-scroll").task { load() }
    }

    private func load() { do { try store.load(); loadFailed = false } catch { loadFailed = true } }
}

private struct RatingProviderKeyField: View {
    let store: ProviderKeyStore
    let provider: ProviderKeyStore.Provider
    @State private var draft = ""
    @State private var revealed = false
    @State private var error: String?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private var name: String { provider == .omdb ? "OMDb" : "MDBList" }
    private var summary: String { text(provider == .omdb ? "Real IMDb and Rotten Tomatoes scores." : "Letterboxd, Trakt, Metacritic, and audience scores.") }
    private var placeholder: String { text(provider == .omdb ? "8-character key" : "mdblist api key") }
    private var help: String {
        provider == .omdb
            ? text("They email an activation link the first time. Click it, then come back and save.")
            : text("Adds Letterboxd and Trakt community ratings to detail pages, covering what OMDb misses.")
    }
    private var site: (title: String, url: URL?) {
        provider == .omdb ? ("omdbapi.com/apikey.aspx", URL(string: "https://www.omdbapi.com/apikey.aspx")) : ("mdblist.com", URL(string: "https://mdblist.com/preferences/"))
    }
    private var saved: String { store.key(provider) }
    private var dirty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines) != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(name).font(HarborTheme.font(16, weight: .semibold))
                Circle().fill(saved.isEmpty ? Color.secondary.opacity(0.4) : Color.green).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(text(saved.isEmpty ? "Not set" : "Saved")).font(.footnote).foregroundStyle(.secondary)
            }
            Text(summary).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Group {
                    if revealed { TextField(placeholder, text: $draft) } else { SecureField(placeholder, text: $draft) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().submitLabel(.done).onSubmit { save() }
                    .accessibilityIdentifier("rating-key-\(provider.rawValue)")
                if !draft.isEmpty {
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(text(revealed ? "Hide" : "Show"))
                }
            }.padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
            HStack(spacing: 14) {
                Button(text(dirty || saved.isEmpty ? "Save" : "Saved")) { save() }
                    .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!dirty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("rating-key-save-\(provider.rawValue)")
                if !saved.isEmpty {
                    Button(text("Remove"), role: .destructive) { remove() }.frame(minHeight: 44).accessibilityIdentifier("rating-key-remove-\(provider.rawValue)")
                }
                Spacer(minLength: 0)
                if let url = site.url { Link(site.title, destination: url).font(.footnote).underline().frame(minHeight: 44) }
            }
            Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(14).background(HarborTheme.surface.opacity(0.5), in: .rect(cornerRadius: 12))
        .task(id: saved) { draft = saved }
    }

    private func save() {
        do { try store.set(draft, for: provider); error = nil; keyChanged() } catch { self.error = safeMessage(error) }
    }
    private func remove() {
        do { try store.set("", for: provider); draft = ""; error = nil; keyChanged() } catch { self.error = safeMessage(error) }
    }
    /// A new OMDb key starts a fresh daily allowance, as on Desktop.
    private func keyChanged() {
        if provider == .omdb { Task { await OmdbService.shared.resetBudget() } }
    }
}

/// The scores row on a title's detail page: Rotten Tomatoes, Letterboxd, Metacritic, Trakt, SIMKL and MDBList.
struct DetailProviderRatings: View {
    let media: Media
    let owner: String
    @State private var store: ProviderKeyStore
    @State private var omdb: OmdbScores?
    @State private var mdblist: MdblistScores?
    @State private var simklRating: Double?
    @Environment(\.openURL) private var openURL

    init(media: Media, owner: String) {
        self.media = media; self.owner = owner; _store = State(initialValue: ProviderKeyStore.forOwner(owner))
    }

    private var imdbID: String? { [media.id, media.imdbID ?? ""].first { $0.range(of: "^tt[0-9]+$", options: .regularExpression) != nil } }
    private var items: [DetailRatings.Item] {
        let hidden = InterfacePreferences.shared.detailRatingsHidden
        let others = DetailRatings.items(omdb: omdb, mdblist: mdblist, simkl: simklRating, imdbID: imdbID, isShow: media.type != "movie", hidden: hidden)
        // An anime's primary rating on Desktop is MyAnimeList's catalog score (`hero-ratings.tsx`).
        guard let mal = CardTagPolicy.malDetailItem(media, detailHidden: hidden) else { return others }
        return [mal] + others
    }

    var body: some View {
        Group {
            if !items.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            let label = DesktopInterfaceText.value(item.label)
                            Button { if let link = item.link { openURL(link) } } label: {
                                HStack(spacing: 6) {
                                    Text(DetailRatings.shortName(item.id)).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                                    Text(item.value).font(HarborTheme.font(12, weight: .semibold))
                                        .padding(.horizontal, item.id == "metacritic" ? 5 : 0)
                                        .background(item.id == "metacritic" ? band(item.value) : .clear, in: .rect(cornerRadius: 3))
                                        .foregroundStyle(item.id == "metacritic" ? Color.black : HarborTheme.ink)
                                }.padding(.horizontal, 10).padding(.vertical, 5).background(HarborTheme.background.opacity(0.85), in: .capsule)
                            }.buttonStyle(.plain).disabled(item.link == nil).accessibilityLabel(label + " " + item.value)
                                .accessibilityIdentifier("detail-rating-" + item.id)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
        .task(id: media.identity + "|" + store.keys.values.sorted().joined(separator: ",")) { await load() }
    }

    private func band(_ value: String) -> Color {
        switch DetailRatings.metacriticBand(Int(value) ?? 0) {
        case "green": .green
        case "amber": .orange
        default: .red
        }
    }

    private func load() async {
        do { if !store.ready { try store.load() } } catch { return }
        omdb = nil; mdblist = nil; simklRating = nil
        guard let imdbID else { return }
        let omdbKey = store.key(.omdb), mdblistKey = store.key(.mdblist), show = media.type != "movie"
        async let first = Self.omdbScores(key: omdbKey, imdbID: imdbID)
        async let second = Self.mdblistScores(key: mdblistKey, imdbID: imdbID, show: show)
        async let third = SimklCommunityRatings.shared.rating("imdb:" + imdbID)
        let (found, others, community) = await (first, second, third)
        guard !Task.isCancelled else { return }
        omdb = found; mdblist = others; simklRating = community
    }

    /// Desktop's detail page asks OMDb without a type: an extra one can turn a hit into a miss, and a miss costs a request.
    private static func omdbScores(key: String, imdbID: String) async -> OmdbScores? {
        if key.isEmpty { return nil }
        return await OmdbService.shared.scores(key: key, imdbID: imdbID)
    }
    private static func mdblistScores(key: String, imdbID: String, show: Bool) async -> MdblistScores? {
        if key.isEmpty { return nil }
        return await MdblistService.shared.scores(key: key, imdbID: imdbID, type: show ? "show" : "movie")
    }
}
