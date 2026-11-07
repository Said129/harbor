import SwiftUI
import Observation

/// What one load of the pick depends on. The list is fetched once a day per TMDB key and region; the choice is redone
/// when the watched or voted titles or the Featured titles change.
struct CriticsPickInput: Sendable {
    let configuration: MetadataConfiguration
    let omdbKey: String
    let dayOfYear: Int
    let excludedIDs: Set<String>
    let excludedTitleKeys: Set<String>
    let featuredIDs: Set<String>

    var listSignature: String {
        [configuration.tmdbKey, configuration.language, configuration.region, String(dayOfYear)].joined(separator: "|")
    }
}

@MainActor @Observable
final class CriticsPickModel {
    private(set) var pick: Media?
    private(set) var details: CriticsPickDetails?
    private(set) var scores: CriticsPickScores?
    private var list: [Media] = []
    private var listSignature = ""
    private var detailsFor: String?
    private var scoresFor: String?
    private let service: CriticsPickService

    init(service: CriticsPickService = CriticsPickService()) { self.service = service }

    /// Fetches the day's list when it is not held yet, then chooses the title and loads its details and OMDb scores.
    func refresh(_ input: CriticsPickInput) async {
        if listSignature != input.listSignature {
            let fetched = await service.candidates(dayOfYear: input.dayOfYear, configuration: input.configuration)
            guard !Task.isCancelled else { return }
            list = fetched
            // An empty answer is asked again the next time, so a failed network call does not hide the card for a day.
            if !fetched.isEmpty { listSignature = input.listSignature }
        }
        let next = CriticsPickRules.pick(from: list, excludedIDs: input.excludedIDs, featuredIDs: input.featuredIDs,
                                         excludedTitleKeys: input.excludedTitleKeys, dayOfYear: input.dayOfYear)
        if next?.id != pick?.id {
            pick = next; details = nil; scores = nil; detailsFor = nil; scoresFor = nil
        }
        guard let media = next else { return }
        if detailsFor != media.id {
            let loaded = await service.details(for: media, configuration: input.configuration)
            guard !Task.isCancelled, pick?.id == media.id else { return }
            guard let loaded else { return }
            details = loaded; detailsFor = media.id
        }
        guard scoresFor != media.id, let current = details, !input.omdbKey.isEmpty else { return }
        let omdb = await service.omdbScores(for: current, key: input.omdbKey)
        guard !Task.isCancelled, pick?.id == media.id else { return }
        scores = CriticsPickScores.from(omdb, showRottenTomatoes: InterfacePreferences.shared.showRtBadge)
        scoresFor = media.id
    }
}

/// Desktop's Critics Pick card, as a hero with one review at a time. It is shown on Discover between the rails.
struct CriticsPickView: View {
    let app: AppModel
    /// Titles already shown in Featured, which the pick leaves out (Desktop's `featuredIds`).
    let featuredIDs: Set<String>
    @State private var model = CriticsPickModel()
    @State private var reviewIndex = 0
    @State private var overviewShown = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: ProviderKeyStore { ProviderKeyStore.forOwner(app.personalOwner) }
    private var dayOfYear: Int { CriticsPickRules.dayOfYear(now: Date()) }
    /// Watched or in-progress titles, and titles the person voted on (Desktop hides both from the pick).
    private var watchedItems: [Media] { app.library.items.filter { $0.watched || $0.continuing }.compactMap(\.media) }
    private var excludedIDs: Set<String> {
        var ids = Set(app.library.items.filter { $0.watched || $0.continuing }.map(\.id))
        ids.formUnion(app.library.discovery.votes.keys)
        return ids
    }
    private var excludedTitleKeys: Set<String> { Set(watchedItems.map { CriticsPickRules.titleKey($0.name) }) }
    private var input: CriticsPickInput {
        CriticsPickInput(configuration: MetadataPreferences.shared.configuration(), omdbKey: store.key(.omdb), dayOfYear: dayOfYear,
                         excludedIDs: excludedIDs, excludedTitleKeys: excludedTitleKeys, featuredIDs: featuredIDs)
    }
    /// Changes when the key, the day, the region or the excluded titles change, so the task runs again.
    private var taskID: String {
        let configuration = MetadataPreferences.shared.configuration()
        return [configuration.tmdbKey, configuration.language, configuration.region, store.key(.omdb), String(dayOfYear),
                String(excludedIDs.hashValue), String(excludedTitleKeys.hashValue), String(featuredIDs.hashValue)].joined(separator: "|")
    }
    private var reviews: [CriticsPickReview] { model.details?.reviews ?? [] }
    private var currentReview: CriticsPickReview? { reviews.indices.contains(reviewIndex) ? reviews[reviewIndex] : nil }

