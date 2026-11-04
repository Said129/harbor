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

| Desktop behavior                                                  | Dependency                                                   | Why there is no iOS form                                                                                 |
| ----------------------------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| Updates and experimental builds (settings → updates, beta-return) | Tauri self-updater, installer channels                       | Distribution and updates belong to the App Store/TestFlight; an app cannot replace itself.               |
| Local torrent engine (`torrent_engine.rs`)                        | A resident peer-to-peer daemon and local streaming server    | iOS suspends background networking and listening sockets; debrid services cover the same sources.        |
| Big Picture (10-foot interface, `views/big-picture`)              | Television/gamepad navigation shell                          | Not a touch layout. Desktop, Android and Android TV are scheduled after iOS.                             |
| Game controllers panel for PC games                               | Gamepad mapping for the Games section                        | Tied to the excluded Games section. Gamepad navigation of the app itself is not excluded.                |
| "P2P" choice of the picker source mode (`streamMode: "p2p"`)      | Puts peer-to-peer results first for the local torrent engine | Without the engine those results only start through a debrid service; Both and Direct/debrid are ported. |

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
   Deliberate differences, to confirm with the owner: the iPhone picker keeps
   listing every source (the filter governs automatic playback, as before), and
   the layout defaults to Condensed (Desktop: Stremio). Still open here: home
   servers (Jellyfin/Emby/Plex video libraries), Easynews, Desktop's custom
   stream filters and facet menu, the addon-loading pill, and placing plugin
   groups in the priority list (they follow all addons).
3. Trackers: AniList, MyAnimeList, Letterboxd.
4. Remaining settings sections and the other features above.
5. Music gaps from `music-subtitle-94-work.md` and the physical subtitle defect
   run in parallel; they need Apple hardware or CI to validate.
