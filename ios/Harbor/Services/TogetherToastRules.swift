import Foundation

/// Desktop's `build-invite.ts` and `use-room-invite.ts`: opening a title's sources while joined to a room that has no other host
/// makes this device the host and sends the play invite once for each title and episode.
enum TogetherInviteRules {
    static func key(mediaId: String, season: Int?, episode: Int?) -> String {
        mediaId + "|" + (season.map(String.init) ?? "") + "|" + (episode.map(String.init) ?? "")
    }

    /// `canInvite` of use-room-invite.ts plus the once-per-key guard of its `inviteSentRef`.
    static func shouldInvite(joined: Bool, invitedToKey: Bool, foreignHost: Bool, alreadySent: Bool) -> Bool {
        joined && !invitedToKey && !foreignHost && !alreadySent
    }

    /// `toEpisodeRef`: an episode without a season and number cannot be named in an invite.
    static func episodeRef(_ episode: Episode?) -> TogetherEpisodeRef? {
        guard let episode, let season = episode.season, let number = episode.episode else { return nil }
        return TogetherEpisodeRef(season: season, episode: number, name: episode.name ?? episode.title, imdbId: episode.imdbID,
                                  imdbSeason: episode.imdbSeason, imdbEpisode: episode.imdbEpisode,
                                  absoluteNumber: episode.absoluteNumber, tvdbEpisodeId: episode.tvdbEpisodeID)
    }

    /// `buildPlayInvite`. Desktop only knows movies and series, so an anime title goes out as a series.
    static func invite(media: Media, episode: Episode?) -> TogetherPlayInvite {
        TogetherInviteBuilder.playInvite(mediaId: media.id, isSeries: media.type == "series" || media.type == "anime", title: media.name,
                                         releaseInfo: media.releaseInfo, poster: media.poster, background: media.background,
                                         logo: media.logo, episode: episodeRef(episode))
    }
}

/// Where a summon sends the guest (`together-summon-toast.tsx`).
enum TogetherSummonDestination: Equatable {
    case section(HarborSection)
    case media(Media)
}

/// What the invite and summon toasts show and open. Desktop's rules, without the screens.
enum TogetherToastRules {
    /// The `Meta` the invite toast opens.
    static func media(from invite: TogetherPlayInvite) -> Media {
        var media = Media(id: invite.mediaId, type: invite.mediaType, name: invite.mediaTitle)
        media.poster = invite.posterUrl
        media.background = invite.backgroundUrl
        media.logo = invite.logoUrl
        media.releaseInfo = invite.releaseInfo
        return media
    }

    /// `S1 · E02`; the IMDb numbering wins when the invite carries it.
    static func episodeLabel(_ episode: TogetherEpisodeRef?) -> String? {
        guard let episode else { return nil }
        let season = episode.imdbSeason ?? episode.season
        let number = episode.imdbEpisode ?? episode.episode
        return "S\(season) · E" + (number < 10 ? "0" : "") + String(number)
    }

    /// Nil when the summon names nothing this app can open; accepting it then only closes the toast.
    static func destination(_ target: TogetherSummonTarget) -> TogetherSummonDestination? {
        if let view = target.view {
            switch view {
            case "home": return .section(.home)
            case "discover": return .section(.discover)
            case "anime": return .section(.anime)
            case "queue": return .section(.library)
            case "addons": return .section(.addons)
            default: return nil
            }
        }
        if target.addonId != nil { return .section(.addons) }
        guard let id = target.mediaId, let type = target.mediaType, let title = target.mediaTitle else { return nil }
        var media = Media(id: id, type: type, name: title)
        media.poster = target.posterUrl
        media.background = target.backgroundUrl
        media.releaseInfo = target.releaseInfo
        return .media(media)
    }

    static func headline(_ target: TogetherSummonTarget) -> String {
        if target.addonId != nil { return nonEmpty(target.label) ?? DesktopInterfaceText.value("an addon") }
        if let view = target.view { return nonEmpty(target.label) ?? viewLabel(view) }
        return nonEmpty(target.mediaTitle) ?? DesktopInterfaceText.value("a title")
    }

    private static func viewLabel(_ view: String) -> String {
        switch view {
        case "home": return DesktopInterfaceText.value("Home")
        case "discover": return DesktopInterfaceText.value("Discover")
        case "anime": return DesktopInterfaceText.value("Anime")
        case "queue": return DesktopInterfaceText.value("My Library")
        default: return view
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
