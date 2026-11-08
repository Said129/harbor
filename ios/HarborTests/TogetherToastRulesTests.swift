import XCTest
@testable import Harbor

/// Desktop's `together-invite-toast.tsx`, `together-summon-toast.tsx`, `build-invite.ts` and `use-room-invite.ts`.
final class TogetherToastRulesTests: XCTestCase {
    func testInviteKeyNamesTitleSeasonAndEpisode() {
        XCTAssertEqual(TogetherInviteRules.key(mediaId: "tt1", season: nil, episode: nil), "tt1||")
        XCTAssertEqual(TogetherInviteRules.key(mediaId: "tt1", season: 2, episode: 5), "tt1|2|5")
        XCTAssertEqual(TogetherInviteRules.key(mediaId: "tt1", season: 2, episode: 5),
                       TogetherRoomDerive.inviteKey(TogetherInviteRules.invite(media: Media(id: "tt1", type: "series", name: "Show"),
                                                                                episode: Episode(id: "e", season: 2, episode: 5))))
    }

    func testOnlyAJoinedRoomWithoutAnotherHostIsInvitedOncePerKey() {
        XCTAssertTrue(TogetherInviteRules.shouldInvite(joined: true, invitedToKey: false, foreignHost: false, alreadySent: false))
        XCTAssertFalse(TogetherInviteRules.shouldInvite(joined: false, invitedToKey: false, foreignHost: false, alreadySent: false))
        XCTAssertFalse(TogetherInviteRules.shouldInvite(joined: true, invitedToKey: true, foreignHost: false, alreadySent: false))
        XCTAssertFalse(TogetherInviteRules.shouldInvite(joined: true, invitedToKey: false, foreignHost: true, alreadySent: false))
        XCTAssertFalse(TogetherInviteRules.shouldInvite(joined: true, invitedToKey: false, foreignHost: false, alreadySent: true))
    }

    func testEpisodeReferenceNeedsSeasonAndNumber() {
        XCTAssertNil(TogetherInviteRules.episodeRef(nil))
        XCTAssertNil(TogetherInviteRules.episodeRef(Episode(id: "e", season: 1, episode: nil)))
        var episode = Episode(id: "e", season: 1, episode: 3)
        episode.title = "Pilot"; episode.imdbID = "tt9"; episode.imdbSeason = 1; episode.imdbEpisode = 4
        episode.absoluteNumber = 13; episode.tvdbEpisodeID = 77
        let ref = TogetherInviteRules.episodeRef(episode)
        XCTAssertEqual(ref?.season, 1); XCTAssertEqual(ref?.episode, 3); XCTAssertEqual(ref?.name, "Pilot")
        XCTAssertEqual(ref?.imdbId, "tt9"); XCTAssertEqual(ref?.imdbEpisode, 4)
        XCTAssertEqual(ref?.absoluteNumber, 13); XCTAssertEqual(ref?.tvdbEpisodeId, 77)
    }

    func testInviteCarriesTheTitleAndSendsAnimeAsASeries() {
        var media = Media(id: "kitsu:1", type: "anime", name: "Anime")
        media.poster = "p"; media.background = "b"; media.logo = "l"; media.releaseInfo = "2024"
        let anime = TogetherInviteRules.invite(media: media, episode: nil)
        XCTAssertEqual(anime.mediaType, "series")
        XCTAssertEqual([anime.mediaId, anime.mediaTitle, anime.posterUrl, anime.backgroundUrl, anime.logoUrl, anime.releaseInfo],
                       ["kitsu:1", "Anime", "p", "b", "l", "2024"])
        XCTAssertNil(anime.episode)
        XCTAssertEqual(TogetherInviteRules.invite(media: Media(id: "tt2", type: "movie", name: "Film"), episode: nil).mediaType, "movie")
        XCTAssertEqual(TogetherInviteRules.invite(media: Media(id: "tt3", type: "series", name: "Show"), episode: nil).mediaType, "series")
    }

    func testInviteToastOpensTheInvitedTitle() {
        let invite = TogetherInviteBuilder.playInvite(mediaId: "tt5", isSeries: true, title: "Show", releaseInfo: "2020", poster: "p",
                                                      background: "b", logo: "l", episode: nil)
        let media = TogetherToastRules.media(from: invite)
        XCTAssertEqual(media.id, "tt5"); XCTAssertEqual(media.type, "series"); XCTAssertEqual(media.name, "Show")
        XCTAssertEqual([media.poster, media.background, media.logo, media.releaseInfo], ["p", "b", "l", "2020"])
    }

    func testEpisodeLabelPrefersImdbNumbersAndPadsTheEpisode() {
        XCTAssertNil(TogetherToastRules.episodeLabel(nil))
        XCTAssertEqual(TogetherToastRules.episodeLabel(TogetherEpisodeRef(season: 2, episode: 3)), "S2 · E03")
        XCTAssertEqual(TogetherToastRules.episodeLabel(TogetherEpisodeRef(season: 2, episode: 3, imdbSeason: 1, imdbEpisode: 12)), "S1 · E12")
    }

    func testSummonViewsMapToSections() {
        func destination(_ view: String) -> TogetherSummonDestination? { TogetherToastRules.destination(TogetherSummonTarget(view: view)) }
        XCTAssertEqual(destination("home"), .section(.home))
        XCTAssertEqual(destination("discover"), .section(.discover))
        XCTAssertEqual(destination("anime"), .section(.anime))
        XCTAssertEqual(destination("queue"), .section(.library))
        XCTAssertEqual(destination("addons"), .section(.addons))
        XCTAssertNil(destination("somewhere"))
    }

    func testSummonToAnAddonOrATitle() {
        XCTAssertEqual(TogetherToastRules.destination(TogetherSummonTarget(addonId: "a1")), .section(.addons))
        var target = TogetherSummonTarget(mediaId: "tt7", mediaType: "movie", mediaTitle: "Film")
        target.posterUrl = "p"; target.backgroundUrl = "b"; target.releaseInfo = "1999"
        guard case .media(let media)? = TogetherToastRules.destination(target) else { return XCTFail("a title summon opens the title") }
        XCTAssertEqual(media.id, "tt7"); XCTAssertEqual(media.name, "Film"); XCTAssertEqual(media.poster, "p"); XCTAssertEqual(media.releaseInfo, "1999")
        XCTAssertNil(TogetherToastRules.destination(TogetherSummonTarget(mediaId: "tt7", mediaType: "movie")), "a title needs its name")
        XCTAssertNil(TogetherToastRules.destination(TogetherSummonTarget()))
    }

    func testSummonHeadlinePrefersTheSenderLabel() {
        XCTAssertEqual(TogetherToastRules.headline(TogetherSummonTarget(addonId: "a", label: "My addon")), "My addon")
        XCTAssertEqual(TogetherToastRules.headline(TogetherSummonTarget(view: "home", label: "Tonight")), "Tonight")
        XCTAssertEqual(TogetherToastRules.headline(TogetherSummonTarget(mediaId: "tt1", mediaType: "movie", mediaTitle: "Film")), "Film")
        XCTAssertEqual(TogetherToastRules.headline(TogetherSummonTarget(view: "elsewhere")), "elsewhere")
    }
}
