import SwiftUI

/// Desktop's calendar filter rail for the Custom source (`views/calendar/config/config-rail.tsx`), as a sheet.
struct CalendarFilterSheet: View {
    let store: CustomCalendarStore
    let resultCount: Int
    let tmdbKey: String
    let traktConnected: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var openGroups: Set<String> = ["genres"]
    @State private var genreFilter = ""
    @State private var countryFilter = ""
    @State private var query = ""
    @State private var found: [CalendarSources.PersonResult] = []
    @State private var searching = false
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private func binding(_ group: String) -> Binding<Bool> {
        Binding(get: { openGroups.contains(group) }, set: { if $0 { openGroups.insert(group) } else { openGroups.remove(group) } })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        resultPill
                        Spacer(minLength: 0)
                    }
                    Text(text("Show")).font(HarborTheme.font(11, weight: .bold)).tracking(1.4).foregroundStyle(.secondary).textCase(.uppercase)
                    HStack(spacing: 8) {
                        mediaPill("Movies", \.movie, id: "movie")
                        mediaPill("Series", \.tv, id: "tv")
                        mediaPill("Anime", \.anime, id: "anime")
                    }
                    group("genres", title: "Genres", count: store.value.genres.count, clear: { store.value.genres = [] }) {
                        filterField("Filter genres", text: $genreFilter)
                        chips(CustomCalendar.genreOptions.filter { matches(label($0), genreFilter) }.map { option in
                            Chip(key: option.key, label: label(option), selected: store.value.genres.contains { $0.id == option.genre.id && $0.mediaType == option.genre.mediaType }) { store.value.toggleGenre(option.genre) }
                        })
                    }
                    group("providers", title: "Where to watch", count: store.value.watchProviders.count, clear: { store.value.watchProviders = [] }) {
                        chips(CustomCalendar.providers.map { provider in
                            Chip(key: "prov:\(provider.id)", label: provider.name, selected: store.value.watchProviders.contains { $0.id == provider.id }) { store.value.toggleProvider(provider) }
                        })
                    }
                    group("countries", title: "Origin country", count: store.value.originCountries.count, clear: { store.value.originCountries = [] }) {
                        filterField("Filter countries", text: $countryFilter)
                        chips(CustomCalendar.countries.filter { matches(text($0.name), countryFilter) }.map { country in
                            Chip(key: "cn:\(country.code)", label: text(country.name), selected: store.value.originCountries.contains(country.code)) { store.value.toggleCountry(country.code) }
                        })
                    }
                    group("people", title: "Track people", count: store.value.trackedPeople.count, clear: { store.value.trackedPeople = [] }) { people }
                    Text(text("Trakt sources")).font(HarborTheme.font(11, weight: .bold)).tracking(1.4).foregroundStyle(.secondary).textCase(.uppercase)
                    HarborSettingsToggle(text("Trakt anticipated"), note: text("Most-anticipated upcoming releases on Trakt"), isOn: Binding(get: { store.value.includeTraktAnticipated }, set: { store.value.includeTraktAnticipated = $0 }))
                        .accessibilityIdentifier("calendar-filter-trakt-anticipated")
                    HarborSettingsToggle(text("My Trakt watchlist"), note: traktConnected ? text("Upcoming items from your watchlist") : text("Connect Trakt in settings first"),
                                         isOn: Binding(get: { store.value.includeTraktWatchlist }, set: { store.value.includeTraktWatchlist = $0 }))
                        .disabled(!traktConnected).accessibilityIdentifier("calendar-filter-trakt-watchlist")
                    HStack {
                        let active = store.value.activeCount
                        Text(active > 0 ? "\(active) \(text("active"))" : text("No filters")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                        Spacer()
                        Button(text("Clear all")) { store.value.clearAll() }.disabled(active == 0).frame(minHeight: 44).accessibilityIdentifier("calendar-filter-clear-all")
                    }
                }.padding(20)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
                .navigationTitle(text("Filters")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(text("Done")) { dismiss() }.accessibilityIdentifier("calendar-filter-done") } }
        }.accessibilityIdentifier("calendar-filter-sheet")
    }

    private var resultPill: some View {
        Group {
            if resultCount <= 0 { Text(text("Nothing yet")).foregroundStyle(.secondary) }
            else { Text("\(resultCount) \(text(resultCount == 1 ? "result" : "results"))").fontWeight(.semibold).foregroundStyle(HarborTheme.accent) }
        }.font(HarborTheme.font(13))
    }

    private func label(_ option: CustomCalendar.GenreOption) -> String {
        option.tvOnly ? text("{name} (TV)").replacingOccurrences(of: "{name}", with: text(option.name)) : text(option.name)
    }
    private func matches(_ label: String, _ filter: String) -> Bool {
        let wanted = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return wanted.isEmpty || label.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func mediaPill(_ title: String, _ path: WritableKeyPath<CustomCalendar.MediaTypes, Bool>, id: String) -> some View {
        HarborPill(title: text(title), selected: store.value.mediaTypes[keyPath: path]) { store.value.mediaTypes[keyPath: path].toggle() }
            .accessibilityIdentifier("calendar-filter-media-" + id)
    }

    private struct Chip: Identifiable {
        let key: String
        let label: String
        let selected: Bool
        let toggle: () -> Void
        var id: String { key }
    }
    private func chips(_ items: [Chip]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    Button(action: item.toggle) {
                        Text(item.label).font(HarborTheme.font(13, weight: .semibold)).lineLimit(1).padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(item.selected ? Color.black : HarborTheme.ink.opacity(0.75))
                            .background(item.selected ? Color.white : HarborTheme.surface.opacity(0.65), in: .capsule)
                    }.buttonStyle(.plain).accessibilityAddTraits(item.selected ? [.isSelected] : []).accessibilityIdentifier("calendar-filter-" + item.key)
                }
            }
            if items.isEmpty { Text(text("No matches")).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
        }
    }

    private func filterField(_ placeholder: String, text binding: Binding<String>) -> some View {
        TextField(text(placeholder), text: binding).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(.horizontal, 12).frame(minHeight: 44).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
    }

    private func group<Content: View>(_ id: String, title: String, count: Int, clear: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        let built = content()
        return DisclosureGroup(isExpanded: binding(id)) {
            VStack(alignment: .leading, spacing: 12) {
                built
                if count > 0 { Button(text("Clear"), action: clear).font(HarborTheme.font(13)).frame(minHeight: 44).accessibilityIdentifier("calendar-filter-clear-" + id) }
            }.padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text(text(title)).font(HarborTheme.font(15, weight: .semibold))
                if count > 0 { Text("\(count)").font(HarborTheme.font(12, weight: .bold)).foregroundStyle(HarborTheme.accent) }
            }
        }.accessibilityIdentifier("calendar-filter-group-" + id)
    }

    @ViewBuilder private var people: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(tmdbKey.isEmpty ? text("Add a TMDB key in settings first") : text("Search actors, directors…"), text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(tmdbKey.isEmpty)
                .padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                .accessibilityIdentifier("calendar-filter-people-search")
            if searching { ProgressView().frame(maxWidth: .infinity) }
            ForEach(found) { person in
                let added = store.value.trackedPeople.contains { $0.id == person.id }
                Button {
                    store.value.addPerson(id: person.id, name: person.name, profile: person.profile); query = ""; found = []
                } label: {
                    HStack(spacing: 12) {
                        personAvatar(person.profile)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).font(HarborTheme.font(14)).lineLimit(1)
                            Text(person.knownFor).font(HarborTheme.font(12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if added { Text(text("added")).font(HarborTheme.font(11, weight: .semibold)).foregroundStyle(HarborTheme.accent).textCase(.uppercase) }
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(added).accessibilityIdentifier("calendar-filter-person-\(person.id)")
            }
            if !tmdbKey.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty, !searching, found.isEmpty { Text(text("No people found")).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
            ForEach(store.value.trackedPeople) { person in
                HStack(spacing: 12) {
                    personAvatar(person.profile)
                    Text(person.name).font(HarborTheme.font(14)).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { store.value.removePerson(person.id) } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(text("Remove {name}").replacingOccurrences(of: "{name}", with: person.name))
                }.frame(minHeight: 48)
            }
        }
        .task(id: query) { await search() }
    }

    private func personAvatar(_ profile: String?) -> some View {
        Artwork(url: profile.map { "https://image.tmdb.org/t/p/w92" + $0 }, maxPixels: 120).frame(width: 36, height: 36).clipShape(.circle)
    }

    /// Desktop waits 220 ms after the last keystroke, then shows the first eight people.
    private func search() async {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, !tmdbKey.isEmpty else { found = []; searching = false; return }
        searching = true
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        let result = await CalendarFetcher().searchPeople(key: tmdbKey, query: wanted)
        guard !Task.isCancelled else { return }
        found = result; searching = false
    }
}
