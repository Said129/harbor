import XCTest
@testable import Harbor

/// Desktop's people search (`lib/search.ts`) and person page (`lib/providers/tmdb/tmdb-people.ts`, `views/person/*`) rules, on canned TMDB JSON.
final class TMDBPeopleTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func hit(_ id: Int, _ name: String, profile: String? = "/p.jpg", popularity: Double = 1) -> PersonSearchHit {
        PersonSearchHit(id: id, name: name, profile: profile, knownFor: "", popularity: popularity)
    }

    func testPeopleFromMultiKeepsOrderKnownForAndDepartmentFallbacks() throws {
        let multi = try json("""
        {"results": [
          {"id": 1, "media_type": "person", "name": "Ana Actor", "popularity": 12.5, "profile_path": "/a.jpg",
           "known_for_department": "Acting", "known_for": [{"title": "Movie A"}, {"name": "Show B"}, {"title": "Movie C"}]},
          {"id": 2, "media_type": "person", "name": "Bo Director", "popularity": 40.0, "profile_path": null,
           "known_for_department": "Directing", "known_for": []},
          {"id": 3, "media_type": "movie", "title": "Movie A", "poster_path": "/m.jpg"},
          {"id": 4, "media_type": "person", "name": "Cy Unknown", "popularity": 40, "profile_path": "/c.jpg",
           "known_for": [{"title": ""}]}
        ]}
        """)
        let people = TMDBPeople.people(fromMulti: multi)
        XCTAssertEqual(people.map(\.id), [1, 2, 4])
        XCTAssertEqual(people[0].knownFor, "Movie A, Show B")
        XCTAssertEqual(people[1].knownFor, "Directing")
        XCTAssertEqual(people[2].knownFor, "Cast")
        let ranked = TMDBPeople.ranked(people)
        XCTAssertEqual(ranked.map(\.id), [2, 4, 1], "equal popularity keeps TMDB order")
        XCTAssertEqual(TMDBPeople.railPeople(ranked).map(\.id), [4, 1], "people without a photo are not in the rail")
    }

    func testRankingKeepsTenMostPopularBeforePhotoFilter() {
        let people = (1...12).map { index in
            hit(index, "Person \(index)", profile: index % 2 == 0 ? "/p\(index).jpg" : nil, popularity: Double(index))
        }
        let ranked = TMDBPeople.ranked(people)
        XCTAssertEqual(ranked.count, TMDBPeople.searchLimit)
        XCTAssertEqual(ranked.first?.id, 12)
        XCTAssertEqual(ranked.last?.id, 3)
        XCTAssertEqual(TMDBPeople.railPeople(ranked).map(\.id), [12, 10, 8, 6, 4])
    }

    func testFuzzyFallbackOnlyForSeveralWordsWithoutTitleMatchesOrWithPeople() throws {
        let none = try json(#"{"results": []}"#)
        let personOnly = try json(#"{"results": [{"id": 9, "media_type": "person", "name": "Tom Hanks"}]}"#)
        let posterMovie = try json(#"{"results": [{"id": 3, "media_type": "movie", "poster_path": "/m.jpg"}]}"#)
        let posterless = try json(#"{"results": [{"id": 3, "media_type": "tv", "poster_path": null}]}"#)
        XCTAssertFalse(TMDBPeople.needsFuzzyFallback(query: "Tom", multi: none), "a single word never falls back")
        XCTAssertTrue(TMDBPeople.needsFuzzyFallback(query: "Tom Hanks", multi: none))
        XCTAssertTrue(TMDBPeople.needsFuzzyFallback(query: "Tom Hanks", multi: personOnly))
        XCTAssertFalse(TMDBPeople.needsFuzzyFallback(query: "Tom Hanks", multi: posterMovie))
        XCTAssertTrue(TMDBPeople.needsFuzzyFallback(query: "Tom Hanks", multi: posterless), "a show without a poster does not count")
    }

    func testFuzzyTokenIsTheLongestWordOfThreeCharactersOrMore() {
        XCTAssertEqual(TMDBPeople.fuzzyToken("Jon Favreau"), "Favreau")
        XCTAssertEqual(TMDBPeople.fuzzyToken("Al Pacino Jr"), "Pacino")
        XCTAssertEqual(TMDBPeople.fuzzyToken("Bob Lee Ray"), "Bob", "a tie keeps the first word")
        XCTAssertNil(TMDBPeople.fuzzyToken("a bc"))
    }

    func testFuzzyMergeAddsOnlyCloseNewNames() throws {
        let extra = try json("""
        {"results": [
          {"id": 1, "name": "Jon Favreau", "popularity": 9},
          {"id": 2, "name": "Jon Favrau", "popularity": 3, "profile_path": null},
          {"id": 3, "name": "Bob Smith", "popularity": 50}
        ]}
        """)
        let merged = TMDBPeople.merging([hit(1, "Jon Favreau")], extra: extra, query: "Jon Favreau")
        XCTAssertEqual(merged.map(\.id), [1, 2])
        XCTAssertEqual(merged.last?.name, "Jon Favrau")
    }

    func testNameCloseToUsesContainmentThenEditDistance() {
        XCTAssertTrue(TMDBPeople.nameCloseTo("Tom Hanks", "tom hanks"))
        XCTAssertTrue(TMDBPeople.nameCloseTo("Tom Hank", "Tom Hanks"))
        XCTAssertTrue(TMDBPeople.nameCloseTo("Jon Favrau", "Jon Favreau"))
        XCTAssertFalse(TMDBPeople.nameCloseTo("Bob Smith", "Ana Lopez"))
        XCTAssertFalse(TMDBPeople.nameCloseTo("", "Ana Lopez"))
        XCTAssertEqual(TMDBPeople.editDistance("kitten", "sitting"), 3)
    }

    func testMatchPersonNeedsPhotoAndNamePrefixOfThreeCharacters() {
        let people = [hit(1, "Tom Hanks")]
        XCTAssertEqual(TMDBPeople.matchPerson(people, query: "Tom Hanks")?.id, 1)
        XCTAssertEqual(TMDBPeople.matchPerson(people, query: "Tom")?.id, 1)
        XCTAssertNil(TMDBPeople.matchPerson(people, query: "To"), "fewer than three characters never match")
        XCTAssertNil(TMDBPeople.matchPerson(people, query: "Hanks"))
        XCTAssertNil(TMDBPeople.matchPerson([hit(1, "Tom Hanks", profile: nil)], query: "Tom Hanks"))
    }

    func testProfileDedupesCastSortsByPopularityAndBuildsFilmography() throws {
        let value = try json(personJSON(othersCount: 5))
        let profile = try XCTUnwrap(TMDBPeople.profile(value, englishName: nil))
        XCTAssertEqual(profile.name, "Lena Star")
        XCTAssertEqual(profile.birthday, "1970-06-15")
        XCTAssertEqual(profile.placeOfBirth, "Lisbon")
        XCTAssertEqual(profile.cast.count, 3, "the duplicate movie 1 is merged")
        XCTAssertEqual(profile.cast.map(\.id), [1, 2, 3])
        XCTAssertEqual(profile.cast.first?.popularity, 60, "the higher popularity copy wins")
        XCTAssertEqual(profile.cast.first?.character, "Nora (dup)")

        let sections = TMDBPeople.filmography(profile)
        XCTAssertEqual(sections.map(\.title), ["Movies · {n}", "TV Shows · {n}", "Directing", "Writing", "Other Work"])
        XCTAssertEqual(sections[0].items.map(\.id), [1, 3])
        XCTAssertEqual(sections[1].items.map(\.id), [2])
        XCTAssertEqual(sections[4].items.count, 5, "other crew shows once there are more than four")
    }

    func testKnownForSkipsCameosAndRanksByNotableScore() throws {
        let profile = try XCTUnwrap(TMDBPeople.profile(try json(personJSON(othersCount: 0)), englishName: nil))
        let known = TMDBPeople.knownFor(profile)
        XCTAssertEqual(known.map(\.id), [1, 2], "movie 3 is a self cameo and is left out")
        XCTAssertEqual(known.map(\.title), ["Big Film", "Small Show"])
    }

    func testKnownForCrewUsesDepartmentAndOneEntryPerTitle() throws {
        let value = try json("""
        {"id": 500, "name": "Dana Cut", "known_for_department": "Directing", "biography": "",
         "combined_credits": {
           "cast": [],
           "crew": [
             {"id": 10, "media_type": "movie", "title": "Dir Film", "popularity": 30, "vote_count": 400, "job": "Director", "department": "Directing"},
             {"id": 10, "media_type": "movie", "title": "Dir Film", "popularity": 25, "vote_count": 400, "job": "Director", "department": "Directing"},
             {"id": 11, "media_type": "movie", "title": "Writer Film", "popularity": 90, "vote_count": 800, "job": "Writer", "department": "Writing"}
           ]}}
        """)
        let profile = try XCTUnwrap(TMDBPeople.profile(value, englishName: nil))
        XCTAssertEqual(TMDBPeople.knownFor(profile).map(\.id), [10])
        XCTAssertEqual(TMDBPeople.knownFor(profile).first?.popularity, 30)
    }

    func testCreditMapsToHarborMediaWithSeriesType() throws {
        let credit = try XCTUnwrap(TMDBPeople.credit(try json("""
        {"id": 77, "media_type": "tv", "name": "Show Name", "popularity": 3, "vote_count": 5, "vote_average": 7.4,
         "first_air_date": "2011-02-03", "poster_path": "/s.jpg", "character": "Doc", "episode_count": 9}
        """)))
        let media = TMDBPeople.media(for: credit)
        XCTAssertEqual(media.id, "tmdb:tv:77")
        XCTAssertEqual(media.type, "series")
        XCTAssertEqual(media.name, "Show Name")
        XCTAssertEqual(media.releaseInfo, "2011")
        XCTAssertEqual(media.imdbRating, "7.4")
        XCTAssertEqual(media.ratingSource, "TMDB")
        XCTAssertEqual(media.poster, "https://image.tmdb.org/t/p/w342/s.jpg")
        XCTAssertEqual(TMDBPeople.caption(credit), "Doc · 2011")
    }

    func testCaptionFallsBackToJobWhenThereIsNoCharacter() throws {
        let credit = try XCTUnwrap(TMDBPeople.credit(try json("""
        {"id": 12, "media_type": "movie", "title": "Dir Film", "job": "Director", "release_date": "2019-05-05"}
        """)))
        XCTAssertEqual(TMDBPeople.caption(credit), "Director · 2019")
    }

    func testOtherCrewStaysHiddenUpToFourCredits() throws {
        let profile = try XCTUnwrap(TMDBPeople.profile(try json(personJSON(othersCount: 4)), englishName: nil))
        XCTAssertFalse(TMDBPeople.filmography(profile).contains { $0.title == "Other Work" })
    }

    func testEnglishNameIsRequestedOnlyWhenLocalizedNameIsTheOriginal() throws {
        let original = try json(#"{"id": 1, "name": "田中", "original_name": "田中"}"#)
        let translated = try json(#"{"id": 1, "name": "Tanaka", "original_name": "田中"}"#)
        XCTAssertTrue(TMDBPeople.needsEnglishName(original, language: "ja-JP"))
        XCTAssertFalse(TMDBPeople.needsEnglishName(original, language: "en-US"))
        XCTAssertFalse(TMDBPeople.needsEnglishName(translated, language: "ja-JP"))
        let profile = try XCTUnwrap(TMDBPeople.profile(original, englishName: "Tanaka"))
        XCTAssertEqual(profile.name, "Tanaka")
    }

    func testAgeCountsWholeYearsAtDeathOrToday() throws {
        let calendar = TMDBPeople.utcCalendar
        let beforeBirthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14)))
        let onBirthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        XCTAssertEqual(TMDBPeople.age(birthday: "1970-06-15", deathday: nil, now: beforeBirthday, calendar: calendar), 55)
        XCTAssertEqual(TMDBPeople.age(birthday: "1970-06-15", deathday: nil, now: onBirthday, calendar: calendar), 56)
        XCTAssertEqual(TMDBPeople.age(birthday: "1970-06-15", deathday: "2000-01-02", now: onBirthday, calendar: calendar), 29)
        XCTAssertNil(TMDBPeople.age(birthday: "unknown", deathday: nil, now: onBirthday, calendar: calendar))
    }

    func testDisplayDateKeepsUnparsedInput() {
        XCTAssertEqual(TMDBPeople.displayDate("not a date"), "not a date")
        XCTAssertTrue(TMDBPeople.displayDate("1970-06-15").contains("1970"))
    }

    func testPhotoURLUsesTheRequestedSize() {
        XCTAssertEqual(TMDBPeople.photoURL("/lena.jpg", size: "h632"), "https://image.tmdb.org/t/p/h632/lena.jpg")
        XCTAssertNil(TMDBPeople.photoURL(nil, size: "h632"))
        XCTAssertNil(TMDBPeople.photoURL("", size: "h632"))
    }

    /// A person with one duplicated movie, a movie cameo, a TV show, a director credit, a writer credit and `othersCount` other crew credits.
    private func personJSON(othersCount: Int) -> String {
        let others = (0..<othersCount).map { index in
            #"{"id": \#(900 + index), "media_type": "movie", "title": "Crew \#(index)", "popularity": 1, "job": "Makeup Artist", "department": "Crew"}"#
        }
        let crew = [
            #"{"id": 10, "media_type": "movie", "title": "Dir Film", "popularity": 30, "vote_count": 400, "job": "Director", "department": "Directing"}"#,
            #"{"id": 11, "media_type": "movie", "title": "Writer Film", "popularity": 10, "vote_count": 50, "job": "Writer", "department": "Writing"}"#,
        ] + others
        return """
        {"id": 500, "name": "Lena Star", "original_name": "Lena Star", "biography": "Bio text",
         "birthday": "1970-06-15", "deathday": null, "place_of_birth": "Lisbon",
         "known_for_department": "Acting", "profile_path": "/lena.jpg",
         "combined_credits": {
           "cast": [
             {"id": 1, "media_type": "movie", "title": "Big Film", "popularity": 50, "vote_count": 900, "vote_average": 7.5, "character": "Nora", "release_date": "2010-03-01", "poster_path": "/b.jpg", "order": 0},
             {"id": 1, "media_type": "movie", "title": "Big Film", "popularity": 60, "vote_count": 900, "vote_average": 7.5, "character": "Nora (dup)", "release_date": "2010-03-01", "order": 0},
             {"id": 2, "media_type": "tv", "name": "Small Show", "popularity": 20, "vote_count": 300, "vote_average": 8.0, "character": "Self", "episode_count": 10, "first_air_date": "2015-09-01"},
             {"id": 3, "media_type": "movie", "title": "Cameo Movie", "popularity": 5, "vote_count": 10, "character": "Self", "release_date": "2001-01-01"}
           ],
           "crew": [\(crew.joined(separator: ", "))]
         }}
        """
    }
}
