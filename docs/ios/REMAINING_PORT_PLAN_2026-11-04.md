# Remaining Desktop 0.9.132 → iOS/iPadOS port: verified gaps and plan (4 November 2026)

This is an audit of the code, not a completion percentage. The reproducible
inventory (`desktop-parity-0.9.132.json`) has 435 of 438 behaviors and all 511
settings still at `pending_reference_review`, and 486 settings have no lexical
native candidate, so it cannot say what is missing. Each gap below was checked
by searching the Swift/Rust sources for the feature and by reading the Desktop
module. Nothing here is compiled or executed on Apple yet.

## Scope rules applied

The owner's scope excludes Games/PC libraries and the Kids section, and anything
that has no meaning or no compatible form on iOS. `DESKTOP_PARITY_0_9_132.md`
adds that a feature which is merely hard is not excluded, and that every extra
exclusion records the Desktop behavior, its concrete PC dependency and why it has
no mobile form. The list below follows that.

### Excluded (concrete platform reason)

| Desktop behavior                                                                                                                                                                                           | Dependency                                                   | Why there is no iOS form                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| Updates and experimental builds (settings → updates, beta-return)                                                                                                                                          | Tauri self-updater, installer channels                       | Distribution and updates belong to the App Store/TestFlight; an app cannot replace itself.                          |
| Local torrent engine (`torrent_engine.rs`)                                                                                                                                                                 | A resident peer-to-peer daemon and local streaming server    | iOS suspends background networking and listening sockets; debrid services cover the same sources.                   |
| Big Picture (10-foot interface, `views/big-picture`)                                                                                                                                                       | Television/gamepad navigation shell                          | Not a touch layout. Desktop, Android and Android TV are scheduled after iOS.                                        |
| Game controllers panel for PC games                                                                                                                                                                        | Gamepad mapping for the Games section                        | Tied to the excluded Games section. Gamepad navigation of the app itself is not excluded.                           |
| "P2P" choice of the picker source mode (`streamMode: "p2p"`)                                                                                                                                               | Puts peer-to-peer results first for the local torrent engine | Without the engine those results only start through a debrid service; Both and Direct/debrid are ported.            |
| Desktop windowing: fullscreen restore/keep/mode, embedded or separate player window, native/hybrid title bar, drag anywhere, tray, pause when minimized/unfocused, Esc exits fullscreen, HDR opaque window | Resizable OS windows, a system tray and window focus         | An iOS app is always full screen in its scene; the system owns backgrounding and focus.                             |
| Graphics and display options: Direct3D flip, mpv renderer and UI graphics backend, RTX HDR/VSR, macOS EDR, display panel, HDR stage, SVP motion interpolation                                              | Windows/macOS GPU drivers and the Windows-only SVP app       | iOS renders through one Metal/OpenGL ES path chosen by the system. Motion interpolation inside mpv is not excluded. |
| Player engine choice (`playerEngine`)                                                                                                                                                                      | Several Desktop players (web, embedded mpv, external)        | iOS has one native libmpv engine.                                                                                   |
| Custom CSS/JS/HTML (`customCss`, `customJs`, `customHtml`)                                                                                                                                                 | Desktop's interface is a web view with a DOM                 | The iOS interface is native SwiftUI; there is no page to inject into.                                               |
| Smooth scrolling (`smoothScroll`)                                                                                                                                                                          | Wheel/trackpad scroll smoothing in the web view              | iOS scrolling is native.                                                                                            |
| Download folders (`downloadDir`, `ebookDownloadDir` and their sub-folder options)                                                                                                                          | Writing to any folder on disk                                | Files stay in the app's sandbox and are shared through the Files app.                                               |
| Discord Rich Presence (`discord*`)                                                                                                                                                                         | IPC with the Discord desktop client                          | There is no Discord client IPC on iOS.                                                                              |
| Progressive media proxy (`stream_proxy.rs` progressive route)                                                                                                                                              | Serving media to Desktop's web player                        | The native player plays the source directly; request headers go to mpv (ported).                                    |
| **Pending owner approval:** idle screensaver (`screensaver*`)                                                                                                                                              | An idle overlay on an always-on desktop screen               | iOS auto-lock normally turns the screen off. Weak reason: the app already keeps the screen awake while playing.     |
| **Pending owner approval:** pointer hover previews and styles (`hoverPreview*`, `cardHover*`, `customHoverId`, `seekDotHover`, `musicSeekThumbHover`)                                                      | A mouse pointer over cards and the seek bar                  | Touch has no hover. Weak reason: iPads with a trackpad or mouse do have a pointer.                                  |

### Not excluded, undecided (needs a feasibility review, not a default exclusion)

DVR (continuous live recording), multi-view (several simultaneous mpv instances),
webhooks, relay, remote pairing. Each has an iOS form to evaluate before any
exclusion is recorded.

## Verified missing (no Swift implementation found)

1. **Debrid services** (`src/lib/debrid`, 67 KB): Real-Debrid, TorBox, AllDebrid,
   Premiumize and Debrid-Link. iOS currently answers every infoHash/magnet
   stream with "requires the torrent engine or Debrid, still pending on iPhone"
   (`CoreBridge.swift`, `dispatch.rs`).
