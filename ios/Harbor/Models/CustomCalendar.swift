import Foundation
import Observation

/// Desktop's `customCalendar` setting: what the Custom calendar source follows (`lib/settings/defaults.ts`,
/// `views/calendar/config/constants.ts` and `rail-sources.ts`).
struct CustomCalendar: Codable, Equatable, Hashable, Sendable {
    struct Person: Codable, Equatable, Hashable, Sendable, Identifiable {
        var id: Int
        var name: String
        var profile: String? = nil
        var role = "any"
    }
    struct Genre: Codable, Equatable, Hashable, Sendable {
        var id: Int
        var name: String
        /// "movie" or "tv".
        var mediaType: String
    }
    struct Provider: Codable, Equatable, Hashable, Sendable, Identifiable {
        var id: Int
        var name: String
    }
    struct MediaTypes: Codable, Equatable, Hashable, Sendable {
        var movie = true
        var tv = true
        var anime = true
    }

    var trackedPeople: [Person] = []
    var includeTraktWatchlist = false
    var includeTraktAnticipated = false
    var genres: [Genre] = []
    var watchProviders: [Provider] = []
    var originCountries: [String] = []
    var mediaTypes = MediaTypes()

    init() {}

    /// A value synced from elsewhere may lack any field; each one falls back to its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackedPeople = try container.decodeIfPresent([Person].self, forKey: .trackedPeople) ?? []
        includeTraktWatchlist = try container.decodeIfPresent(Bool.self, forKey: .includeTraktWatchlist) ?? false
        includeTraktAnticipated = try container.decodeIfPresent(Bool.self, forKey: .includeTraktAnticipated) ?? false
        genres = try container.decodeIfPresent([Genre].self, forKey: .genres) ?? []
        watchProviders = try container.decodeIfPresent([Provider].self, forKey: .watchProviders) ?? []
        originCountries = try container.decodeIfPresent([String].self, forKey: .originCountries) ?? []
        mediaTypes = try container.decodeIfPresent(MediaTypes.self, forKey: .mediaTypes) ?? MediaTypes()
    }

    /// Desktop's `buildActiveCount`: each choice made, the two Trakt sources counting one apiece.
    var activeCount: Int {
        genres.count + watchProviders.count + originCountries.count + trackedPeople.count + (includeTraktAnticipated ? 1 : 0) + (includeTraktWatchlist ? 1 : 0)
    }

    /// Desktop's "Clear all": the choices go, the media types stay.
    mutating func clearAll() {
        genres = []; watchProviders = []; originCountries = []; trackedPeople = []
        includeTraktAnticipated = false; includeTraktWatchlist = false
    }

    mutating func toggleGenre(_ genre: Genre) {
        if let index = genres.firstIndex(where: { $0.id == genre.id && $0.mediaType == genre.mediaType }) { genres.remove(at: index) } else { genres.append(genre) }
    }
    mutating func toggleProvider(_ provider: Provider) {
        if let index = watchProviders.firstIndex(where: { $0.id == provider.id }) { watchProviders.remove(at: index) } else { watchProviders.append(provider) }
    }
    mutating func toggleCountry(_ code: String) {
        if let index = originCountries.firstIndex(of: code) { originCountries.remove(at: index) } else { originCountries.append(code) }
    }
    /// Desktop's `addPerson`: a person already followed is not added twice.
    mutating func addPerson(id: Int, name: String, profile: String?) {
        guard !trackedPeople.contains(where: { $0.id == id }) else { return }
        trackedPeople.append(Person(id: id, name: name, profile: profile, role: "any"))
    }
    mutating func removePerson(_ id: Int) { trackedPeople.removeAll { $0.id == id } }

    // MARK: What Desktop offers

    struct GenreOption: Equatable, Sendable {
        let key: String
        /// The genre's name as a translation key; TV-only genres are printed as "{name} (TV)".
        let name: String
        let genre: Genre
        let tvOnly: Bool
    }

    static let providers: [Provider] = [
        Provider(id: 8, name: "Netflix"), Provider(id: 9, name: "Prime Video"), Provider(id: 337, name: "Disney+"), Provider(id: 384, name: "Max"),
        Provider(id: 15, name: "Hulu"), Provider(id: 350, name: "Apple TV+"), Provider(id: 531, name: "Paramount+"), Provider(id: 386, name: "Peacock"),
        Provider(id: 257, name: "FuboTV"), Provider(id: 283, name: "Crunchyroll")]

    static let countries: [(code: String, name: String)] = [
        ("US", "United States"), ("GB", "United Kingdom"), ("CA", "Canada"), ("AU", "Australia"), ("JP", "Japan"), ("KR", "South Korea"), ("CN", "China"),
        ("FR", "France"), ("DE", "Germany"), ("ES", "Spain"), ("IT", "Italy"), ("IN", "India"), ("MX", "Mexico"), ("BR", "Brazil")]

    /// Desktop's `MOVIE_GENRES` and `TV_GENRES` (`lib/feed/tags.ts`), in its order.
    private static let movieGenres: [(String, Int)] = [
        ("Action", 28), ("Adventure", 12), ("Animation", 16), ("Comedy", 35), ("Crime", 80), ("Documentary", 99), ("Drama", 18), ("Family", 10751), ("Fantasy", 14),
        ("History", 36), ("Horror", 27), ("Music", 10402), ("Mystery", 9648), ("Romance", 10749), ("Sci-Fi", 878), ("Thriller", 53), ("War", 10752), ("Western", 37)]
    private static let tvGenres: [(String, Int)] = [
        ("Action & Adventure", 10759), ("Animation", 16), ("Comedy", 35), ("Crime", 80), ("Documentary", 99), ("Drama", 18), ("Mystery", 9648),
        ("Sci-Fi & Fantasy", 10765), ("War", 10768)]

    /// Desktop's `buildGenreOptions`: every movie genre, then the TV genres whose name no movie genre has.
    static let genreOptions: [GenreOption] = {
        var options = movieGenres.map { GenreOption(key: "movie:\($0.1)", name: $0.0, genre: Genre(id: $0.1, name: $0.0, mediaType: "movie"), tvOnly: false) }
        let movieNames = Set(movieGenres.map(\.0))
        options += tvGenres.filter { !movieNames.contains($0.0) }.map { GenreOption(key: "tv:\($0.1)", name: $0.0, genre: Genre(id: $0.1, name: $0.0, mediaType: "tv"), tvOnly: true) }
        return options
    }()
}

/// The Custom source's filters, kept in the profile's settings as one JSON text (`calendar.custom`).
@MainActor @Observable final class CustomCalendarStore {
    static let shared = CustomCalendarStore()
    private static let key = "calendar.custom"
    var value: CustomCalendar { didSet { save() } }

    init() { value = Self.stored() }

    static func stored(_ defaults: UserDefaults = .standard) -> CustomCalendar {
        guard let text = defaults.string(forKey: key), let decoded = try? JSONDecoder().decode(CustomCalendar.self, from: Data(text.utf8)) else { return CustomCalendar() }
        return decoded
    }

    /// Picks up what another profile's settings left in storage.
    func reload() {
        let stored = Self.stored()
        if stored != value { value = stored }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: Self.key)
    }
}
