import SwiftUI

/// Desktop's "Cards" column of the ratings matrix and its score position and limit (`ratings-matrix.tsx`,
/// `card-badges-panel.tsx`). A provider whose key is missing is shown off, with Desktop's hint.
struct CardBadgesSettingsView: View {
    @State private var store: ProviderKeyStore
    @Bindable private var interface = InterfacePreferences.shared

    init(owner: String) { _store = State(initialValue: ProviderKeyStore.forOwner(owner)) }

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    /// Turning the bookmark on returns it to Desktop's default corner; Desktop keeps the last corner only for the session.
    private var watchlistOnBinding: Binding<Bool> {
        Binding(get: { interface.watchlistBadge != "off" }, set: { on in interface.watchlistBadge = on ? "topEnd" : "off" })
    }
    /// Desktop's `showMalDetail` is the MAL row of the ratings matrix's Details column, which iOS keeps in `detailRatingsHidden`.
    private var malDetailBinding: Binding<Bool> {
        Binding(get: { !interface.detailRatingsHidden.contains("mal") },
                set: { shown in if shown { interface.detailRatingsHidden.remove("mal") } else { interface.detailRatingsHidden.insert("mal") } })
    }
    private var keys: Set<CardRatingKey> { CardRatingPolicy.keySources(omdb: store.key(.omdb), mdblist: store.key(.mdblist)) }
    private var selected: Set<CardRatingProvider> {
        CardRatingPolicy.selectedProviders(Set(CardRatingProvider.allCases.filter { interface.cardRatingOn($0) }), simklCommunity: interface.simklShowCommunityRatings)
    }
    private var enabledCount: Int { CardRatingPolicy.chipCount(CardRatingPolicy.enabled(selected: selected, keys: keys)) }
    /// Desktop offers limits up to the enabled count, never fewer than 2.
    private var maxChoice: Int { max(2, enabledCount) }
    private var limitChoices: [(String, Int)] { (2...6).filter { $0 <= maxChoice }.map { (String($0), $0) } }
    private var limitSelection: Binding<Int> {
        Binding(get: { min(interface.cardBadgeLimit, maxChoice) }, set: { interface.cardBadgeLimit = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection("Cards", note: "The little score chip printed on poster cards across your rows and grids.") {
                    HarborSettingsChoice("Score position", selection: $interface.badgePlacement,
                                         choices: [("Top", "top"), ("Bottom", "bottom")], identifier: "card-badges-placement")
                    Text(text("Which end of the poster the score chip rides on.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HarborSettingsChoice("Max scores per card", selection: limitSelection, choices: limitChoices,
                                         localizeChoices: false, identifier: "card-badges-limit")
                    Text(DesktopInterfaceText.value("Caps how many score chips a poster shows. Extras drop off the end of the chip. You have {n} turned on.",
                                                    variables: ["n": String(enabledCount)]))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HarborSettingsSection("On the poster") {
                    HarborSettingsToggle("Show tags on cards",
                                         note: "The New, In Cinema, Rerun, and Awards chips. Turn off for a cleaner grid. Score chips are separate, below.",
                                         isOn: $interface.showCardBadges)
                    HarborSettingsToggle("Watchlist bookmark", note: "Puts a small bookmark on posters you have already saved.", isOn: watchlistOnBinding)
                    if interface.watchlistBadge != "off" {
                        HarborSettingsChoice("Bookmark corner", selection: $interface.watchlistBadge,
                                             choices: [("Top left", "topStart"), ("Top right", "topEnd"), ("Bottom left", "bottomStart"), ("Bottom right", "bottomEnd")],
                                             identifier: "card-badges-bookmark-corner")
                        Text(text("Pick which corner of the poster the bookmark sits in.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HarborSettingsToggle(DesktopInterfaceText.value("Watched badge"), note: DesktopInterfaceText.value("Puts a check on titles you have already finished."),
                                         isOn: $interface.showWatchedBadge)
                        .accessibilityIdentifier("card-watched-badge")
                    HarborSettingsToggle("Show DUB badge on anime cards",
                                         note: "Flags anime with an English dub. Also tags dub / sub / dual on stream sources.",
                                         isOn: $interface.showDubBadge)
                }
                HarborSettingsSection("Scores") {
                    ratingToggle(.imdb, "IMDb")
                    ratingToggle(.tmdb, "TMDB", note: "The TMDB community score.")
                    ratingToggle(.mal, "MAL", note: "Anime")
                    HarborSettingsToggle("Details", note: "The ratings row on a title's detail page, next to runtime and genre.", isOn: malDetailBinding)
                        .accessibilityIdentifier("card-rating-mal-details")
                    ratingToggle(.simkl, "SIMKL")
                    ratingToggle(.rt, "Rotten Tomatoes")
                    ratingToggle(.audience, "Audience", note: "Rotten Tomatoes Popcornmeter, the audience score (%).")
                    ratingToggle(.metacritic, "Metacritic")
                    ratingToggle(.letterboxd, "Letterboxd")
                    ratingToggle(.mdblist, "MDBList")
                    ratingToggle(.trakt, "Trakt")
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Cards")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("card-badges-scroll")
            .task { if !store.ready { _ = try? store.load() } }
    }

    private func ratingToggle(_ provider: CardRatingProvider, _ title: String, note: String? = nil) -> some View {
        let hint = CardRatingPolicy.missingKeyHint(provider, keys: keys)
        let binding = Binding(get: { interface.cardRatingOn(provider) }, set: { setRating(provider, $0) })
        return HarborSettingsToggle(title, note: hint ?? note, isOn: binding)
            .disabled(hint != nil)
            .accessibilityIdentifier("card-rating-" + provider.rawValue)
    }

    /// Turning a score on past the limit lifts the limit to the new count, as Desktop does.
    private func setRating(_ provider: CardRatingProvider, _ on: Bool) {
        let before = enabledCount
        interface.setCardRating(provider, on)
        interface.cardBadgeLimit = CardRatingPolicy.limitAfterEnabling(previous: before, current: enabledCount, limit: interface.cardBadgeLimit)
    }
}