    /// The container is always there, so the task starts while no title is chosen yet (as in CardRatingChips).
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let media = model.pick { section(media) }
        }
        .task(id: taskID) {
            if !store.ready { try? store.load() }
            await model.refresh(input)
        }
        .onChange(of: model.pick?.id) { _, _ in reviewIndex = 0 }
    }

    private func section(_ media: Media) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(spacing: 12) {
                heroCard(media)
                quotePanel(media)
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $overviewShown) {
            CriticsPickOverviewSheet(media: media, details: model.details, review: currentReview)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DesktopInterfaceText.value("Critics' Pick")).font(HarborTheme.displayFont(28)).accessibilityAddTraits(.isHeader)
            Text(DesktopInterfaceText.value("Loved by reviewers today")).font(HarborTheme.font(11, weight: .semibold)).tracking(1.8)
                .textCase(.uppercase).foregroundStyle(.secondary)
        }
    }

    private func heroCard(_ media: Media) -> some View {
        NavigationLink(value: media) {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: media.background, fallback: media.fallbackBackground, fallbacks: [media.poster].compactMap { $0 }, maxPixels: 1100)
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                heroText(media)
            }
            .frame(height: 300)
            .clipShape(.rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesktopInterfaceText.value("Open {name}", variables: ["name": media.name]))
    }

    private func heroText(_ media: Media) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HarborHeroTitle(media: media, size: 28, height: 76).frame(maxWidth: 260, alignment: .leading)
            scoreRow(media)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scoreRow(_ media: Media) -> some View {
        let shown = model.scores ?? CriticsPickScores()
        return HStack(spacing: 10) {
            if let year = media.releaseInfo { Text(year) }
            if let imdb = shown.imdbRating {
                scoreText(DesktopInterfaceText.value("IMDb"), imdb)
            } else if let tmdb = media.imdbRating {
                scoreText(DesktopInterfaceText.value("TMDB"), tmdb)
            }
            if let rt = shown.rottenTomatoes {
                scoreText(DesktopInterfaceText.value(DetailRatings.shortName("rt")), "\(rt)%")
            }
            if let metascore = shown.metascore {
                metascoreTag(metascore)
            }
        }
        .font(HarborTheme.font(12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
    }

    private func scoreText(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(HarborTheme.font(9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            Text(value)
        }
    }

    private func metascoreTag(_ score: Int) -> some View {
        HStack(spacing: 4) {
            Text(DesktopInterfaceText.value("M"))
                .font(HarborTheme.font(9, weight: .bold)).foregroundStyle(.black)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color(red: 1.0, green: 0.8, blue: 0.2), in: .rect(cornerRadius: 3))
            Text("\(score)")
        }
    }

    private func quotePanel(_ media: Media) -> some View {
        let fallback = DesktopInterfaceText.value("A standout this week.")
        let quote = CriticsPickRules.quote(review: currentReview, tagline: model.details?.tagline,
                                           overview: model.details?.overview ?? media.description, fallback: fallback)
        return VStack(alignment: .leading, spacing: 12) {
            Text(quote)
                .font(HarborTheme.font(15)).italic()
                .foregroundStyle(HarborTheme.ink.opacity(0.9))
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let review = currentReview { reviewLine(review) }
            controls(media)
            if store.key(.omdb).isEmpty {
                Text(DesktopInterfaceText.value("Cards need an OMDb key."))
                    .font(HarborTheme.font(11)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(HarborTheme.surface.opacity(0.35), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.07), lineWidth: 1) }
    }

    private func reviewLine(_ review: CriticsPickReview) -> some View {
        HStack(spacing: 6) {
            Text(review.author).font(HarborTheme.font(11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            if let rating = review.rating, rating > 0 {
                Text("· " + String(format: "%g", rating) + "/10").font(HarborTheme.font(11)).foregroundStyle(.secondary)
            }
            if let link = reviewURL(review) {
                Button { openURL(link) } label: {
                    Image(systemName: "arrow.up.right.square").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesktopInterfaceText.value("Open review source"))
            }
        }
    }

    private func reviewURL(_ review: CriticsPickReview) -> URL? {
        guard let text = review.url, let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }

    private func controls(_ media: Media) -> some View {
        HStack(spacing: 8) {
            if reviews.count > 1 { reviewPager }
            Button { overviewShown = true } label: {
                Text(DesktopInterfaceText.value("Read full"))
                    .font(HarborTheme.font(12, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(HarborTheme.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            NavigationLink { DetailView(media: media, app: app, playImmediately: true) } label: {
                Text(DesktopInterfaceText.value("Play"))
                    .font(HarborTheme.font(14, weight: .semibold))
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .foregroundStyle(HarborTheme.background)
                    .background(HarborTheme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewPager: some View {
        HStack(spacing: 2) {
            Button { stepReview(-1) } label: {
                Image("desktop-chevron-left").resizable().scaledToFit().frame(width: 12, height: 12).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DesktopInterfaceText.value("Previous review"))
            Text("\(reviewIndex + 1)/\(reviews.count)").font(HarborTheme.font(11)).foregroundStyle(.secondary).monospacedDigit()
            Button { stepReview(1) } label: {
                Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 12, height: 12).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DesktopInterfaceText.value("Next review"))
        }
    }

    private func stepReview(_ direction: Int) {
        let count = reviews.count
        guard count > 1 else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            reviewIndex = (reviewIndex + direction + count) % count
        }
    }
}

/// Desktop's overview modal, as a sheet: the full overview, the tagline and the review shown on the card.
private struct CriticsPickOverviewSheet: View {
    let media: Media
    let details: CriticsPickDetails?
    let review: CriticsPickReview?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(media.name).font(HarborTheme.displayFont(26))
                    if let tagline = CriticsPickRules.trimmed(details?.tagline) {
                        Text(tagline).font(HarborTheme.font(15)).italic().foregroundStyle(.secondary)
                    }
                    if let overview = CriticsPickRules.trimmed(details?.overview ?? media.description) {
                        Text(overview).font(HarborTheme.font(15))
                    }
                    if let review {
                        Divider()
                        Text(review.author).font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(.secondary)
                        Text(review.content).font(HarborTheme.font(14))
                    }
                }
                .padding(20)
            }
            .background(HarborTheme.background)
            .toolbar { Button(DesktopInterfaceText.value("Close")) { dismiss() } }
        }
    }
}
