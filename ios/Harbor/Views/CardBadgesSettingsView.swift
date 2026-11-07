import SwiftUI

/// Desktop's "Cards" column of the ratings matrix and its score position and limit (`ratings-matrix.tsx`,
/// `card-badges-panel.tsx`). A provider whose key is missing is shown off, with Desktop's hint.
struct CardBadgesSettingsView: View {
    @State private var store: ProviderKeyStore
    @Bindable private var interface = InterfacePreferences.shared

    init(owner: String) { _store = State(initialValue: ProviderKeyStore.forOwner(owner)) }

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    private var keys: Set<CardRatingKey> { CardRatingPolicy.keySources(omdb: store.key(.omdb), mdblist: store.key(.mdblist)) }
    private var selected: Set<CardRatingProvider> { Set(CardRatingProvider.allCases.filter { interface.cardRatingOn($0) }) }
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
                HarborSettingsSection("Scores") {
                    ratingToggle(.imdb, "IMDb")
                    ratingToggle(.tmdb, "TMDB", note: "The TMDB community score.")
                    ratingToggle(.mal, "MAL", note: "Anime")
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
