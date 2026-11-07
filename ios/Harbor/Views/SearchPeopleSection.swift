import SwiftUI

/// Desktop's people part of search (components/search/search-overlay.tsx): a top match card, then a photo rail.
/// It loads its own results, and shows nothing without a TMDB key or when no person matches.
struct SearchPeopleSection: View {
    let app: AppModel
    let query: String
    @State private var people: [PersonSearchHit] = []

    var body: some View {
        let match = TMDBPeople.matchPerson(people, query: query)
        VStack(alignment: .leading, spacing: 24) {
            if let match { PersonTopMatchCard(app: app, person: match) }
            PeopleRail(app: app, people: TMDBPeople.railPeople(people, excluding: match?.id))
        }
        .padding(.horizontal)
        .padding(.bottom, people.isEmpty ? 0 : 24)
        .task(id: query) { await load() }
    }

    private func load() async {
        people = []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        let found = (try? await TMDBPeople().search(text, configuration: MetadataPreferences.shared.configuration())) ?? []
        guard !Task.isCancelled else { return }
        people = found
    }
}

/// Desktop's `PeopleRow`: the people with a photo, as round portraits that open the person page.
struct PeopleRail: View {
    let app: AppModel
    let people: [PersonSearchHit]

    var body: some View {
        if people.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(DesktopInterfaceText.value("People"))
                    .font(HarborTheme.font(17, weight: .medium))
                    .accessibilityIdentifier("search-people-title")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(people) { person in
                            NavigationLink {
                                PersonView(personID: person.id, app: app)
                            } label: {
                                PersonPhotoCell(person: person)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search-person")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct PersonPhotoCell: View {
    let person: PersonSearchHit

    var body: some View {
        VStack(spacing: 8) {
            Artwork(url: TMDBPeople.photoURL(person.profile, size: "h632"), maxPixels: 350)
                .frame(width: 84, height: 84)
                .clipShape(.circle)
            Text(person.name)
                .font(HarborTheme.font(13, weight: .semibold))
                .lineLimit(1)
            Text(person.knownFor)
                .font(HarborTheme.font(12))
                .foregroundStyle(HarborTheme.ink.opacity(0.5))
                .lineLimit(1)
        }
        .frame(width: 104)
    }
}

/// Desktop's `PersonTopMatch`: the best name match, with its photo, as one card to open.
private struct PersonTopMatchCard: View {
    let app: AppModel
    let person: PersonSearchHit

    var body: some View {
        NavigationLink {
            PersonView(personID: person.id, app: app)
        } label: {
            HStack(spacing: 16) {
                Artwork(url: TMDBPeople.photoURL(person.profile, size: "h632"), maxPixels: 350)
                    .frame(width: 96, height: 96)
                    .clipShape(.circle)
                VStack(alignment: .leading, spacing: 6) {
                    Text(DesktopInterfaceText.value("Top match"))
                        .font(HarborTheme.font(11, weight: .semibold))
                        .foregroundStyle(HarborTheme.accent)
                    Text(person.name)
                        .font(HarborTheme.displayFont(26))
                        .lineLimit(2)
                    if !person.knownFor.isEmpty {
                        Text(person.knownFor)
                            .font(HarborTheme.font(13))
                            .foregroundStyle(HarborTheme.ink.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(DesktopInterfaceText.value("Explore"))
                    .font(HarborTheme.font(14, weight: .semibold))
                    .foregroundStyle(HarborTheme.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesktopInterfaceText.value("Explore {name}", variables: ["name": person.name]))
        .accessibilityIdentifier("search-person-top-match")
    }
}
