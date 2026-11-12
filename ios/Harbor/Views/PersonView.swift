import SwiftUI

/// Desktop's person page (views/person.tsx): photo and facts, Known For, then the filmography grouped by role.
struct PersonView: View {
    let personID: Int
    let app: AppModel
    @State private var profile: PersonProfile?
    @State private var knownFor: [PersonCreditItem] = []
    @State private var sections: [FilmographySection] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if let profile { PersonHeaderView(profile: profile) }
                // Desktop's person page reads the awards of the person's IMDb id (`useAwards(person.imdbId)`).
                TitleAwardsSection(imdbID: profile?.imdbID, isSeries: false, allowsPerson: true)
                if !knownFor.isEmpty { CreditRail(title: DesktopInterfaceText.value("Known For"), app: app, items: knownFor) }
                ForEach(sections) { section in FilmographyGrid(section: section, app: app) }
                if !loading && profile != nil && knownFor.isEmpty && sections.isEmpty { emptyNotice }
            }
            .padding()
        }
        .background(HarborTheme.background)
        .navigationTitle(title)
        .task(id: personID) { await load() }
    }

    private var title: String {
        profile?.name ?? (loading ? "" : DesktopInterfaceText.value("Unknown"))
    }

    private var emptyNotice: some View {
        Text(DesktopInterfaceText.value("No filmography on record."))
            .font(HarborTheme.font(14))
            .foregroundStyle(HarborTheme.ink.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding()
    }

    private func load() async {
        loading = true
        let configuration = MetadataPreferences.shared.configuration()
        let loaded = try? await TMDBPeople().person(personID, configuration: configuration)
        guard !Task.isCancelled else { return }
        profile = loaded
        knownFor = loaded.map(TMDBPeople.knownFor) ?? []
        sections = loaded.map(TMDBPeople.filmography) ?? []
        loading = false
    }
}

private struct PersonHeaderView: View {
    let profile: PersonProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Artwork(url: TMDBPeople.photoURL(profile.profilePath, size: "h632"), maxPixels: 700)
                .frame(width: 160, height: 240)
                .clipShape(.rect(cornerRadius: 14))
            Text(profile.name)
                .font(HarborTheme.displayFont(34))
                .accessibilityIdentifier("person-name")
            if let department = departmentLabel {
                Text(department)
                    .font(HarborTheme.font(13, weight: .medium))
                    .foregroundStyle(HarborTheme.ink.opacity(0.55))
            }
            ForEach(lifeLines, id: \.self) { line in
                Text(line)
                    .font(HarborTheme.font(14))
                    .foregroundStyle(HarborTheme.ink.opacity(0.7))
            }
            if !profile.biography.isEmpty {
                Text(profile.biography)
                    .font(HarborTheme.font(15))
                    .foregroundStyle(HarborTheme.ink.opacity(0.85))
            }
        }
    }

    /// The Desktop department names are translated; any other value is shown as TMDB gives it.
    private var departmentLabel: String? {
        let department = profile.knownForDepartment
        if department.isEmpty { return nil }
        return TMDBPeople.departmentKeys.contains(department) ? DesktopInterfaceText.value(department) : department
    }

    private var lifeLines: [String] {
        var lines: [String] = []
        if let birthday = profile.birthday {
            var born = DesktopInterfaceText.value("Born {date}", variables: ["date": TMDBPeople.displayDate(birthday)])
            if let years = TMDBPeople.age(birthday: birthday, deathday: profile.deathday, now: Date()) {
                born += " · \(years)"
            }
            lines.append(born)
        }
        if let deathday = profile.deathday {
            lines.append(DesktopInterfaceText.value("Died {date}", variables: ["date": TMDBPeople.displayDate(deathday)]))
        }
        if let place = profile.placeOfBirth { lines.append(place) }
        return lines
    }
}

/// A horizontal row of posters that open the title, as Desktop's `FilmRow` without captions.
private struct CreditRail: View {
    let title: String
    let app: AppModel
    let items: [PersonCreditItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(HarborTheme.font(17, weight: .medium))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items.indices, id: \.self) { index in
                        CreditPosterLink(credit: items[index], app: app, showsCaption: false)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .posterRowBehavior()
        }
    }
}

/// One group of the filmography (Movies, TV Shows, Directing, ...) as a wrapping grid.
private struct FilmographyGrid: View {
    let section: FilmographySection
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DesktopInterfaceText.value(section.title, variables: ["n": String(section.items.count)]))
                .font(HarborTheme.font(17, weight: .medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 14, alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(section.items.indices, id: \.self) { index in
                    CreditPosterLink(credit: section.items[index], app: app, showsCaption: true)
                }
            }
        }
    }
}

private struct CreditPosterLink: View {
    let credit: PersonCreditItem
    let app: AppModel
    let showsCaption: Bool

    var body: some View {
        let media = TMDBPeople.media(for: credit)
        NavigationLink {
            DetailView(media: media, app: app)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Poster(media: media, width: showsCaption ? nil : 116)
                if showsCaption {
                    Text(TMDBPeople.caption(credit))
                        .font(HarborTheme.font(12))
                        .foregroundStyle(HarborTheme.ink.opacity(0.5))
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(media.name)
    }
}
