import SwiftUI

/// Desktop's score chips on a poster (`components/card-score-stack.tsx`). Which chips show, their order and the limit come
/// from `CardRatingPolicy`; the scores come from `CardRatings`. Nothing is fetched until the card is on screen.
struct CardRatingChips: View {
    let media: Media
    let owner: String
    @State private var store: ProviderKeyStore
    @State private var scores = CardRatingScores()

    init(media: Media, owner: String) {
        self.media = media
        self.owner = owner
        _store = State(initialValue: ProviderKeyStore.forOwner(owner))
    }

    private var preferences: InterfacePreferences { InterfacePreferences.shared }
    private var anime: Bool { AnimeService.isAnime(media.id) }
    private var keys: Set<CardRatingKey> { CardRatingPolicy.keySources(omdb: store.key(.omdb), mdblist: store.key(.mdblist)) }
    private var selected: Set<CardRatingProvider> { Set(CardRatingProvider.allCases.filter { preferences.cardRatingOn($0) }) }
    private var enabled: [CardRatingProvider] { CardRatingPolicy.enabled(selected: selected, keys: keys) }
    private var needs: CardRatingNeeds {
        CardRatingPolicy.needs(anime: anime, enabled: enabled, inlineRating: media.imdbRating, inlineSource: media.ratingSource)
    }
    private var chips: [CardRatingChip] {
        CardRatingPolicy.chips(anime: anime, inlineRating: media.imdbRating, inlineSource: media.ratingSource, scores: scores,
                               enabled: enabled, limit: preferences.cardBadgeLimit)
    }
    private var taskID: String {
        media.identity + "|" + String(needs.rawValue) + "|" + keys.map(\.rawValue).sorted().joined(separator: ",")
    }
    private var alignment: Alignment { preferences.badgePlacement == "top" ? .topTrailing : .bottomTrailing }

    var body: some View {
        chipRow
            .task(id: taskID) { await refresh() }
    }

    @ViewBuilder private var chipRow: some View {
        if !chips.isEmpty {
            HStack(spacing: 4) {
                ForEach(chips.indices, id: \.self) { index in
                    if index > 0 { Text("·").opacity(0.3) }
                    CardRatingChipLabel(chip: chips[index])
                }
            }
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.8), in: .capsule)
            .scaleEffect(scale(chips.count), anchor: .trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Desktop's `ScoreStack` shrinks the row as more chips are shown.
    private func scale(_ count: Int) -> CGFloat {
        if count <= 3 { return 1 }
        if count == 4 { return 0.88 }
        if count == 5 { return 0.78 }
        return 0.7
    }

    private func refresh() async {
        do { if !store.ready { try store.load() } } catch { return }
        let wanted = needs
        guard !wanted.isEmpty, let imdbID = CardRatingPolicy.imdbID(media) else { return }
        let found = await CardRatings.shared.scores(imdbID: imdbID, omdbKey: store.key(.omdb), mdblistKey: store.key(.mdblist),
                                                    show: media.type != "movie", needs: wanted)
        guard !Task.isCancelled else { return }
        scores = found
    }
}

/// One chip: a logo or a short name, then the score. Desktop prints logos; these are the bundled tracker marks or text.
private struct CardRatingChipLabel: View {
    let chip: CardRatingChip

    var body: some View {
        if chip.provider == .metacritic {
            Text(chip.text).foregroundStyle(.black).padding(.horizontal, 3)
                .background(metacriticColor, in: .rect(cornerRadius: 3))
        } else {
            HStack(spacing: 3) {
                leading
                Text(chip.text)
            }
        }
    }

    @ViewBuilder private var leading: some View {
        switch chip.provider {
        case .imdb: tag(DesktopInterfaceText.value("IMDb"), fill: .yellow)
        case .tmdb: tag(DesktopInterfaceText.value("TMDB"), fill: .mint)
        case .mal: Image("tracker-mal").resizable().scaledToFit().frame(width: 11, height: 11)
        case .simkl: Image("tracker-simkl").resizable().scaledToFit().frame(width: 11, height: 11)
        case .trakt: Image("tracker-trakt").resizable().scaledToFit().frame(width: 11, height: 11)
        default: Text(DesktopInterfaceText.value(DetailRatings.shortName(chip.provider.rawValue)))
        }
    }

    private func tag(_ title: String, fill: Color) -> some View {
        Text(title).font(.system(size: 7, weight: .black)).foregroundStyle(.black).padding(2)
            .background(fill, in: .rect(cornerRadius: 2))
    }

    private var metacriticColor: Color {
        switch DetailRatings.metacriticBand(Int(chip.text) ?? 0) {
        case "green": .green
        case "amber": .orange
        default: .red
        }
    }
}