2. **Streaming sources panel** beyond catalogs: stream safety filter, stream
   sorting, play-picker layout, home servers, Easynews (the iOS "Streaming
   services" page is only Desktop's streaming-catalogs section).
3. **Trackers**: AniList (27 modules), MyAnimeList (14) and Letterboxd. Only Trakt
   and Simkl exist.
4. **Settings sections** with no native counterpart: card badges, award icons,
   hotkeys (iPad hardware keyboard), controllers (app navigation), remotes,
   relay, webhooks, backup row, bug report, licenses, app icons.
5. Other features with no match: AI search, ad skip, Watch Together, ratings
   matrix, EPG guide, person/people pages (naming differs, to be re-checked).

## Order

Debrid first because it blocks playing a whole class of streams for users who
configure the service in Harbor itself.

1. Debrid: clients, key storage and the settings page (done), and the stream
   pipeline connection (done, uncompiled): provider cache and library
   verification before ranking through a new Rust `DebridFlags` input and
   `cacheVerified` field, active debrids in the score options, torrent-only
   streams resolved at play time (cached-first order, error-clip validation),
   automatic selection limited to verified torrents. Still open: prefetching
   the first prepared links, streams listed from the debrid library, queueing
   an uncached source from the picker and per-provider health badges.
2. Streaming sources panel (Settings › Streaming sources, uncompiled): Services
   (link to Debrid), Filters (safety filter, addon wait time), Sorting (Harbor
   ranking or addon order, stream priority list with move/reset and uninstalled
   entries, aggregator note) and Picker (Condensed or Stremio layout, source
   mode, Refresh next to Back, release names, full descriptions). Effects: the
   wait time is `max(addon budget, setting)` per request as Desktop's
   `timeoutFor`, the priority list re-ranks the requests and reorders the
   ranked list (`applyStreamPriority`), the source mode filters the picker and
   automatic selection without ever emptying it and can be switched live in
   the picker, and a new Stremio layout lists each addon's own text. Policy is
   in `StreamSourcePolicy.swift`, tests in `StreamSourcePolicyTests.swift`.
   Owner decision (4 November): match Desktop. The picker now shows what the
   safety filter keeps (automatic play picks from that same list), with
   Desktop's recovery: "N sources · 0 made it through" with the rejection
   groups and Search wider (Strict → Balanced → everything), the "Only 1/2
   sources after filtering" warning with Show everything anyway, and the "no
   debrid is configured" state with Set up a debrid; the relaxed level lasts
   until another title, episode or safety level. The layout defaults to
   Stremio; UI tests of the Condensed picker pass `-streams.pickerLayout
condensed`, and the synthetic caption flow also passes `-streamFilterLevel
off` (its clip is not a real release). The safety filter now receives
   Desktop's IMDb-aligned episode (`effSeason`/`effEpisode`), and the automatic
   start skips episode checks for anime ids as Desktop does. To verify on
   Apple: anime episodes whose listed numbering differs from the IMDb
   coordinates, which Desktop's trust may also reject (its alias filter is not
   ported); and the two opt-in Live UI picker flows, whose Big Buck Bunny item
   has an IMDb id, so its streams now pass through the Strict filter. Not ported from the empty ladder: the "still in theatres" state,
   the unresolved-ID state and the source-outage notice. Still open here: home
   servers (Jellyfin/Emby/Plex video libraries), Easynews, Desktop's custom
   stream filters and facet menu, the per-addon "Waiting for" chip, and placing
   plugin groups in the priority list (they follow all addons).
   Progressive results (uncompiled), as Desktop's `runPipeline` and
   `use-auto-fire.ts`: every answer is ranked into a partial list (at most every
   250 ms) that the picker shows with an "addons loading" pill; debrid
   verification runs alongside on new hashes (at most every 1.5 s) and once
   more before the final list; offers keep a stable identity across partials
   so a selection does not jump. Automatic play starts a confident instant
   source after 350 ms, otherwise once the list settles (playable top 1.5 s
   after the first result, 4 s for an episode without an exact cached file,
   80 % of the requests answered, or 10 s), and always when every addon has
   answered; a remembered next-episode source that has not answered yet is
   waited for. Not ported in the settle: preferred-language checks, Watch
   Together host source, Desktop's own automatic candidate ranking
   (`use-auto-candidates.ts`; iPhone keeps `StreamPreferences.preferred`), so
   its title-name check (`nameKnown` → `nameAbsent`) never applies, and the
   retry with the next candidate after a failed automatic start
   (`autoAttemptIdx`; iPhone stops and shows the picker with the error). Retained cases to rerun with this:
   LiveNavigationTests source-picker and change-source flows (they wait
   15–30 s for offers and assume the Condensed picker), NativeDataTests stream
   preferences, MobileSourcesAndSubtitlesTests and DebridStreamTests automatic
   ranking, LiveServicesTests streams.
3. Trackers: AniList, MyAnimeList, Letterboxd.
4. Remaining settings sections and the other features above.
5. Music gaps from `music-subtitle-94-work.md` and the physical subtitle defect
   run in parallel; they need Apple hardware or CI to validate.
