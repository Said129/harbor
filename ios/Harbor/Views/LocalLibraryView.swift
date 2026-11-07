import SwiftUI
import UniformTypeIdentifiers

/// What the single file importer is picking. One importer per view: SwiftUI can drop all but the last one attached.
private enum LocalImportMode {
    case files, folder
}

/// The person's own video files, opened through security-scoped bookmarks. Nothing is copied or scanned in the background.
struct LocalLibraryView: View {
    let app: AppModel
    @State private var store: LocalLibraryStore
    @State private var playback: PlaybackSession?
    @State private var playbackTitle = "Harbor"
    @State private var access: LocalLibraryFileAccess?
    @State private var importing = false
    @State private var importMode = LocalImportMode.files
    @State private var failure: String?
    @State private var notice: String?
    @AppStorage(LocalLibraryPreferences.minimumSizeKey) private var minimumMB = LocalLibraryPreferences.defaultMinimumSizeMB
    @AppStorage(LocalLibraryPreferences.sortKey) private var sortRaw = LocalLibrarySortKey.added.rawValue
    @AppStorage(LocalLibraryPreferences.sortDescendingKey) private var sortDescending = true
    @AppStorage(LocalLibraryPreferences.episodeSortKey) private var episodesDescending = false
    @Environment(\.locale) private var locale
    private func text(_ key: String, variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables, language: locale.identifier) }

    @MainActor init(app: AppModel) {
        self.app = app
        _store = State(initialValue: LocalLibraryStore(owner: app.personalOwner))
    }

    private var owner: String { app.personalOwner }
    private var sortKey: LocalLibrarySortKey { LocalLibrarySortKey(rawValue: sortRaw) ?? .added }
    private var groups: [LocalLibraryGroup] {
        let visible = LocalLibraryFilter.atLeast(store.records, megabytes: minimumMB)
        return LocalLibraryGrouping.arranged(LocalLibraryGrouping.groups(visible), sort: sortKey, descending: sortDescending, episodesDescending: episodesDescending)
    }
    private var movies: [LocalLibraryMovie] {
        var out: [LocalLibraryMovie] = []
        for group in groups {
            if case .movie(let movie) = group { out.append(movie) }
        }
        return out
    }
    private var shows: [LocalLibraryShow] {
        var out: [LocalLibraryShow] = []
        for group in groups {
            if case .show(let show) = group { out.append(show) }
        }
        return out
    }

    var body: some View {
        List {
            Section {
                addButtons
                sortMenu
                minimumSizeRow
                Toggle(text("Sort episodes"), isOn: $episodesDescending)
            }
            if let notice = notice {
                Section { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            if let problem = failure ?? store.error {
                Section { Text(problem).font(.caption).foregroundStyle(.orange) }
            }
            movieSection
            showSections
            if groups.isEmpty { emptySection }
        }
        .navigationTitle(text("Local")).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, allowsMultipleSelection: importMode == .files) { result in
            handleImport(result)
        }
        .fullScreenCover(item: $playback, onDismiss: { endAccess() }) { session in
            PlayerView(session: session, resume: app.resume, title: playbackTitle, media: nil, library: app.library)
        }
        .onChange(of: owner) { _, next in
            endAccess()
            playback = nil
            store = LocalLibraryStore(owner: next)
        }
    }

    private var importTypes: [UTType] {
        importMode == .folder ? [UTType.folder] : LocalLibraryStore.contentTypes
    }

    // MARK: - Controls

    private var addButtons: some View {
        HStack(spacing: 10) {
            Button(text(store.records.isEmpty ? "Choose folder" : "Add folder")) { startImport(.folder) }
                .buttonStyle(.bordered)
            Button(text("Add files from your computer")) { startImport(.files) }
                .buttonStyle(.bordered)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LocalLibrarySortKey.allCases) { key in
                Button { sortRaw = key.rawValue } label: { Text(text(key.desktopTitle)) }
            }
            Divider()
            Button { sortDescending.toggle() } label: { Text(text(sortDescending ? "Descending" : "Ascending")) }
        } label: {
            Label(text(sortKey.desktopTitle), systemImage: "arrow.up.arrow.down")
        }
    }

    private var minimumSizeRow: some View {
        Stepper(value: $minimumMB, in: 0...5000, step: 10) {
            HStack {
                Text(text("Minimum file size"))
                Spacer()
                Text(String(minimumMB) + " " + text("MB")).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var movieSection: some View {
        if !movies.isEmpty {
            Section {
                ForEach(movies) { movie in movieRow(movie) }
            } header: {
                Text(text("Movies"))
            }
        }
    }

    @ViewBuilder
    private var showSections: some View {
        ForEach(shows) { show in
            Section {
                ForEach(show.seasons) { season in
                    Text(text("Season {n}", variables: ["n": String(season.number)]))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(season.episodes) { record in episodeRow(record) }
                }
            } header: {
                Text(show.title)
            }
        }
    }

    @ViewBuilder
    private func movieRow(_ movie: LocalLibraryMovie) -> some View {
        if let first = movie.versions.first {
            if movie.versions.count == 1 {
                Button { play(first) } label: { rowLabel(movieTitle(movie), detail: movieDetail(first)) }
                    .swipeActions { removeButton(movie.versions) }
            } else {
                Menu {
                    ForEach(movie.versions) { record in
                        Button(record.filename) { play(record) }
                    }
                } label: {
                    rowLabel(movieTitle(movie), detail: movieDetail(first))
                }
                .swipeActions { removeButton(movie.versions) }
            }
        }
    }

    private func episodeRow(_ record: LocalLibraryRecord) -> some View {
        Button { play(record) } label: {
            rowLabel(record.parsed.episodeLabel ?? record.filename, detail: record.filename)
        }
        .swipeActions { removeButton([record]) }
    }

    private func removeButton(_ records: [LocalLibraryRecord]) -> some View {
        Button(text("Remove from library"), role: .destructive) { remove(records) }
    }

    private func rowLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func movieTitle(_ movie: LocalLibraryMovie) -> String {
        guard let year = movie.year else { return movie.title }
        return movie.title + " (" + String(year) + ")"
    }

    private func movieDetail(_ record: LocalLibraryRecord) -> String {
        let parts: [String] = [record.parsed.resolution, record.filename].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var emptySection: some View {
        Section {
            if store.records.isEmpty {
                ContentUnavailableView(text("Add files from your computer"), systemImage: "externaldrive")
            } else {
                Text(text("No matches for these filters.")).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func startImport(_ mode: LocalImportMode) {
        importMode = mode
        failure = nil
        notice = nil
        importing = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        if importMode == .folder {
            addFolder(urls[0])
        } else {
            addFiles(urls)
        }
    }

    private func addFiles(_ urls: [URL]) {
        do {
            try store.addFiles(urls)
        } catch {
            failure = text("Couldn't open this file")
        }
    }

    private func addFolder(_ folder: URL) {
        do {
            let added = try store.addFolder(folder, megabytes: minimumMB)
            if added == 0 {
                failure = text("No video files found in that folder.")
            } else if added == 1 {
                notice = text("Added 1 new title from your folders")
            } else {
                notice = text("Added {n} new titles from your folders", variables: ["n": String(added)])
            }
        } catch {
            failure = text("Couldn't scan that folder.")
        }
    }

    private func play(_ record: LocalLibraryRecord) {
        guard playback == nil else { return }
        failure = nil
        do {
            let opened = try store.openForPlayback(record)
            endAccess()
            access = opened
            playbackTitle = record.parsed.title
            // Local files have no catalog id, so progress is not sent to the library. Playback starts at 0.
            playback = PlaybackSession(
                source: PlaybackSource(url: opened.file.path, headers: nil, subtitles: nil, via: "local"),
                target: ResumeTarget(id: "local:" + record.id),
                startMs: 0,
                storageWarning: nil,
                progressEnabled: false,
                owner: app.library.owner,
                personalOwner: owner
            )
        } catch {
            failure = text("Couldn't open this file")
        }
    }

    private func endAccess() {
        access?.end()
        access = nil
    }

    private func remove(_ records: [LocalLibraryRecord]) {
        do {
            try store.remove(ids: Set(records.map(\.id)))
        } catch {
            failure = text("Couldn't open this file")
        }
    }
}
