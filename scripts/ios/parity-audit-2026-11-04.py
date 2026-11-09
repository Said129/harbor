"""Code-level parity audit of the Desktop 0.9.132 inventory against the iOS sources (4 November 2026).

Each behavior and setting of docs/ios/desktop-parity-0.9.132.json gets one verdict:
  D  ported: an iOS implementation of the same behavior exists in the code
  P  partial: implemented in part, or an earlier review recorded it as Partial
  M  missing: no iOS implementation found
  X  excluded: owner exclusion or a recorded platform reason (not in the denominator)
The verdicts are a reading of the code, not runtime validation: nothing written since the last
successful Apple build has been compiled. Run: python -I scripts/ios/parity-audit-2026-11-04.py
"""
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INVENTORY = json.loads((ROOT / "docs/ios/desktop-parity-0.9.132.json").read_text("utf-8"))

def expand(spec):
    """'1-3 D note; 5 M note' -> {1: ('D', 'note'), ...}; later entries win."""
    result = {}
    for part in filter(None, (p.strip() for p in spec.split("\n"))):
        ids, verdict, *note = part.split(" ", 2)
        start, _, end = ids.partition("-")
        for index in range(int(start), int(end or start) + 1):
            result[index] = (verdict, note[0] if note else "")
    return result

# Areas group the verdicts for the report; ranges follow the inventory order.
BEHAVIOR_AREAS = [
    (1, 21, "Home, Discover and rooms"), (22, 32, "Search"), (33, 47, "Details and episodes"),
    (48, 67, "Addons and catalogs"), (68, 106, "Stream pipeline, parser, trust and scoring"),
    (107, 135, "Resolution and Debrid"), (136, 153, "Torrent engine and streaming server"),
    (154, 216, "Player, subtitles, skip, trailers and downloads"), (217, 238, "Live TV, VOD, DVR and multiview"),
    (239, 259, "Casting and Watch Together"), (260, 273, "Stremio account, library and local files"),
    (274, 304, "Trackers"), (305, 323, "Metadata providers, calendar and lists"),
    (324, 365, "Profiles, appearance, integrations and system"), (366, 390, "Manga"),
    (391, 401, "Sports"), (402, 409, "Home customization"), (410, 417, "VOD details"),
    (418, 421, "Spooktober"), (422, 437, "Music"), (438, 438, "Subtitle FPS"),
]

BEHAVIORS = expand("""
1-3 P earlier review Partial; personalised rails and physical checks incomplete
4 D homeMode classic
5-6 P DiscoverView, DiscoveryRails, DiscoveryPreferences
7 M no Critics Pick rail
8 P genre preferences in DiscoveryPreferences
9 D DiscoveryQueueView with UI test
10-11 P earlier review Partial
12 P decade rails in TMDBService; no mood rails
13 P earlier review Partial
14-15 P generic ContentPageView rooms
16 P TMDB premieres; no network rails
17 P earlier review Partial
18-21 P DesktopAnimeRows and MAL/AniList public rows
22-24 P earlier review Partial
25 P addon search aggregation
26 M no people search
27 P anime results section in SearchView
28 M no Live TV search
29 D direct video URL card (5 Nov, uncompiled)
30 P magnet and info-hash card plays through debrid only (5 Nov, uncompiled)
31-32 M no search guide or AI search
33-35 P earlier review Partial
36 D cast and crew in DetailMetadataView
37 M no awards drill-down
38 D Watch on row with TMDB providers (5 Nov, uncompiled)
39 P related titles (loadRelated)
40-43 P earlier review Partial
44-45 P AnimeEpisodePool and episode projection
46-47 D TVDBEpisodeOrderService, TVDBOrderPanel
48-52 P earlier review Partial (install, validate, configure, uninstall, enable)
53 M no addon sharing
54-55 P earlier review Partial
56 D CommunityAddons with UI test
57 M no addon recommendations
58 D hideContent.adult
59 D CommunityAddonBrowseView
60-61 P earlier review Partial
62 D AddonDetailView
63-67 P earlier review Partial
68-69 P earlier review Partial
70 D addon wait time ported 4 Nov (uncompiled)
71 D progressive results ported 4 Nov (uncompiled)
72 D stream priority ported 4 Nov (uncompiled)
73-74 D StreamRequestPolicy dedup and multi-ID requests
75 P earlier review Partial
76-80 D shared Rust parser
81 D size parsing with thousands separators synced (5 Nov, uncompiled)
82-84 D shared Rust parser
85 P anitomy enrichment of anime names not ported
86 D multi-episode spans synced (5 Nov, uncompiled)
87 D shared Rust parser
88 D trust.rs synced with Desktop 0.9.132 (5 Nov, uncompiled)
89 D fake-group, stub and size checks synced with Desktop (5 Nov, uncompiled)
90 P title gate synced, but the anime alias titles are not passed yet
91 D cinema-window checks synced with Desktop (5 Nov, uncompiled)
92-93 D shared Rust trust
94 D preferred languages reach trust (5 Nov, uncompiled)
95-101 D shared Rust scoring (1-line drift)
102 D preferred languages reach scoring (5 Nov, uncompiled)
103 D streamResults pipeline (uncompiled)
104 M corroborated early-leak rescue (TS side) not ported
105 M anime stream enrichment not ported
106 M streams listed from the debrid library not ported
107-109 P earlier review Partial
110 D DebridStreamResolver (uncompiled)
111 X P2P fallback needs the excluded torrent engine
112-113 D error-clip validation and episode file selection (uncompiled)
114 P earlier review Partial; queueing uncached sources missing
115 P external links open; YouTube/NZB handling incomplete
116-118 D Real-Debrid account, cache, playable link (uncompiled)
119 P library used for verification only
120-122 D AllDebrid (uncompiled)
123 P library used for verification only
124-126 D Premiumize (uncompiled)
127 P library used for verification only
128-130 D TorBox (uncompiled)
131 P library used for verification only
132-134 D Debrid-Link (uncompiled)
135 P library used for verification only
136-148 X local torrent engine and LAN server excluded (background sockets)
149-152 M remote Stremio streaming server not ported
153 X full torrent download needs the excluded engine
154-163 D libmpv playback, seek, speed, volume, tracks, chapters, hwdec
164 P tone mapping options only
165-167 D playback events, audio and subtitle delay
168-169 M no screenshot, no advanced mpv properties
170 X separate player window is desktop windowing
171 D PlayerResumePrompt
172-173 P earlier review Partial
174 P subtitle font choice; no custom subtitle fonts
175 D loudness normalizer and sound profiles through an mpv audio filter chain (5 Nov, uncompiled)
176 X RTX HDR needs an NVIDIA Windows driver
177 P earlier review Partial
178 M no motion interpolation
179-180 P earlier review Partial
181-182 D next episode and auto advance
183 D A-B loop (5 Nov, uncompiled)
184 D sleep timer (5 Nov, uncompiled)
185 D playback stats card read from mpv once a second; iPad hotkey I and a switch in Playback options (5 Nov, uncompiled)
186 P earlier review Partial
187 M no player chrome customization
188 P earlier review Partial
189-190 M no GIF recording or local episode chooser
191 M no Anime4K shaders
192-194 D AniSkip, TheIntroDB, chapter skips in SkipIntroService
195 M no ad corpus skip
196-198 P earlier review Partial
199 P encoding handling in SubtitleFileService
200 D SubtitleAddonService
201 P no Desktop subtitle ranking/dedupe
202 P earlier review Partial
203 P SubtitleAutoSync
204 P OpenSubtitles through addons only
205 M no Wyzie
206-207 P SubtitleAutoSync; embedded tracks via mpv
208 D MPVPictureInPicture
209-210 M no trickplay previews
211 P addon trailers; no YouTube resolution in app
212-213 M no trailer download, quality or cache
214-216 D DownloadManager
217-218 P earlier review Partial
219 P Xtream short EPG; no XMLTV guide
220-223 P earlier review Partial
224 M no region top networks
225 P catch-up fields parsed
226-227 P earlier review Partial
228 M no playlist export
229-230 P earlier review Partial
231-237 M DVR and multiview not ported (feasibility undecided)
238 M no live reconnect policy
239-244 M no Chromecast or DLNA
245 P AirPlay route picker for audio; no video casting flow
246-249 M no Roku or cast transcoding/subtitles
250-259 M Watch Together and relay not ported
260-262 P earlier review Partial
263-264 D library add/remove and progress writes (LibraryWriteQueue)
265 M no library repair
266-267 P earlier review Partial
268 D LibraryHistory
269 P watchlist through trackers and library
270 D ManualWatchedSelection
271-273 M no local video library
274-278 D Trakt login, refresh, profile, history, watchlist
279-281 P Trakt import/export, lists, recommendations partial
282 D TraktPlaybackTracking
283 D My Trakt and Trakt anticipated calendar sources (7 Nov, uncompiled)
284 P Trakt comments of movies and shows: sort, spoilers, replies, paging (5 Nov, uncompiled); posting, likes and ratings not ported
285 D AniList PIN-code login and session (5 Nov, compiled; 14 cases passed)
286 P AniList progress is pushed while watching; the watched map from the lists is not read
287-288 M AniList lists and recommendations not ported
289 P AniList name and avatar in Settings; not used as the Harbor avatar
290 M AniList relations and threads not ported
291 D MyAnimeList login, token refresh and session (5 Nov, compiled; 13 cases passed)
292 P MyAnimeList name shown; no avatar
293 M MyAnimeList lists not ported
294 P MyAnimeList progress is pushed while watching; the watched map is not read
295-298 D Simkl login, history, watchlist, scrobble
299 P Simkl premieres calendar source (7 Nov, uncompiled); no My Simkl source
300-301 P Simkl ratings, anime grouping partial
302-304 M Letterboxd not ported
305 P earlier review Partial
306-308 D TMDBService, MovieCollection, IMDb resolution
309 P TMDB images, trailers and watch providers
310 P OmdbService: scores, 90-day cache, daily budget, refused key; no awards, season ratings or budget panel (7 Nov, compiled; cases passed)
311-312 M no RPDB or Fanart
313 P MdblistService: scores on the detail row; no cards chips (7 Nov, compiled; cases passed)
314 M Wikidata used for music/books only
315 D TVDBService
316 M no TVMaze
317-318 D Kitsu (AnimeService), AniZip mappings
319 P Jikan in AnimeService
320 P earlier review Partial
321 P source switcher with library, all upcoming, My Trakt, Trakt anticipated, Simkl premieres and anime with its Sub/Dub switch (7 Nov, uncompiled); no My Simkl or games; Custom source with its filter sheet (7 Nov, uncompiled)
322 P earlier review Partial
323 D CustomListStore
324-327 D household profiles, switching, per-profile settings, identity sync
328 X Kids/parental excluded by owner
329 P hideContent categories
330-331 X Kids/parental excluded by owner
332-334 P earlier review Partial
335-336 P poster appearance and navigation layout
337-341 M no Theme Studio, code editor, import/export, library, custom background
342 P Desktop's default hotkeys on an iPad keyboard (5 Nov, uncompiled); no remapping
343 P reading fonts only
344-345 M no webhooks or content notifications
346 X Discord Rich Presence needs the Discord desktop client
347-349 M no AI, song identification or Wrapped
350-351 D 16 interface languages, RTL layout
352-354 M no remote control
355 D request headers passed to mpv natively
356 X progressive proxy serves Desktop's web player only
357 M no web receiver/remote interface
358-359 D metadata cache, settings persistence
360-361 P migrations and advanced configuration partial
362 M no startup crash detection
363 P Diagnostics log export
364 P deep links partial
365 D onboarding and replay
366-438 P earlier review Partial
168 X frame grab to a file: iOS has system screenshots, little use on a phone
169 X advanced mpv properties: a free-text power-user field for desktop tuning
178 X motion interpolation: heavy GPU work that drains a phone or tablet for little gain
187 X player chrome and seek bar customization: cosmetic skinning with little use on touch
189 X GIF recording: needs desktop screen capture and has little use on a phone
191 X Anime4K shaders: desktop GPU upscaling, too heavy for mobile battery
212 X trailer download and merge: needs desktop video tooling, trailers stream on iOS
228 X Live TV playlist export: a desktop file-management action with little use on a phone
231 X scheduled DVR: iOS cannot record in the background on a schedule
232 X active recordings: part of the DVR, which iOS cannot run in the background
233 X recording directory: a desktop folder for the DVR
234 X DVR stop and delete: part of the DVR, which iOS cannot run in the background
259 X Cloudflare relay deploy, check and delete: a server administration task, not for a phone
338 X theme code editor: editing code on a phone is impractical
344 X Discord and Telegram webhooks: fired by a desktop app that stays running, iOS cannot
348 X song identification: needs system audio capture that iOS does not allow
354 X remote text entry: types into a TV or desktop interface, not into a phone
357 X web receiver and remote interface: a server a desktop hosts, iOS cannot serve in the background
362 X startup crash detection: iOS reports crashes itself and relaunches cleanly
287 P AniList lists: read-only browse by status with search and type filter, no edits (7 Nov, written by Haiku, CI run 23 green)
288 D AniList recommendations rail from the lists, Desktop ranking and franchise dedupe (7 Nov, written by Haiku, CI run 23 green)
337 P Theme Studio without the code editor: library, import/export and background (7 Nov, written by Haiku, CI run 23 green)
339 D theme import / export as Desktop's JSON (7 Nov, written by Haiku, CI run 23 green)
340 D theme library: save, apply, rename, export, remove (7 Nov, written by Haiku, CI run 23 green)
341 P custom background image with dim; no logo (iOS cannot change the app icon this way) (7 Nov, written by Haiku, CI run 23 green)
349 P watching statistics: hours, titles, split, top titles, highlights, year heatmap from local history; genres and people need Desktop's network enrichment (7 Nov, written by Haiku, CI run 23 green)
302 D Letterboxd (Stremboxd) session: public username or full sign-in, token in the Keychain (7 Nov, written by Haiku, CI run 24 green)
303 D Letterboxd home rails (7 Nov, written by Haiku, CI run 24 green)
304 P Letterboxd catalogs appear as Home rails and in View All; no catalog-browser integration (7 Nov, written by Haiku, CI run 24 green)
26 D search people: People rail, top match and person page with filmography; cast opens it (7 Nov, written by Haiku, CI run 25 pending)
32 D AI search: the Ask AI screen from search with OpenRouter or Groq keys (7 Nov, written by Haiku, CI run 25 pending)
149 D remote streaming server: torrent streams resolve through the configured server, after debrid or first without one; wired in HarborService.resolve and compiled, parsing and policy tested, not exercised against a real server (7 Nov, written by Haiku, CI run 25 pending)
150 D strict remote server policy (7 Nov, written by Haiku, CI run 25 pending)
151 P transcode URL generation is built and tested; the decode-error retry that uses it is not wired (7 Nov, written by Haiku, CI run 25 pending)
152 D streaming server health check and Test connection (7 Nov, written by Haiku, CI run 25 pending)
205 D Wyzie subtitles through the optional provider search; wired in the player's addon-subtitle task and compiled, request and parsing tested, not exercised against Wyzie (7 Nov, written by Haiku, CI run 25 pending)
347 P AI assisted search with own keys; recommendations and the episode mode are not ported (7 Nov, written by Haiku, CI run 25 pending)
37 D awards drill-down: ceremonies with wins and nominations from Wikidata on the detail page, drill-down per ceremony (7 Nov, written by Haiku, CI run 31 green, 80 cases)
271 P local file library: the person picks files or a folder in the Files app and they are kept as bookmarks; no background scan (7 Nov, written by Haiku, CI run 31 green, 80 cases)
272 D local media import through the file picker (7 Nov, written by Haiku, CI run 31 green, 80 cases)
273 D local episode discovery from file names (7 Nov, written by Haiku, CI run 31 green, 80 cases)
314 P Wikidata awards for titles; people awards are not ported (7 Nov, written by Haiku, CI run 31 green, 80 cases)
345 P content notifications as local notifications for upcoming episodes and releases, scheduled while the app is open; Discord and Telegram webhooks stay excluded (7 Nov, written by Haiku, CI run 31 green, 80 cases)
7 D Critics Pick: the daily pick with reviews and scores on Discover; cast chips, stills and genre chips are left out (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
28 D search Live TV channels from the search box (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
53 P addon sharing: the stremio:// link is shared from the addon detail; opening an incoming link is not wired (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
57 D addon recommendations on the addon detail (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
224 D region top networks rows on the Live TV channel list (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
240 P cast control for Roku and DLNA renderers: play, pause, seek where the device supports it, stop, volume; Chromecast is not ported (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
241 D resume locally after a Roku or DLNA cast stops (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
242 P DLNA devices are added by their description address; SSDP multicast needs an entitlement iOS apps do not get freely (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
243 P DLNA vendor handling in the load request (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
244 D DLNA transport controls through AVTransport (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
246 D Roku discovery by Bonjour, a local network probe or a typed address, and playback through its media channel (7 Nov, written by Haiku, CI run 32 green (43 cases), cast run green (36 cases))
247 X cast HLS transcoding: Desktop re-encodes with a local ffmpeg server that a phone does not have
248 X receiver compatible re-encode: needs the same local transcoder
249 X cast subtitle conversion and serving: needs the local cast server
290 D AniList threads and comments on anime detail pages (read-only) and the sequels and prequels strip in Search when the best match is an anime (7 Nov, comments written by Haiku and green; the Search strip is uncompiled)
293 P MyAnimeList lists: read-only browse by status with search and type filter (7 Nov, written by Haiku, CI runs 37 to 39 green)
213 X trailer download, quality and cache: needs yt-dlp and ffmpeg, which a phone does not have
104 P corroborated early-leak rescue: pure rules and tests exist; the Rust ranking does not call them yet (7 Nov, written by Haiku, CI run 42 green, 103 cases)
105 P anime stream enrichment: Desktop's anime parsing as pure functions; the Rust ranking parses before it can use them (7 Nov, written by Haiku, CI run 42 green, 103 cases)
106 P debrid library merge: matching and merge as pure functions; the pipeline does not list the library yet (7 Nov, written by Haiku, CI run 42 green, 103 cases)
265 P library repair preview in Settings; applying the repair needs a write method the library model does not have (7 Nov, written by Haiku, CI run 42 green, 103 cases)
311 D rated posters: RPDB poster URL for cards when a key is saved (7 Nov, written by Haiku, CI run 42 green, 103 cases)
312 P Fanart logos and backdrops: provider and ranking exist, no detail screen calls them yet (7 Nov, written by Haiku, CI run 42 green, 103 cases)
316 D TVMaze schedules: the library calendar asks TVMaze for a series with no dated episode in the month when no TMDB key is saved, as Desktop's last resort (7 Nov, client green; the calendar hook is uncompiled)
235 X multiview: up to four live mpv players at once cost too much CPU, memory and battery on an iPad and make no sense on an iPhone
236 X per tile audio focus: depends on multiview
237 X multiview geometry: depends on multiview
238 D live channels reconnect after a player error with Desktop's delays and attempt limits (7 Nov, written by Haiku, CI runs 43 and 44 green)
239 D Chromecast discovery and playback through CASTv2 with Bonjour; tested with scripted streams, not against a real Chromecast (7 Nov, written by Haiku, CI runs 43 and 44 green)
240 D cast control for Roku, DLNA and Chromecast: play, pause, seek where supported, stop, volume (7 Nov, written by Haiku, CI runs 43 and 44 green)
250 P Watch Together rooms: create and join through the relay with a sheet; the player holds the lobby paused, the host starts the room by pressing play, guests follow and send their controls to the host; no lobby screen with a ready list and no other-title notice (7 Nov, player side uncompiled)
251 D Watch Together invite links, built and parsed (7 Nov, written by Haiku, CI runs 43 and 44 green)
252 D clock aligned playback sync: the host publishes about once a second and at once on pause or seek, guests follow rate, position and play state, the host applies guests' play, pause and seek commands (7 Nov, uncompiled; TogetherPlayerSyncTests)
253 D Watch Together chat (7 Nov, written by Haiku, CI runs 43 and 44 green)
254 X on-screen cursors: a touch screen has no pointer
255 X collaborative drawing: not worth a phone port
256 P host summon and invite: the session stores them, no screen shows them yet (7 Nov, written by Haiku, CI runs 43 and 44 green)
257 P source matching: scoring exists and is tested, no player flow uses it yet (7 Nov, written by Haiku, CI runs 43 and 44 green)
258 P self-hosted relay: the relay address setting works; Desktop's Cloudflare deploy is excluded (7 Nov, written by Haiku, CI runs 43 and 44 green)
31 X search guide: Desktop's guide is the Live TV programme guide opened from the empty search, and iOS loads no programme data (XMLTV), so it would only repeat the channel list in Live TV
190 X local episode chooser: the iOS local library list already shows every season and episode file and plays one on a tap
209 X trickplay seeking previews: Desktop's sprites come from video media servers, which iOS does not have (Plex and Jellyfin are music only)
352 X remote control sessions: Desktop's remote is a mobile web page served by the Desktop app (about twelve thousand lines of its own screens) that drives the Desktop player; the iOS app is itself the phone client and plays on the phone
353 X remote player binding: same reason, it binds that web remote to the Desktop player
210 X shadow mpv thumbnail session: a second decoder opened on the same stream would double the bandwidth and memory of a phone for a debrid or torrent source
312 P Fanart artwork: with a Fanart key, an anime title's logo and backdrops fill what is missing on its detail page (8 Nov, written by Haiku, uncompiled); Desktop's poster, the home hero logos and the movie lookup are not ported
195 D injected ad skip: the signed corpus is fetched and checked (Ed25519), matched on the content and the exact release (info hash or release fingerprint) and offered as a Skip button or skipped by itself; the report button sends the marked times for review (8 Nov, written by Haiku, report screen by Sonnet, uncompiled; iOS has the info hash and size of a stream but the release group and parsed title only when an enrichment added them, so some releases fall back to a key the corpus never holds)
256 P host summon and invite: guests get the invite card (Join or Choose) and the summon card, and the host's invite goes out when its sources open (8 Nov, uncompiled); Desktop's host-side summon actions live in its context menu and have no iOS screen yet
366 P Every failed probe on iOS collapses into manga-network, manga-authorization or manga-protocol, so a missing Suwayomi endpoint (not_found) is not told apart from an unsupported server, and the server name and version from aboutSer...
367 D read row by row (8 Nov): ios/Harbor/Services/SuwayomiClient.swift: sources() loads id, name, language, latest support and adult flag through GraphQL or REST, and removes dupl...
368 D read row by row (8 Nov): ios/Harbor/Services/SuwayomiClient.swift: browse(source:latest:query:page:) requests fetchSourceManga POPULAR, LATEST or SEARCH over GraphQL, or the...
369 P No Suwayomi category support on iOS: gqlCategories, gqlCategoryManga and their REST equivalents are not implemented, so the library cannot be filtered or opened by Suwayomi category and no category tags exist.
370 D read row by row (8 Nov): ios/Harbor/Services/SuwayomiClient.swift: changeExtension(_:action:) runs install, uninstall or update through GraphQL updateExtension or REST /api/v...
371 M No iOS implementation: there is no extensionStores query, addExtensionStore or removeExtensionStore mutation, no fetchExtensions refresh, and no repository UI.
372 P iOS imports one archive as one single-chapter book. Archives inside an imported folder are ignored by importFolder(), which accepts only image files, so a folder of CBZ/ZIP chapters cannot be imported as chapters and fails with m...
373 D read row by row (8 Nov): ios/Harbor/Services/MangaArchive.swift: MangaLocalStore.importFolder() keeps image files with their relative paths, and chapters() groups them by fir...
374 D read row by row (8 Nov): ios/Harbor/Services/MangaArchive.swift: MangaArchive.init sorts image paths with compare(.numeric, .caseInsensitive) so page 2 precedes page 10
375 D read row by row (8 Nov): ios/Harbor/Views/MangaReaderView.swift: reader(size:) renders mode 'long' as a vertical LazyVStack in a ScrollView and mode 'long-h' as a horizontal...
376 D read row by row (8 Nov): ios/Harbor/Views/MangaReaderView.swift: mode 'paged' shows one page per TabView tab; mode 'double' shows fixed pairs (page 2n and 2n+1) with a double...
377 P iOS book mode always shows single leaves. Desktop's aspect-ratio rule that switches to two-page spreads for wide pages has no iOS equivalent; this matters only on wide screens, since Desktop forces single pages on mobile (singleP...
378 P The 'original' fit on iOS uses the image's own pixel size times zoom, while Desktop uses container width times zoom, so original-fit pages can be much larger than the screen on iOS.
379 P The +/-0.1 stepper buttons and the quick preset buttons (50, 100, 150, 200, 300 percent) of the Desktop zoom panel are missing on iOS, which has only the slider, the value label and reset.
380 D read row by row (8 Nov): ios/Harbor/Views/MangaReaderView.swift: @AppStorage manga.reader.rtl (default true) and directionCard options in the direction settings section (line...
381 D read row by row (8 Nov): ios/Harbor/Views/MangaReaderView.swift: canvas and ink computed from @AppStorage manga.reader.background with dark #0B0B0D, gray 0.15 and light 0.96...
382 D read row by row (8 Nov): ios/Harbor/Views/MangaReaderView.swift: @AppStorage manga.reader.navPos with Picker for stack-br, stack-bl, bottom and sides (lines 35, 172)
383 P The iOS slider stops at 40, so gaps of 42 to 48 px available on Desktop cannot be chosen on iOS.
384 P iOS focus mode hides the page counter, slider, arrows and any progress indicator with no temporary reveal; the Desktop thin ReaderProgressMeter stays visible in focus, and the only way back on iOS is the eye button, which turns t...
385 P With auto-next off, iOS shows no end-of-chapter card or Next chapter button in paged or strip modes; turn() only sets the hint, so the user must use the chapter list. The iOS long strip also auto-advances, which the Desktop long...
386 P The iOS hint is a plain caption with no next-chapter button, no next-chapter name and no dismiss control; it can only be hidden through the settings toggle.
387 D read row by row (8 Nov): ios/Harbor/Views/MangaReaderView.swift: @AppStorage manga.reader.enablePageDownload and the save-and-share pages toggle (lines 39, 178)
388 D read row by row (8 Nov): ios/Harbor/Views/MangaReaderView.swift: @AppStorage manga.reader.flipSound default true and page-turn sound toggle in book mode (lines 40, 174)
389 P iOS has no GraphQL-to-REST fallback at send time (the protocol is fixed per chapter at load), and leaving the active scene does not send the Suwayomi update (sync false), so the last page only reaches the server when the app beco...
390 X Desktop defines the per-source filters call (rest.ts restFilters) and nothing in Desktop calls it, so there is no behavior to port
391 P iOS shows English titles only (no Arabic or Russian labels), and the NCAA soccer leagues read 'NCAA Men's/Women's Football' where Desktop getLeagueLabel shows 'NCAA Men's/Women's Soccer'.
392 P The iOS date picker has no live-day markers, so users cannot see which dates contain live games before choosing them.
393 P The iOS state filter covers only the selected day and the leagues the user selected, and iOS sorts finished games oldest first where Desktop sorts them newest first.
394 P iOS refreshes only the selected day's scoreboards, so games that continue past midnight are not covered, and returning to the foreground does not refresh at once because the loop sleeps first.
395 P iOS has no sport-specific period labels (overtime, innings, sets) and no cricket partnership or player tables, baseball or football situation panels, or volleyball set data.
396 P iOS does not read keyEvents or football events, so no typed timeline with clock and participant is shown; it displays unstructured commentary text instead.
397 P iOS has no league-team browser, no home team per group, and no following or team schedule view; only teams that appear in loaded events or standings can be starred.
398 P The iOS notice has no warning against paywall or DRM bypass and no statement that league names and logos do not imply endorsement (usage-notice.ts SPORTS_USAGE_SECTIONS and SPORTS_USAGE_DETAILS).
399 P iOS lead options differ (0, 5, 10, 15, 30 minutes, default 10) and stored reminders are never re-synced when the start time moves. Local notifications replacing Discord and Telegram are a platform adaptation, not counted as a gap.
400 P iOS has no standings panel inside the match detail and does not highlight the two teams' rows there; standings are reachable only from the league menu.
401 P iOS has no per-event attached sources, no matching of playlist channels to the game, and no page-URL stream resolver; it only starts a Live TV search for the first broadcast name.
402 D read row by row (8 Nov): ios/Harbor/Models/PageCustomization.swift: PageLayout.order, PageCustomization.ordered() and move(_:toward:)
403 D read row by row (8 Nov): ios/Harbor/Models/PageCustomization.swift: PageLayout.hidden and ordered(includeHidden:)
404 D read row by row (8 Nov): ios/Harbor/Models/PageCustomization.swift: PageLayout.renamed, title(_:among:) and rename(_:to:) with a 120 character limit
405 P iOS also gives Top 10 styling by default to -top10 and cm-top-movies, cm-drama and cm-comedy rails, renders ranked rails without the 10-title check (PageCustomizationView line 95), and has no first-row Top 10 block with its own h...
406 P iOS takes the first five titles of the chosen row without the backdrop-first ordering, the four-slide cap, or the artwork check at render time.
407 D read row by row (8 Nov): ios/Harbor/Models/PageCustomization.swift: PageLayout.playButtonSquare
408 D read row by row (8 Nov): ios/Harbor/Models/PageCustomization.swift: PageLayout.secondaryMoreInfo
409 D read row by row (8 Nov): ios/Harbor/Models/PageCustomization.swift: PageLayout.cwTop
410 D read row by row (8 Nov): ios/Harbor/Models/VOD.swift: VODTitles.kind follows Desktop classifyChannel order (declared tvg-type, /series/ /movie/ /live/ paths, VOD and live ext...
411 P iOS sets the series logo only from the first episode, so a show whose first episode has no logo never gets one from later episodes, while Desktop fills it (vod.ts line 113).
412 D read row by row (8 Nov): ios/Harbor/Models/VOD.swift: VODTitles.clean, tags, isTag, show, number, year and normalized mirror vod-title.ts (region tag stripping, bracket and n...
413 P Only the per-channel schedule sheet calls programs(); no iOS path hydrates short EPG into the live guide or now and next data as use-xtream-epg-fallback.ts does, and a failed request throws where Desktop returns an empty list.
414 P Container negotiation matches, but when server_protocol is https and neither https_port nor port is given, iOS keeps the typed base (which may be http) while Desktop forces https://host.
415 D read row by row (8 Nov): ios/Harbor/Services/VODMetadataService.swift: enrich searches TMDB by original title, kind and year, takes the first result, applies poster, overview...
416 D read row by row (8 Nov): ios/Harbor/Models/VOD.swift: VODTitles.searchKey applies NFKC, removes invisible marks and harakat, folds alef, ta marbuta, alef maksura and hamza fo...
417 D read row by row (8 Nov): ios/Harbor/Views/VODView.swift: VODEpisodeRow reads the owner resume entry, draws a progress bar, shows minutes left below 90 percent, a watched chec...
418 D read row by row (8 Nov): ios/Harbor/Models/Spooktober.swift: SpooktoberSeason.available (October in any year, or 28 September onward in 2026 only) and SpooktoberSeason.nextCh...
419 D read row by row (8 Nov): ios/Harbor/Views/SpooktoberView.swift: SpooktoberInvitation shows the full card, or a collapsed pumpkin chip after dismissal that still opens the fes...
420 D read row by row (8 Nov): ios/Harbor/SpooktoberContent.json: 71 entries identical to public/spooktober/content.json in order and every field (43 Film, 10 Series, 12 Book, 6 Ma...
421 D read row by row (8 Nov): ios/Harbor/Views/SpooktoberView.swift: SpooktoberView.shelf opens DetailView for items with a Media value and SpooktoberSourceView for the rest
422 D read row by row (8 Nov): ios/Harbor/Services/MusicFileService.swift: importFile copies the picked file into a SHA256-named private file, probes tags with libmpv (MusicProbe.i...
423 D read row by row (8 Nov): harbor-core/src/music.rs: local_track computes album_key from credited artist plus album and artist_key from the credited (album-artist-preferred) ar...
424 P The sidecar image fallback (cover, folder or front, jpg/jpeg/png) does not exist on iOS, and folder import copies only audio files so sidecar images are never read. Embedded art is taken as the first picture rather than preferrin...
425 D read row by row (8 Nov): ios/Harbor/Player/MusicAudioEngine.swift: MusicAudioEngine actor wraps libmpv; open(stream) loads a local file or URL with headers, command() handles...
426 P No queue continuation: when the queue ends iOS stops, while Desktop's music-queue-continuation.tsx loads more tracks from the origin (playlist, catalog, Spotify page or similar/discover). Also, enqueue(next:) inserts directly aft...
427 D read row by row (8 Nov): ios/Harbor/Player/MusicPlayback.swift: remoteControls() registers MPRemoteCommandCenter play, pause, toggle play/pause, next, previous and changePlay...
428 D read row by row (8 Nov): ios/Harbor/Player/MPVController.swift: initialize() calls MusicPlayback.shared.pauseForVideo() before the video session opens
429 D read row by row (8 Nov): harbor-core/src/music.rs: playlist_name trims the name and enforces 1 to 100 characters, as Desktop library.rs does
430 D read row by row (8 Nov): ios/Harbor/Models/MusicPlaylists.swift: MusicPlaylistStore.add(_:to:) skips tracks already in the playlist and records trackAddedAt; remove(_:from:)...
431 D read row by row (8 Nov): harbor-core/src/music.rs: playlist_order applies the same remove-then-insert index arithmetic with clamping as Desktop library.rs reordered()
432 D read row by row (8 Nov): ios/Harbor/Models/MusicPlaylists.swift: MusicPlaylistStore.delete(_:) removes only the playlist entry and never calls MusicLibrary.remove or MusicFil...
433 P iOS does a one-time copy import and keeps no folder source: there is no rescan, no skipping of unchanged files by size and modification time, and no pruning of tracks whose files were removed. It also skips hidden files, which De...
434 D read row by row (8 Nov): ios/Harbor/Services/MusicCollectionTools.swift: MusicCollectionTools runs the pinned src/lib/music/playlist-filters.ts program in JavaScriptCore for...
435 D read row by row (8 Nov): ios/Harbor/Services/MusicCollectionTools.swift: the pinned playlist-filters program applies the six sorts, descending order and unknown-value-last ru...
436 D read row by row (8 Nov): ios/Harbor/Views/MusicCollectionViews.swift: MusicCollectionToolsView offers List and Compact in the options menu, stored in AppStorage harbor.music....
437 P Copy title exists only in MusicTrackActions for local library records. The connector and catalog track menu (MusicRecordingActions, used by catalog cards, catalog detail and playlist rows when a session is active) has no copy act...
438 P iOS does not disable the FPS control while auto-sync is running (SubtitleTiming.unavailable has no auto-sync check); applySubtitleFPS instead cancels the running sync through cancelSubtitleSync().
1 P iOS never fetches Desktop's hosted hero pool: the trending feed falls back to the first catalog titles, and the trakt and simkl feeds only pick an already-loaded rail whose name contains that service. The Desktop 4...
2 P iOS shows no empty-state message or sign-in prompt when the row is empty (ContinueWatching returns nothing). It also lacks Desktop's duplicate-by-name and franchise-root removal and the 100-item cap, and it orders...
3 P Top 10 numerals are not gated by the 10-title minimum at render time: PageCustomization.ranked and TopTenRail do not check the title count, while Desktop renders a row as Top 10 only when it has at least 10 titles.
10 P The iOS movie room has no user collection rows assigned to the page, no Top 10 Movies Today row (no movie top-10 rail was found in ContentPageModel or TMDBService), no cross-row de-duplication against the hero and...
11 P CinemaHero on iOS has no auto-advance (no timer or rotate task), and the movie hero is the first titles of the catalog with no daily rotation and no exclusion of recently played titles.
13 P iOS movie rows never request a second page inline; CatalogRails has no load-more trigger and ContentPageModel fetches page 1 only. Pagination exists only in the View all grid, and only for addon catalogs whose mani...
17 P iOS series rows never load a second page inline (same gap as movie catalog pagination), the hero is the first titles of the catalog rather than Desktop's curated 6-title pool, and hero titles are not removed from t...
22 P iOS has no TMDB search/multi aggregation, no top-match ranking, no fuzzy people fallback, and no year or genre intent results; it only merges addon catalog search rows.
23 P iOS has no TMDB search source for movies, no poster filter, no 12-title cap and no top-match ranking; movie rows are whatever the addon catalogs return for the query.
24 P iOS has no TMDB search source for series, no poster filter, no 12-title cap and no top-match ranking; series rows are whatever the addon catalogs return for the query.
33 P iOS has no shared crew line (other films by the same crew), no user-reorderable detail section layout (Desktop DetailLayoutEditor), and no per-title reminder button on the title page; EpisodeAlertsSettingsView is o...
34 P The title page logo for movies and series comes only from the metadata or the saved artwork choice. DetailView never calls CardArtworkResolver (only card and profile poster views do), and FanartClient.movie is neve...
35 P iOS genre badges are not clickable and every genre is shown, while Desktop shows the first three genres as pills that open a genre filter (openFilter) when clicked.
40 P iOS picks the default season from the history episode hint or the first real season, with no watched-progress choice of the next unfinished season (resumeDefaultSeason). No mark-season action was found in the episo...
41 P iOS rows never show runtime, the percent-watched or watched-ago text, the progress bar, or New badges, and there is no dedicated episode detail view (Desktop openEpisodeDetail); the list and card builders in Episod...
42 P The initial season ignores Desktop's resumeDefaultSeason logic (EpisodeList.chooseInitialSeason uses only the preferred episode or the first season), and no cross-season episode search or random-episode control is...
43 P Simkl watched episodes are parsed into SimklLibraryItem.watchedEpisodes (ios/Harbor/Models/SimklLibrary.swift) but no episode watched function reads them, so they never reach LibraryModel.watchedEpisodes; the seaso...
48 P AppModel.install dedupes only by transport URL and appends the addon at the end, so the same manifest id at a new URL is duplicated and loses its position (Desktop dedupes by id and keeps the order on replace); the...
49 D read row by row (8 Nov): ios/Harbor/Services/HarborService.swift: HarborService.install fetches the normalized URL with http.json before installing
50 P The replacement is saved only to the local profile through AppModel.persist, which throws profile-account-migration when a Stremio account is signed in; Desktop also pushes the replacement to the Stremio account (p...
51 P Removal is local only: no iOS code makes the Stremio account write (Desktop uninstallAddon calls setUserAddons), and AppModel.persist throws profile-account-migration for a signed-in Stremio account, so removal fai...
52 P AppModel.setEnabled saves through AppModel.persist, which throws profile-account-migration when the active configuration carries a signed-in Stremio account (HouseholdSourceAccount.account), so the toggle cannot be...
54 P Local persistence of the configured manifest URL exists through HouseholdSessionVault.save, but the Stremio account write does not: no iOS code makes the addonCollectionSet call, and AppModel.persist throws profile...
55 P The order is saved only locally and only for guest profiles (AppModel.move goes through persist, which throws for a signed-in Stremio account); there is no stale check, no account write or verification, and no back...
60 P Local list management is present, but for signed-in Stremio profiles every install, remove, reorder and toggle write goes through AppModel.persist and fails, and no iOS code writes uninstall or reorder changes to t...
61 P A captured link is not installed automatically: iOS puts it in the native field and waits for the user to tap Save, and there is no timed fallback to the browser, only the manual Abrir en Safari button and the load...
63 P iOS applies none of Desktop's addon_catalog type filter, episode-meta collapse or normalized-name row dedupe (addons.ts NON_CONTENT_TYPES, collapseEpisodeMetas and dedupeAddonRows); HarborService.catalogs only drop...
64 P Genre and skip paging are wired into CatalogBrowserView, but the required-extra default is missing: catalog_plans drops every catalog with an unmet required extra and HarborService.catalogs passes no genre during d...
65 P Desktop also reads the older manifest form (extraSupported) to decide whether a catalog supports search, but the Rust Catalog type has no such field, so addons that declare search only through extraSupported are ne...
66 P Rust deserializes a missing types or idPrefixes list in a specific resource entry as empty, so an entry without its own types never matches and an entry without its own idPrefixes accepts every id, whereas Desktop...
67 M No iOS flow calls the account bridge (accountRequest) or AccountCollection.merging, and there is no Stremio sign-in, startup pull or cloud push; the protocol builders and merge rules exist but are unused, and exist... Stremio sign-in was replaced by local profile sources in commit 986184c8.
68 P The alternate-type retry and the declared-type lookup for non-standard ids (pickIdByDeclaredTypes) apply only to the origin addon in iOS; other addons are queried only for their resource-declared types, and I found...
69 D read row by row (8 Nov): ios/Harbor/Services/HarborService.swift: streamResults (launches every stream request in a task group and streams partial rankings at most every 250...
75 P StreamRequestPolicy.deduplicated drops later duplicates without uniting their sources, no iOS path passes tracker sources to a torrent or streaming-server request, and no iOS code recovers a missing infoHash from t...
107 P The iOS direct-URL path has no HEAD web-page probe, no error-clip size check on direct links (the check runs only on debrid links), and no completed-download precedence in resolve.
108 D read row by row (8 Nov): harbor-ios-bridge/src/dispatch.rs: resolve_direct (reads behaviorHints proxyHeaders request or headers and rejects invalid names and CR, LF or NUL in...
109 P The Stremio streaming-server path returns a PlaybackSource with subtitles nil, so addon subtitles are dropped on that path, while the direct path keeps them.
114 P iOS has no P2P engine fallback or P2P download preference (torrent handling is limited to the Stremio streaming server), and it has no automatic or season download flow that commits uncached picks.
172 P There are no saved subtitle look presets (Desktop's loadSubPresets, saveSubPresets and snapshotSub) and no custom subtitle font import; the font choice is limited to five fixed families.
173 P The second-line size (subSecondaryScale) is saved and shown by SecondLineSizeControl but no mpv property reads it, and the secondary text captured in state.secondarySubtitleText has no view that draws it, so the se...
177 P iOS has no automatic single reload of a VOD stream that ends prematurely (Desktop's isTruncatedEnd and use-auto-retry), its natural-end decision uses only mpv's EOF reason rather than the 85 percent rule, and the e...
179 P iOS offers mute but no volume control, and has no shader (Anime4k) menu, screenshot, draw toggle, in-player download or DVR control; the RTX HDR and RTX VSR toggles are NVIDIA-only and impossible on a phone, while...
180 P The iOS picker opened from the player's Change source action has only quality and provider filters plus the Both/Direct-debrid mode toggle; cached-only, preferred-language, source-group and flagged/rejected toggles...
186 P HarborSeekBar takes only position and duration: it draws no buffered or downloaded fill (cacheEnd is never passed to it), no skip or ad segment spans, no trickplay thumbnails, and dot size and fill are fixed (only...
188 P iOS has the season/order browser, the next-up row and adjacent-episode logic, but choosing an episode always autoplays the best stream: the instant-play off mode that shows a per-episode stream picker, the queue-dr...
196 P iOS imports SRT as raw bytes (8 MB cap, Files security-scoped copy) and passes it to mpv without any encoding detection; sub-codepage is never set and no legacy or Arabic encoding handling exists on the iOS side, s...
197 P ASS/SSA track detection and the ASS size normalisation are wired (isASSTrack, SubtitleSelectionWiring), and .ass/.ssa files are accepted by the Files import. The same missing Desktop encoding detection applies to A...
198 P iOS downloads VTT addon subtitles (sniffing the WEBVTT header and rejecting HTML responses) and imports .vtt files through mpv, but has no encoding detection on the Desktop model, so non-UTF-8 WebVTT files are not...
202 P The flag-driven filters, tags and auto-selection exclusions are implemented, but the hide-SDH setting is sent to mpv as sub-filter-sdh unconditionally: the Desktop gate (sdhFilterAllowed: not forced, not foreignOnl...
217 P iOS imports M3U by URL or file with EXTINF, group, VLC/Kodi/pipe options and DRM detection, but it has no decorative-row filter (only a check that the name has alphanumerics) and no EPG derivation from get.php; XML...
218 D read row by row (8 Nov): ios/Harbor/Models/Xtream.swift: XtreamAccount
220 P iOS loads M3U and Xtream live catalogs from all sources with a six-hour cache and shows them in source order; the group-relevance ordering, pinned channel order, most-watched ordering and per-group hide, pin and re...
221 P iOS offers a category picker of groups sorted alphabetically (localizedStandardCompare) with no relevance ordering, no group pin, hide or reorder, and no counts. Category filtering itself works.
222 P iOS keeps favorites only as channel ids in LiveTVPreferences and filters the currently loaded channels, so a favorite whose playlist is not loaded disappears; there is no snapshot-based Favorites group or favorites...
223 P The Live TV screen search in LiveTVView uses plain localizedCaseInsensitiveContains without Arabic normalisation; the Arabic-aware LiveTVSearch.channels rule is only called from the global search section, where it...
226 D read row by row (8 Nov): ios/Harbor/Services/XtreamClient.swift: XtreamClient
227 D read row by row (8 Nov): ios/Harbor/Services/XtreamClient.swift: XtreamClient.vod (lists Xtream series rows by series_id, decodes base64 names, keeps the series type filter)
229 P The EPG snapshot kind from epg-store.ts (IndexedDB 'epg' entries) has no iOS counterpart: XMLTV is not implemented, and Xtream short EPG (XtreamClient.programs) is refetched every time with refresh set to true.
230 D read row by row (8 Nov): ios/Harbor/Services/M3UParser.swift: M3UParser.option (maps EXTVLCOPT, KODIPROP and pipe options to vlcopt-user-agent, vlcopt-referrer and vlcopt-coo...
260 P The Rust account rules exist, but no Swift code calls AccountPlan, no iOS screen offers Stremio sign-in or sign-out (AccountView has no Stremio flow), and nothing constructs an AccountSession, so the login and logo... Stremio sign-in was replaced by local profile sources in commit 986184c8.
261 P No iOS code calls getUser and no screen shows a Stremio profile; AccountUser.displayName has no caller. Stremio sign-in was replaced by local profile sources in commit 986184c8.
262 P The read, write and remove code is in place, but nothing on iOS creates an AccountSession (no login flow), so a user cannot activate the cloud library; only legacy stored sessions reach LibraryModel.setSession. Stremio sign-in was replaced by local profile sources in commit 986184c8.
266 P Desktop always drops anime cloud-id items (ANIME_CLOUD_ID) from the cloud list and folds resume timestamps into the sort key; iOS keeps cloud anime items whenever the local source is not visible (LibraryModel.allCo...
267 P There is no series-level last-played lookup equivalent to lastPlayedEpisode; iOS resume is per target only, and grep finds no iOS code that returns the most recent season and episode of a series.
305 D read row by row (8 Nov): ios/Harbor/Services/HarborService.swift: HarborService.addonMetadata (falls back to the Cinemeta meta endpoint for tt ids)
320 D read row by row (8 Nov): ios/Harbor/Views/CalendarView.swift: CalendarView.monthGrid (month grid with movie, TV and anime type filter and source pills)
322 P iOS takes only bookmarked or continuing records (CalendarModel.load), does not add the Trakt watchlist even when Trakt is connected, takes dates from addon metadata instead of TMDB upcoming resolution, and has no 8...
332 P iOS hard-codes Fraunces for every display heading (HarborTheme.displayFont) instead of the Desktop default display face (Sentient in sentient-switzer), and the Desktop layout, card and button styling of the identit...
333 P iOS has the eight base palettes, custom colors and saved themes with backgrounds, but no layout, card-style, button-style, CSS or navigation chrome choices, and no beta, featured or template theme catalogue.
334 P iOS offers only three body choices (Switzer, Inter, System) and a fixed Fraunces display face; the Sentient, Fraunces + Inter, General Sans, Cabinet Grotesk, IBM Plex and Plus Jakarta pairs are not offered and the...
366 D Suwayomi connection check tells wrong credentials, no server, unsupported and unreachable apart and shows the server name and version (8 Nov, written by Haiku, uncompiled)
372 D local CBZ/ZIP: a folder of archives imports one chapter per archive (8 Nov, written by Haiku, uncompiled)
378 D manga original fit uses container width times zoom as Desktop (8 Nov, written by Haiku, uncompiled)
379 D manga zoom panel has the 0.1 steppers and the 50 to 300 percent presets (8 Nov, written by Haiku, uncompiled)
383 D manga double-page gap goes up to 48 (8 Nov, written by Haiku, uncompiled)
384 D manga focus mode keeps a thin progress meter (8 Nov, written by Haiku, uncompiled)
385 D manga automatic next chapter off: a chapter-complete card with a Next chapter button ends paged, double and strip modes (8 Nov, written by Haiku, uncompiled)
386 D manga chapter-end hint shows the next chapter name, a Next chapter button and a dismiss control (8 Nov, written by Haiku, uncompiled)
389 D manga chapter progress is sent when the app leaves the foreground and a rejected GraphQL update falls back to REST (8 Nov, written by Haiku, uncompiled; the REST fallback is untested against a real server)
391 D sports league catalog: the NCAA soccer leagues are labelled from the catalog as Desktop's getLeagueLabel does; Desktop's English catalog says Football for them, so English reads as before and other languages get their own word for soccer (8 Nov, written by Haiku, test fixed by Sonnet)
392 P sports calendar: the native date picker cannot mark live days and iOS does not fetch live state for other days
393 D sports filtering: finished games sort newest first and the live scope covers yesterday and today (8 Nov, written by Haiku, uncompiled)
394 D sports live refresh: refreshes at once on returning to the foreground and keeps games that run past midnight (8 Nov, written by Haiku, uncompiled; local calendar days where Desktop uses UTC)
396 P sports event commentary: a typed timeline from key events with clock and participant; American football drive plays still fall back to commentary text (8 Nov, written by Haiku, uncompiled)
398 D sports external-service consent: the notice carries Desktop's permission and endorsement sections and the consent version moved to 2 (8 Nov, written by Haiku, uncompiled)
399 D sports reminders: Desktop's lead options (5, 15, 60, 1440 minutes, default 15) and reminders re-sync when a start time moves, when the list reloads (8 Nov, written by Haiku, uncompiled)
400 D sports standings: the match detail shows the standings group with both teams highlighted (8 Nov, written by Haiku, uncompiled)
411 D VOD M3U episode grouping: the series logo is filled from any episode (8 Nov, written by Haiku, uncompiled)
414 D Xtream live container selection: https stays https with Desktop's port rule (8 Nov, written by Haiku, uncompiled)
217 P M3U import: the decorative-row filter is in; the EPG address derived from a get.php link is tested but nothing uses it because iOS has no XMLTV guide (8 Nov, written by Haiku, uncompiled)
221 P channel categories: the category picker orders groups by relevance to the person's region and language; channel relevance order, group pins and hidden groups are not ported (8 Nov, written by Haiku, uncompiled)
223 D live text search: uses the Arabic-aware matching as Desktop (8 Nov, written by Haiku, uncompiled)
186 D custom seek bar: draws the buffered fill from the demuxer cache end (8 Nov, written by Haiku, uncompiled); Desktop's fully-cached rule is not ported
196 D external SRT: legacy encodings are detected and converted to UTF-8 before mpv gets the file, UTF-8 stays byte-identical (8 Nov, written by Haiku, uncompiled; Desktop's Arabic plausibility tie-break is not ported)
197 D external ASS/SSA: same encoding detection and conversion (8 Nov, written by Haiku, uncompiled)
198 D external WebVTT: same encoding detection and conversion (8 Nov, written by Haiku, uncompiled)
202 D SDH and forced flags: the hide-SDH filter now follows Desktop's gate (not forced, not foreign-only, safe language) (8 Nov, written by Haiku, uncompiled; iOS tracks carry no foreign-only flag)
109 D embedded addon subtitle URLs: the Stremio streaming-server path passes them on (8 Nov, written by Haiku, uncompiled)
177 D player resilience: a network stream that ends before 85 percent of a known duration reloads once, never local or downloaded files (8 Nov, written by Haiku, uncompiled; restarts from the beginning and has no second retry per candidate)
3 D Home row customization: Top 10 numerals need the ten-title minimum at render time (8 Nov, written by Haiku, uncompiled)
405 D Home Top 10 numerals: the defaults follow Desktop (Home rows are not Top 10 by default, Movies and Series keep their rank row, anime rank rows need ten titles) (8 Nov, written by Haiku, uncompiled); Desktop's separate first-row Top 10 block is not ported
406 D Home hero source: backdrop first, no duplicates, at most four slides, Featured as the fallback (8 Nov, written by Haiku, uncompiled); anime and series keep their own counts
35 P synopsis, genres and ratings: only the first three genres show and a TMDB genre opens a filtered browse; unmapped genre names stay plain text (8 Nov, written by Haiku, uncompiled)
40 D seasons: the default season follows Desktop's resume rule (history hint, latest watched season, next unfinished) (8 Nov, written by Haiku, uncompiled)
42 P episode selection: the initial season follows Desktop's resume rule; mark-season, cross-season search and the random-episode button are not ported (8 Nov, written by Haiku, uncompiled)
424 P music audio cover import: a sidecar cover (cover, folder, front) fills in when there is no embedded art, for folder imports; the front-cover tag preference is not possible with AVFoundation's artwork key (8 Nov, written by Haiku, uncompiled)
437 D music track title copying: Copy title and artist in the catalog, playlist and collection track menus (8 Nov, written by Haiku, uncompiled)
438 D subtitle source FPS correction: the control is blocked with Desktop's message while auto-sync analyses or applies (8 Nov, written by Haiku, uncompiled)
2 P Continue Watching on Home: the empty-state box and the one-card-per-title pass with the 100-card cap are in (8 Nov, written by Haiku, uncompiled); franchise-root removal is not, and Desktop's signed-out Stremio prompt is replaced by the empty message because iOS has no Stremio sign-in
11 P cinema hero: auto-advance every 11 seconds and the daily pick of titles with artwork for the movie hero (8 Nov, written by Haiku, uncompiled); no pause on drag, no exclusion of recently played titles, and the pool is the iOS rails rather than Desktop's TMDB pool
13 D movie catalog pagination: reaching the last title of a row asks for the next catalog page, with Desktop's 14-title first-page rule, 30-title cap and duplicate skipping; native fallback rows never page (8 Nov, written by Haiku, uncompiled)
17 P series catalogs: inline paging is in, shared with the movie rows (8 Nov, written by Haiku, uncompiled); the curated 6-title hero pool and the removal of hero titles from the rows are not
34 P poster, backdrop and logo: the title page logo now resolves through CardArtworkResolver after the saved choice and the season artwork (8 Nov, written by Haiku, uncompiled); the resolver only accepts TMDB and anime ids, so IMDb titles keep the metadata logo
41 P episode details: rows show the runtime and a New badge for episodes aired in the last three days (8 Nov, written by Haiku, uncompiled); still no percent-watched or watched-ago text, no progress bar and no dedicated episode detail view
42 P episode selection: the initial season follows Desktop's resume rule, and a random-episode button and a mark-season item in the sort menu are in for plain seasons (8 Nov, written by Haiku, uncompiled); cross-season search is not ported and mark-season writes to Trakt only, not Simkl
43 D episode watched state: Simkl watched episodes join the watched set before the manual decisions, read from the in-memory list that fills when the Simkl library refreshes (8 Nov, written by Haiku, uncompiled)
48 P install addon URL: an install now replaces the addon with the same manifest id or URL, keeps its place in the list and keeps the disabled state by URL (8 Nov, written by Haiku, uncompiled); the Stremio account write is still absent (see rows 50 to 52)
61 P addon configuration viewport: a captured link now installs at once as on Desktop (8 Nov, written by Haiku, uncompiled); there is still no timed fallback to the browser
63 P addon catalog discovery: the addon_catalog type filter and the episode-meta collapse are in (8 Nov, written by Haiku, uncompiled); the normalized-name row dedupe is not
220 P live channel catalogs: channels follow Desktop's group relevance order with pinned channels first and hidden categories removed (8 Nov, written by Haiku, uncompiled); most-watched ordering is not ported because iOS keeps no play counts
221 P channel categories: relevance order, per-list pins and hidden categories with a management sheet (8 Nov, written by Haiku, uncompiled); no drag reorder and no counts
222 D live favorites: each favorite keeps a snapshot of its channel, so it shows when its playlist is not loaded, and the Favorites view ignores the list and category pickers as Desktop does (8 Nov, written by Haiku, uncompiled)
266 P Continue Watching merge: the sort key now takes the newer of the activity and the local resume time (8 Nov, written by Haiku, uncompiled); cloud anime items are dropped only while their local copy is shown, because iOS imports them into the local library and Desktop's unconditional drop would hide them otherwise
267 P The plain series episode picker uses the local last-played season after a valid explicit hint and before watched history. A manual season choice stays selected. Playback entry-point and alias parity remain open.
395 P sports score periods: the headings follow Desktop (Set, Period, Quarter, Overtime, Innings) (8 Nov, written by Haiku, uncompiled); cricket partnership and player tables, baseball and football situation panels and volleyball set data are not ported
413 P Xtream short EPG: the fallback rule (120 channels, existing guides skipped, one failure leaves that channel empty) exists as a helper (8 Nov, written by Haiku, uncompiled); the live list shows no now and next, so nothing calls it
260 X Stremio login / logout: the owner removed the Stremio sign-in from the iOS app before this port began (confirmed 8 Nov); profiles use local sources (commit 986184c8)
261 X Stremio user profile: needs the Stremio sign-in the owner removed (confirmed 8 Nov)
262 X Cloud library: it can only be activated by a Stremio sign-in, which the owner removed (confirmed 8 Nov)
265 X Stremio library repair: it repairs the Stremio cloud library, which needs the sign-in the owner removed (confirmed 8 Nov)
67 X Stremio addon collection sync: it syncs the addon collection with a Stremio account, and the owner removed the sign-in (confirmed 8 Nov)
50 D configure addon URL: the replacement is saved to the local profile; Desktop's extra push to a Stremio account does not apply because the owner removed the sign-in (confirmed 8 Nov)
51 D uninstall addon: removal is saved to the local profile; the Stremio account write does not apply because the owner removed the sign-in (confirmed 8 Nov)
52 D enable and disable addon: the toggle is saved to the local profile; the Stremio account case does not apply because the owner removed the sign-in (confirmed 8 Nov)
54 D configured addon credentials persistence: the configured manifest URL is kept locally through the household vault; the Stremio account write does not apply because the owner removed the sign-in (confirmed 8 Nov)
60 D installed addons management: install, remove, reorder and toggle work on the local list; the signed-in Stremio case does not apply because the owner removed the sign-in (confirmed 8 Nov)
22 P global search: Desktop's poster filter and 12-title cap apply to the merged movie and series rows (8 Nov, written by Haiku, uncompiled); no TMDB search source, no top-match ranking and no year or genre intent
23 P movie search: the poster filter and the 12-title cap are in (8 Nov, written by Haiku, uncompiled); iOS still has no TMDB search source for movies and no top-match ranking
24 P series search: the poster filter and the 12-title cap are in (8 Nov, written by Haiku, uncompiled); iOS still has no TMDB search source for series and no top-match ranking
12 D movie mood and decade rails: Desktop's mood rails (24 moods, 8 seasonal, time-of-day buckets, daily seed) join the decade rails on the movie page (8 Nov, written by Haiku, uncompiled)
16 P network and premiere rails: the network list now matches Desktop (AMC and FX added); the premiere rail's parameters were not compared (8 Nov, written by Haiku, uncompiled)
322 P library release calendar: every library title that is not removed, plus the Trakt watchlist when Trakt is connected, with Desktop's curated order, the 80 shows and 80 movies limits, no season 0 episode 0 and a dedupe (8 Nov, written by Haiku, uncompiled); dates still come from the addon metadata, not Desktop's Cinemeta and TMDB resolution
369 P Manga Suwayomi library: the client can list categories and their books over GraphQL and REST (8 Nov, written by Haiku, uncompiled); the library has no category filter yet
377 P manga book page turns: Desktop's two-page spread rule exists as a tested helper (8 Nov, written by Haiku, uncompiled); the book pager still shows single leaves
426 P music playback queue: the expanded player can request and append fresh tracks from the queue context without interrupting playback; Discover currently uses the profile catalog rather than Desktop radio, and Spotify paging and artist blocks remain pending
433 P music local folder scanning: the unchanged-file and removed-file rules exist as tested helpers (8 Nov, written by Haiku, uncompiled); imports are still a one-time copy with no rescan
397 P sports favorite leagues and teams: a home team per league group can be set from the match detail and is kept in the Keychain, and the form, last result and next fixture rules exist (8 Nov, written by Haiku, uncompiled); no team browser, no followed-team schedule view
217 D M3U import: the decorative-row filter is in and the guide address derived from a get.php or player_api link now feeds the XMLTV guide (8 Nov, written by Haiku, uncompiled); a header url-tvg and a configured guide address are not read because iOS keeps neither
219 P XMLTV EPG: Desktop's parser, now and next lookup, tvg-shift and shared tvg-id rule, a per-source cache and the now and next line under each channel are in (8 Nov, written by Haiku, uncompiled); a gzip guide is refused, only the first answering address is used, and the programmes kept are those from two hours ago to three days ahead
229 P persistent IPTV cache: the guide is kept as a raw XMLTV file per source with Desktop's one hour freshness and twelve hour offline use (8 Nov, written by Haiku, uncompiled); no parsed snapshot is stored
413 D Xtream short EPG: the fallback rule runs for Xtream sources whose XMLTV guide is empty, up to 120 channels, and feeds the now and next line (8 Nov, written by Haiku, uncompiled)
225 P live catchup: the catch-up URL builder exists with tests (8 Nov, written by Haiku, uncompiled); no channel menu entry plays it because the list has no start-time playback route
286 P AniList watched sync: list progress marks the first aired episodes watched (8 Nov, written by Haiku, uncompiled); the progress is read only after the AniList lists screen has been opened, and kitsu ids are not mapped
294 P MAL watched sync: list progress marks the first aired episodes watched (8 Nov, written by Haiku, uncompiled); the progress is read only after the MyAnimeList lists screen has been opened
289 D AniList profile and avatar: the AniList name and avatar show in Settings and a toggle uses the avatar as the Harbor avatar (AniListAvatarSync); the earlier note was out of date
301 P Simkl anime grouping: the pure grouping, rating average and year range are ported (8 Nov, written by Haiku, uncompiled); no screen uses them and the relations enhancement is not ported
284 P Trakt comments: sort, spoilers, replies and paging are in; the post, like and rating request builders exist (8 Nov, written by Haiku, uncompiled) but no screen posts
310 P OMDB ratings and budget: scores, cache, budget, refused key and now the awards parsing (8 Nov, written by Haiku, uncompiled); no screen shows awards or the budget, as Desktop reads neither
314 P Wikidata awards and people: titles have awards; the person award kind and collapse rules exist (8 Nov, written by Haiku, uncompiled); iOS fetches no people awards
201 P subtitle ranking and dedupe: provider search now deduplicates by language, URL, title and format, interleaves providers and prioritizes language; native rows and download cache preserve distinct results, while Desktop stream-hint ranking and automatic provider selection remain pending
22 P global search: with a TMDB key the search adds Desktop's TMDB movie and series rows after the addon rows, leaving out titles an addon row already shows (8 Nov, written by Haiku, uncompiled); the top-match ranking and the year or genre intent exist as helpers that no screen uses
23 D movie search: TMDB movies join the addon rows with the poster filter and the 12-title cap (8 Nov, written by Haiku, uncompiled); the top-match order is a helper only
24 D series search: TMDB series join the addon rows with the poster filter and the 12-title cap (8 Nov, written by Haiku, uncompiled); the top-match order is a helper only
25 D search provider aggregation: TMDB rows are merged into the addon rows in the search screen, and with no TMDB key nothing changes (8 Nov, written by Haiku, uncompiled)
27 P search anime: the merge rule (source order, repeated ids and names skipped, cap of 8) exists (8 Nov, written by Haiku, uncompiled); iOS has no AniList, Jikan or Kitsu text search client to feed it
5 P Discover personalized feed: Desktop's affinity ranking (genre 4, decade 1.5) orders the Trending and Top Rated shelves, and the featured ranking already matched (8 Nov, written by Haiku, uncompiled); exclusions of downvoted titles, the locale penalty and the extra lanes are not ported
6 P daily discovery rails: the seeded row order with pinned anchors exists as a tested helper (8 Nov, written by Haiku, uncompiled); iOS has no daily row catalog to order
8 P genre discovery: all eighteen Desktop tiles now open the correct TMDB filter or the public Cinemeta genre catalog without a TMDB key; artwork loads lazily and the richer editorial genre screen remains pending
16 P network and premiere rails: the network list, the premiere parameters and the Quick Watches Under 90 parameters match Desktop (8 Nov, written by Haiku, uncompiled); the series rail order and about fifteen Desktop rails (80s Classics, Prestige Drama and others) are not in iOS
41 P episode details: rows show the runtime, a New badge, the percent watched and the watched-ago text with a thin progress bar (8 Nov, written by Haiku, uncompiled); no manual unwatched override in that text, no dedicated episode detail view
39 D recommendations and similar titles: the related list falls back to Trakt related titles when the main source is empty, merged and mapped with Desktop's rules (8 Nov, written by Haiku, uncompiled)
33 P real content details: the shared crew rules (three or more shared films, the line text) exist as helpers (8 Nov, written by Haiku, uncompiled); there is no crew query, cache or line on the page and no detail layout editor
172 D subtitle styling: the current look can be saved as one of up to 12 presets (Desktop's English, Foreign and Arabic seeds), applied and removed from the subtitle style settings (8 Nov, written by Haiku, uncompiled)
174 P custom subtitle fonts: the accepted file types, the 32 MB limit and the name rule exist (8 Nov, written by Haiku, uncompiled); the import is not wired because the player maps any unknown font id to Inter
369 D Suwayomi library categories are selectable in the iOS shelf with saved progress, title search and return to the full shelf; category requests use GraphQL with REST fallback. Apple build and the two selected category cases passed.
371 D The Suwayomi extension manager lists, adds and removes server repositories, normalizes GitHub links, offers Desktop suggestions and refreshes the server index after edits. Apple build and the URL case passed; live server mutations remain unverified.
225 D Past programmes can open the native player from the channel programme list when the catch-up URL is valid. Channel headers, title, profile scope and the twelve-hour XMLTV history are wired. Native route and provider playback need validation.
377 D Book mode adapts to two-page spreads on wide regular-width iPad layouts with compatible page shapes. It uses native page curls, RTL pairing, odd-page padding and spread-aware resume and completion. Physical iPad validation remains pending.
203 P External subtitle estimates can be reviewed and applied from the player, and verified community matches keep automatic application. Desktop's full source matching and structural calibration are pending.
63 D Home and Anime use Desktop's normalized-name and type dedupe, preserving the first loaded catalog in source order. Home keeps its classic and show-all behavior. Non-content filtering and episode-meta collapse remain wired.
64 D Catalog request planning fills required extras from the first offered option when no explicit value is supplied. Search-only catalogs stay out of browse, and selected genres and skip values override their defaults.
65 D Catalog planning and the native browser preserve legacy extraSupported declarations through the addon bridge and honor search and skip. Existing installations refresh from their configured manifests.
66 D Metadata and subtitle resource plans inherit absent manifest types and ID prefixes while respecting explicit overrides. Playback stream requests preserve Desktop's separate stream-specific selector.
27 D Global search queries the native AniList, Jikan and Kitsu providers, applies Desktop source order, caps and deduplication, and opens results in the normal detail route. Apple and live provider verification pending.
433 D The local music library tracks a selected iOS Files folder and rescans it by size and modification time. It preserves playlist identities, keeps manually removed paths suppressed and prunes managed copies only after a complete traversal. Unbookmarkable folders keep one-time import. Apple verification pending.
204 D The built-in OpenSubtitles v3 search is wired into the player, follows its setting and steps aside for an enabled equivalent addon. Its public lookup is independent of account sign-in. Apple execution pending.
53 D Installed addon links share via stremio and open the iOS install form when delivered by the OS. The configured manifest path and query are preserved, with a visible host and explicit install action.
364 P Harbor and Stremio detail links now open the iOS title screen with episode hints, and Stremio manifests open the installer. Desktop list, music and profile routes and browser URL handoffs remain pending.
1 P Home uses Desktop's public Trending, Trakt and Simkl pools with a three-hour cache, explicit rail priority, catalog fallback, and per-title ranking. Native base catalog composition and some personal rails still differ.
""")

SETTINGS = expand("""
1-3 M no UI sounds
4 D blur comments until revealed (5 Nov, uncompiled)
5-6 D blurEpisodes, TMDB key
7 D OMDb key kept in the Keychain per profile, saving it resets the budget (7 Nov, compiled; cases passed)
8-10 M no RPDB/IMDb fallback/Fanart keys
11 P TVDB used without a user key setting
12-17 D debrid keys, region
18-19 D stream ranking languages and require-language (5 Nov, uncompiled)
20 D
21 M
22 D
23-29 M card rating chips not ported
30 P no master switch: each provider has its own Details toggle (7 Nov, compiled; cases passed)
31-32 D IMDb/TMDB detail rating toggles (7 Nov, compiled; cases passed)
33 M no MAL detail rating
34-39 D Rotten Tomatoes, audience, Letterboxd, Metacritic, Trakt and MDBList detail toggles (7 Nov, compiled; cases passed)
40 D show Trakt comments on detail pages (5 Nov, uncompiled)
41 M card rating chips not ported
42 D SIMKL detail toggle with SIMKL's community rating from the Harbor community server (7 Nov, uncompiled)
43-44 M rating badges not ported
45 D
46-51 M card badges and home languages not ported
52-55 D poster settings
56-60 M no liquid glass settings
61-64 D poster behavior settings
65 P Top 10 rail without ribbon options
66-72 M ribbon side, award tabs, title scales, UI scale
73-86 M no web UI, remote or controller settings
87-88 M
89 D interface.autoRotateBanners
90-96 M hero trailer and hero layout settings
97 D
98 X Big Picture excluded
99-103 X iOS auto-lock replaces an idle screensaver
104-105 D resume settings
106-107 X desktop fullscreen windowing
108-112 M advisory toasts and volume HUD
113-114 D custom playback speeds and sleep minutes (5 Nov, uncompiled)
115 D default speed
116-118 M
119 D
120-122 M
123 D episode sort menu: oldest or newest first (5 Nov, uncompiled)
124 D show episode ratings: community IMDb ratings plus OMDb season ratings on the episode picture (7 Nov, uncompiled)
125 D
126 D hide and skip episodes: menu, list filter and Up Next (5 Nov, uncompiled)
127-128 M
129 P episode order via TVDB season type
130-131 D
132 M
133-134 D Harbor avatar and colour
135-136 D AniList and MyAnimeList sync of watch progress (5 Nov, compiled; cases passed)
137-142 M tracker comments and avatars
143-150 D Trakt session, streaming catalogs, adult addons
151-156 M Watch Together settings
157-165 X Discord Rich Presence
166 X single native player engine
167-170 M PiP behavior, player shells and chrome
171 D player screen lock (5 Nov, uncompiled)
172 M seek preview
173 D instant play
174-176 M preparation, stall switching
177 X desktop fullscreen mode
178 M season source lock
179 D remember last stream (5 Nov, uncompiled)
180 D
181 P tone mapping without the SDR toggle
182-185 X RTX, macOS EDR, display panel
186-189 M motion interpolation, Anime4K
190-192 X embedded/separate desktop player windows
193 X P2P chip needs the torrent engine
194-195 M
196-201 X torrent engine settings
202 D source mode (P2P choice excluded)
203 M
204-205 X torrent cache
206 M
207-208 X desktop cache folders
209-211 M remote streaming server, cast transcoding
212-217 M Anime4K and shaders
218-226 D subtitle languages and style
227 M
228-230 D
231 P reading fonts only
232-235 D
236 M subtitle providers
237-239 D subtitle sync indicator: switch, position and size (5 Nov, uncompiled)
240 M PiP subtitles
241-243 D
244 M
245 D
246-252 M advanced auto-sync options
253 D
254-256 M
257 X updates belong to the App Store/TestFlight
258-260 D auto-skip intros, recaps and outros (5 Nov, uncompiled)
261 M no ad skip source
262 D skip button
263 D skip button auto-hide (5 Nov, uncompiled)
264 M
265 P forced subtitles option partial
266-267 D
268-271 M NFO and local library
272 P watched markers without the badge option
273-282 M local playback, media servers, catalog pins, poster URL
283-285 X pointer hover previews have no touch form
286-287 D
288 M
289-290 X pointer hover styles
291 D MDBList key kept in the Keychain per profile (7 Nov, compiled; cases passed)
292-296 M song ID, AI keys
297-301 X Games excluded
302-306 M AI search settings
307 X Direct3D flip model
308-309 M
310 D
311-312 X desktop renderer and graphics backend
313 M
314 P buffer size without boost
315-316 D
317 D maximum volume boost: 100 to 600 percent ceiling sent to mpv (7 Nov, uncompiled)
318 P earlier review Partial
319-322 X SVP is Windows software
323-324 D seek steps
325-327 M
328-329 X desktop HDR window and Esc key
330 M
331-338 X TV and Big Picture navigation
339 M
340-341 X Big Picture overscan, desktop HDR stage
342-346 M subtitle provider keys
347-348 D audio normalizer and sound profile (5 Nov, uncompiled)
349 P route picker instead of a device setting
350 M
351-352 D
353-354 D still-watching check-in and its threshold (5 Nov, uncompiled)
355 M
356-359 M
360 X native iOS scrolling
361-362 M
363 P external continue watching via cwSources
364 D
365 M
366 P profile prompt interval
367-368 D
369 P sports favourites
370-371 M
372 D
373 P episode blur covers thumbnails
374-375 D
376-380 M
381-382 D
383-388 M custom logos, app icons, music seek thumbs
389 X pointer hover
390 M
391 D
392-394 M
395 P library sort
396 M
397 D
398-401 M
402 X desktop title bar
403-409 M fullscreen clock
410 X desktop title bar
411-413 M top bar appearance
414 X window dragging
415 M
416 D
417 M
418 D
419-422 M
423 D
424-427 X tray and window focus
428-430 M
431-432 D
433-434 P home rows and navigation names
435 M
436 P anime rows
437-443 M hotkeys and anime picks settings
444 D
445-447 M
448-453 D picker settings
454-455 M custom stream filters
456-457 M seek bar style and height
458 D
459-462 M
463 X pointer hover
464-465 M
466-468 X custom CSS/JS/HTML for Desktop's web interface
469 M
470 P calendarSource kept per profile; six of Desktop's nine sources (7 Nov, uncompiled)
471-473 M Simkl rails
474 D
475 M
476-477 D calendar settings
478 P customCalendar: people, genres, providers, countries, media types and Trakt sources with a filter sheet (7 Nov, uncompiled)
479 M
480-483 X desktop download folders
484-485 M
486 P addon deep-link install
487-488 P earlier review Partial
489-490 M
491 M
492-493 X Games excluded
494-497 M
498 D
499 M
500-501 D
502 M
503 D
504-511 M
1-3 X UI sound effects: iOS uses haptics and system sounds
56-60 X Desktop glass effect settings: iOS has the system's own Liquid Glass
69-70 X title scales: iOS scales text with Dynamic Type
72 X UI scale: iOS scales with Dynamic Type and display zoom
73-74 X serve the web interface and be remote controlled: an iPhone does not host or take remote control
75-86 X game controller cursor and keyboard: pointer navigation for a TV or desktop, iOS is touch
111-112 X player volume overlay: iOS shows its own volume indicator
116 X nav bar sleep timer button: there is no desktop nav bar, the player has its own timer
152-154 X Cloudflare relay credentials and deploy state: a server task, not for a phone
168-170 X player shell, chrome theme and black menu: cosmetic skinning with little use on touch
186-189 X motion interpolation and Anime4K: heavy GPU work that drains a phone or tablet
212-217 X Anime4K shaders and custom shader folders: desktop GPU and folder features
292-295 X song identification keys and provider: iOS cannot capture system audio
308 X extra mpv options: a free-text power-user field for desktop tuning
313 X force yuv420p: a Windows GPU compatibility workaround
327 X share watch presence: feeds the Discord desktop presence
339 X tab hotkeys: desktop keyboard shortcuts for switching tabs
355 X keyboard pause shows controls: a desktop keyboard behavior
378-380 X song identification toggle and card style: iOS cannot capture system audio
383-384 X custom logo mark and wordmark: desktop title bar branding
387 X music artwork as app icon: iOS cannot change the app icon on its own
403-409 X fullscreen clock: iOS shows the system clock, the settings are desktop window options
411-413 X top bar scroll blur and appearance: there is no desktop top bar
437 X custom hotkeys: remapping desktop keyboard shortcuts
456-457 X seek bar style and height: cosmetic skinning with little use on touch
459-462 X seek bar image, fill and dot shape: cosmetic skinning with little use on touch
464-465 X seek dot size and image: cosmetic skinning with little use on touch
469 X webhooks: fired by a desktop app that stays running, iOS cannot
479 X webhook rules: fired by a desktop app that stays running, iOS cannot
491 X collapsible desktop sidebar: iOS has its own tab bar and sidebar
511 X Audd API key: song identification is not possible on iOS
356-357 D hide watched and unreleased titles in the home catalog rows, in Home layout (7 Nov, uncompiled; written by Haiku in a trial)
394 D Watchlist shows only saved titles: off also lists unstarted entries Stremio auto-added (7 Nov, uncompiled; written by Haiku in a trial)
400 D Continue Watching advances to the next episode, optional (7 Nov, uncompiled; written by Haiku in a trial)
51 D Home catalogs language filter on the Home rows by original language (7 Nov, uncompiled; written by Haiku in a trial)
282 D hide titles under posters on poster cards (7 Nov, uncompiled; written by Haiku in a trial)
377 X stream backdrop blur: the iOS stream picker draws no backdrop artwork, so there is nothing to blur
398 D keep anime in the Anime room only: Home Continue Watching leaves anime out (7 Nov, uncompiled; written by Haiku in a trial)
66 X Top 10 ribbon side: iOS poster cards have no ribbon, so there is no side to choose
279 D pinned catalogs on the Catalogs screen (7 Nov, written by Haiku, CI run 23 green)
280 D hidden catalogs on the Catalogs screen (7 Nov, written by Haiku, CI run 23 green)
392 D Home show every addon row (7 Nov, written by Haiku, CI run 23 green)
494 D Stats entry in the library header (7 Nov, written by Haiku, CI run 23 green)
23 D Rotten Tomatoes chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
24 D MAL chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
25 X anime card rating choice: iOS has no IMDb title source for anime, so MAL is always used
26 D Metacritic chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
27 D Letterboxd chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
28 D MDBList chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
29 D Trakt chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
41 D SIMKL chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
47 D maximum score chips per card (7 Nov, written by Haiku, CI run 24 green)
117 D score chip placement top or bottom (7 Nov, written by Haiku, CI run 24 green)
120 D Popcornmeter chip on poster cards (7 Nov, written by Haiku, CI run 24 green)
121 D episode layout list, strip or grid (7 Nov, written by Haiku, CI run 24 green)
122 D episode card scale (7 Nov, written by Haiku, CI run 24 green)
127 X HD episode images: iOS never builds TMDB still URLs, so the toggle would change nothing
128 P episode arcs from TMDB story groups on plain series; no TVDB order or anime pool (7 Nov, written by Haiku, CI run 24 green)
362 X Letterboxd profile card: iOS has no profile surface for it
393 D New Episodes row on Home (7 Nov, written by Haiku, CI run 24 green)
399 D what happens to a finished anime in Continue Watching (7 Nov, written by Haiku, CI run 24 green)
401 D remove shows from Continue Watching once caught up (7 Nov, written by Haiku, CI run 24 green)
428 X Continue Watching snapshot retention: iOS saves the position only, not frames
429 X Continue Watching snapshot quality: iOS saves the position only, not frames
430 D Continue Watching episode still artwork (7 Nov, written by Haiku, CI run 24 green)
505 D Letterboxd settings: enable, mode, username, catalogs, custom lists, ratings on posters (7 Nov, written by Haiku, CI run 24 green)
195 P stremioServerTranscode is stored; Desktop has no control for it either (7 Nov, written by Haiku, CI run 25 pending)
209 D remote streaming server address (7 Nov, written by Haiku, CI run 25 pending)
210 D use the remote server exclusively (7 Nov, written by Haiku, CI run 25 pending)
211 P castAlwaysTranscode is stored; there is no cast pipeline yet (7 Nov, written by Haiku, CI run 25 pending)
236 P subtitle sources: Wyzie is wired but not exercised at runtime; SUBDL and Subsource are searched but their zip or key-protected files are not loadable yet (7 Nov, written by Haiku, CI run 25 pending)
296 D AI search key (7 Nov, written by Haiku, CI run 25 pending)
302 D AI search model (7 Nov, written by Haiku, CI run 25 pending)
303 D AI search provider (7 Nov, written by Haiku, CI run 25 pending)
304 D Groq key (7 Nov, written by Haiku, CI run 25 pending)
305 D Jina key (7 Nov, written by Haiku, CI run 25 pending)
306 D live web context for AI search (7 Nov, written by Haiku, CI run 25 pending)
342 P OpenSubtitles key is stored; auto-sync does not read it yet (7 Nov, written by Haiku, CI run 25 pending)
344 X Jimaku token: Desktop has no Jimaku provider, the key is only declared
345 P SUBDL key stored and used for search; zip downloads not loadable yet (7 Nov, written by Haiku, CI run 25 pending)
346 P Subsource key stored and used for search; downloads that need the key are not loadable yet (7 Nov, written by Haiku, CI run 25 pending)
67 X award tabs on poster cards: one Wikidata query per card is too costly on a phone grid
68 X award tab position: only meaningful with award tabs on poster cards
174 X instant playback preparation: it pre-creates debrid transfers before Play and iOS has no preparation pipeline
175 P auto-skip stalled streams: setting and decision policy exist; the player does not feed them yet (7 Nov, written by Haiku, CI run 31 green, 80 cases)
176 P wait before skipping a stalled stream: stored with the policy (7 Nov, written by Haiku, CI run 31 green, 80 cases)
178 D stay on one source for a season: saved after a pick and applied to the automatic start in DetailModel (7 Nov, written by Haiku, CI run 31 green, 80 cases)
268 X NFO poster size: iOS has no NFO artwork
269 X NFO backdrop size: iOS has no NFO artwork
270 X NFO logo size: iOS has no NFO artwork
276 D minimum local file size (7 Nov, written by Haiku, CI run 31 green, 80 cases)
277 X local auto scan: iOS cannot scan folders in the background
278 X local scan mode: no background scan on iOS
358 D local episode sort order (7 Nov, written by Haiku, CI run 31 green, 80 cases)
44 P SIMKL community score is shown as a chip on cards and on the detail page; the switch itself is not ported
325 D short seek back step on Shift plus the arrow keys (7 Nov, compiled and tested, run 24)
326 D short seek forward step (7 Nov, compiled and tested, run 24)
330 D ask before leaving the player (7 Nov, compiled and tested, run 24)
21 X subtitle indicator: Desktop shows it in the player's subtitle menu only
33 D MAL score on the detail page: an anime's detail ratings row shows MyAnimeList's catalog score unless the matrix hides it (7 Nov, policy green; the row is uncompiled)
43 D DUB badge on anime cards (7 Nov, written by Haiku, CI runs 37 to 39 green)
46 D Simkl rail granular toggles (7 Nov, written by Haiku, CI runs 37 to 39 green)
50 D New tag on poster cards (7 Nov, written by Haiku, CI runs 37 to 39 green)
71 P series first title in the player: stored, the player title does not read it yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
87 X trailer quality: the embedded player picks its own quality
88 D auto-play trailer on the detail hero (muted, off by default; 7 Nov, written by Haiku, CI runs 37 to 39 green)
90 D detail trailer audio (7 Nov, written by Haiku, CI runs 37 to 39 green)
95 D hero trailers on the featured hero (muted, off by default; 7 Nov, written by Haiku, CI runs 37 to 39 green)
96 D hero trailer audio (7 Nov, written by Haiku, CI runs 37 to 39 green)
118 D watchlist bookmark and its corner on poster cards (7 Nov, written by Haiku, CI runs 37 to 39 green)
137 D blur AniList comments (7 Nov, written by Haiku, CI runs 37 to 39 green)
138 D show AniList comments on anime detail pages (7 Nov, written by Haiku, CI runs 37 to 39 green)
139 D use the AniList avatar: the toggle applies it at once and the app applies it again after a launch or a profile switch (7 Nov, toggle green; the launch hook is uncompiled)
140 X Trakt avatar: the iOS Trakt account holds no profile picture
141 X Simkl avatar: the iOS Simkl account holds no profile picture
142 X MAL avatar: the iOS MAL account holds no profile picture
195 P stremioServerTranscode is stored; Desktop has no control for it either
206 P delete watched downloads: stored, not wired to the download manager (7 Nov, written by Haiku, CI runs 37 to 39 green)
227 P normalise ASS subtitle size: policy and setting exist, the player does not call them yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
244 P secondary subtitle scale: stored, nothing draws a second subtitle line yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
254 P prefer embedded subtitles: policy and setting exist, the player does not call them yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
255 P subtitle auto upgrade: policy and setting exist, the player does not call them yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
256 P preselect subtitles before playback: policy and setting exist, the picker does not call them yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
264 P block words for audio and subtitle tracks: policy and setting exist, the player does not call them yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
309 D picture quality preset for mpv (7 Nov, written by Haiku, CI runs 37 to 39 green)
350 X bandwidth hint: iOS has no bitrate ranking
365 X playlists tab switch: iOS shows VOD without it
370 X sports odds: no odds data on iOS
371 X sports without a provider: iOS has no gate to relax
376 P spoilers skip the next episode: stored, the episode list does not read it yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
203 X queue drives navigation: the iOS player has no episode queue
417 X plugins outside the plugins tab: no catalog merge on iOS
419 X plugin auto check: iOS has only the manual update
420 X plugin background prefetch: no scheduler on iOS
421 X plugin poster languages: no listing extras on iOS
422 X plugin poster quality: no listing extras on iOS
438 P favourite anime genres: setting and policy exist, the Anime page does not apply them yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
439 P excluded anime origins: setting and policy exist, picks carry no origin on iOS (7 Nov, written by Haiku, CI runs 37 to 39 green)
440 P hide watched anime picks (7 Nov, written by Haiku, CI runs 37 to 39 green)
441 X anime picks dismissed at: Desktop writes it and never reads it
442 X AniList rows hidden: Desktop only migrates it into the row settings
443 X MAL rows hidden: Desktop only migrates it into the row settings
445 X profile audio: no profile audio on iOS
446 X sync indicator: no iOS view shows a syncing mark during playback
447 X sync indicator position: same
454 D custom stream filters (7 Nov, written by Haiku, CI runs 37 to 39 green)
455 D active stream filter (7 Nov, written by Haiku, CI runs 37 to 39 green)
471 D Simkl home rails switch (7 Nov, written by Haiku, CI runs 37 to 39 green)
472 D Simkl Up Next rail (7 Nov, written by Haiku, CI runs 37 to 39 green)
473 D Simkl trending rail (7 Nov, written by Haiku, CI runs 37 to 39 green)
475 P Simkl anime title language: stored, applied nowhere yet (7 Nov, written by Haiku, CI runs 37 to 39 green)
484 X NYT key: iOS has no NYT lists
485 X sports API key: iOS has no API-Sports path
489 X IPTV force proxy: Desktop never reads it
490 X IPTV EPG offset: iOS has no EPG guide
495 X library hero: the iOS library has no hero
497 X feed locale bias: iOS Discover has no locale ranking
502 X pause list status on pause: Desktop never reads it
8 D RPDB key (7 Nov, written by Haiku, CI run 42 green, 103 cases)
9 X IMDb API fallback: iOS has no client for it
10 D Fanart key (7 Nov, written by Haiku, CI run 42 green, 103 cases)
91 D hero shadow strength on Home (7 Nov, written by Haiku, CI run 42 green, 103 cases)
92 D full hero banner (7 Nov, written by Haiku, CI run 42 green, 103 cases)
93 D full quality hero image (7 Nov, written by Haiku, CI run 42 green, 103 cases)
94 D hero feed choice on Home (7 Nov, written by Haiku, CI run 42 green, 103 cases)
281 X poster base URL: a custom host would receive the RPDB key
288 X scroll up to the trailer: needs Desktop's detail scroll behaviour
151 D Watch Together relay address (7 Nov, written by Haiku, CI runs 43 and 44 green)
155 X share cursors: a touch screen has no pointer, the value is stored only
156 P guests pick their own source: stored and read by the follower, no screen applies it yet (7 Nov, written by Haiku, CI runs 43 and 44 green)
108 D content advisory card in the player: shows once per source after playback starts, from Harbor's parental guide for an IMDb id (7 Nov, written by Haiku, uncompiled; the endpoint host is unconfirmed)
109 D content advisory card theme (7 Nov, written by Haiku, uncompiled)
110 D "Ignore this title" on the content advisory card, kept on the device (7 Nov, written by Haiku, uncompiled)
48 D format chips on stream picker rows can be turned off (7 Nov, written by Haiku, uncompiled)
49 D quality line style under the player title: text bar or chips (7 Nov, uncompiled)
194 D stream quality under the player title: resolution and HDR from the decoded picture and mpv's gamma (7 Nov, uncompiled)
343 D TheIntroDB key, kept in the Keychain per profile and sent as X-API-Key (7 Nov, written by Haiku, uncompiled)
396 P prefer my installed metadata addon: the meta plans are reordered with Cinemeta last; Desktop's poster preference is not ported (7 Nov, written by Haiku, uncompiled)
415 X remember the detail page scroll: the navigation stack already keeps it on iOS
361 X SIMKL card setting: Desktop shows an owner-only card in its profile sidebar and iOS has no profile cards
240 D subtitles can be hidden in the Picture in Picture window while they stay on inline (7 Nov, written by Haiku, uncompiled)
175 D auto-skip stalled streams: an automatically started source that has not begun playing by the end of the wait is set aside and the next candidate opens after the player closes (7 Nov, policy green; the player and DetailModel hooks are uncompiled)
176 D wait before skipping a stalled stream: read by the stall driver (7 Nov, uncompiled)
167 X PiP behavior Resize or Detached: Resize shrinks Harbor's own window, which an iOS app cannot do, and Detached is what Picture in Picture already is
271 X on-disk badge on cards: iOS local records are not linked to catalog ids, so no card can tell a title is on disk
273 X local playback mode: iOS has no choice between a local copy and a stream by catalog id
274 X playback source preference: iOS has no video media servers (Plex and Jellyfin are music only) and no local match by id
275 X preferred media server: iOS has no video media servers
390 D saved music speed presets: name, speed, pitch, reverb and keep pitch are kept per profile in the Keychain (MusicSavedSpeedPresets); the earlier audit missed it
504 D translate overviews: off keeps the English plot and tagline from TMDB while the metadata language is another one; the setting travels with the profile (8 Nov, policy tests, uncompiled)
132 X TVDB PIN: Desktop declares tvdbPin in its settings but nothing reads it
499 X Arabic welcome seen flag: Desktop 0.9.132 exports the Arabic welcome screen and never mounts it
359 X local review dismissal count: dismisses Desktop's local-file review banner; iOS local records are not matched to titles, so no file is flagged for review
385 X custom app icon: iOS only accepts alternate icons built into the app, never an image chosen at run time
386 X custom app icon preset: same reason, the presets would have to ship as alternate icons in the build
388 X music seek thumb: the iOS dock uses the system slider, which always draws its own thumb; Desktop's hover thumb needs a pointer
172 X seek preview setting: the previews are excluded (a second decoder on the stream), so nothing would read it
261 D skip injected ads automatically: read by the segment loader and the player (8 Nov, uncompiled)
506 D enable injected ad skip: gates the corpus lookup and the report button (8 Nov, uncompiled)
507 D always show the report button (8 Nov, uncompiled)
508 D report button first-time tip, dismissed once and kept per profile (8 Nov, uncompiled)
509 D X-Ray: a player button opens the cast rail and the browser with the cast and the about text, a tap opens the person's page; the live scene scan is excluded (8 Nov, written by Haiku, uncompiled)
250 D use community corrections: a tier A answer from the shared database is applied without analysing the audio (8 Nov, written by Haiku, uncompiled)
251 D community sync server: blank uses Harbor's server, any http or https address replaces it (8 Nov, written by Haiku, uncompiled)
252 D private mode: no lookup and no report while it is on (8 Nov, written by Haiku, uncompiled)
272 D watched badge: hides the check on anime movie entries and live episode rows; iOS has no check on posters (8 Nov, written by Haiku, uncompiled)
30 D detail ratings master switch: hides the whole ratings row and the main score badge, next to the per-provider switches (8 Nov, written by Haiku, uncompiled)
44 D Simkl community ratings switch: gates the Simkl chip on cards and on the detail row; Desktop 0.9.132 stores it but reads it nowhere (8 Nov, written by Haiku, uncompiled)
314 D slow or unstable connection (buffer boost): with the automatic buffer size it uses Desktop's large profile, capped by the phone-memory budget the buffer already has; Desktop shows no control for it, the rule is an interpretation (8 Nov, written by Haiku, uncompiled)
181 D HDR to SDR tone mapping: Desktop's eight mpv options for an SDR display behind a switch; off by default here (Desktop: on) so today's output does not change (8 Nov, written by Haiku, uncompiled)
71 D series name first in the player: the top bar shows the episode line (S1 E3 · name) and the show name, swapped by the setting; Desktop's own code and label disagree on the default order and the label was followed (8 Nov, written by Haiku, uncompiled)
206 D delete watched downloads: a download that reaches 90 percent is removed when its player closes (8 Nov, written by Haiku, uncompiled)
376 D keep the next episode visible: the next unwatched episode stays clear in the episode lists and in the player panel, with its own switch (8 Nov, written by Haiku and Sonnet, uncompiled)
254 D prefer embedded subtitles: read when mpv reports its tracks; it picks the embedded track of the preferred language and refuses late external ones (8 Nov, written by Haiku, uncompiled)
255 D subtitle auto upgrade: a better track that arrives later replaces an automatic choice, never a manual one (8 Nov, written by Haiku, uncompiled; iOS does not load addon subtitles by itself, so only tracks mpv adds later count)
264 D block words for tracks: an audio or subtitle track that mpv picked is replaced when its title holds a blocked word, "commentary" by default as on Desktop (8 Nov, written by Haiku, uncompiled)
227 P normalise ASS subtitle size: applied to external local ASS files only; embedded tracks need Desktop's Tauri-only extract command and remote files are not fetched (8 Nov, written by Haiku, uncompiled)
256 P preselect subtitles before playback: not wired, iOS hands the source straight to the player and the tracks only exist once mpv has loaded the file
438 P favourite anime genres: each favourite adds a Jikan genre request to Top Picks (8 Nov, written by Haiku, uncompiled); Desktop's daily seeded page, history seeding and franchise merge are not ported
440 D hide watched anime picks: wired, close to a no-op because Top Picks already drop every library anime (8 Nov, written by Haiku, uncompiled)
439 P excluded anime origins: passed through the policy, but no pick carries a country on iOS
475 P Simkl anime title language: the helpers exist and are tested, no card calls them yet because iOS has one title per Simkl row
156 D guests pick their own source: the invite carries the flag and the guest's card then reads Choose instead of Join, leaving the source to the guest (8 Nov, uncompiled)
435 X own navigation layout kept while a theme brings one: iOS themes import colors and backgrounds only and carry no navigation layout, so there is nothing to put aside
496 X manga enabled: Desktop's opt-in start page for manga sources; iOS opens the manga section directly and reaches its sources and imports from inside it
510 X X-Ray live scan: Desktop matches faces on the frame against the cast photos with its own recognition model (useFaceId); iOS Vision only detects faces and no model ships
248 X subtitle auto-sync speech recognition: Desktop runs a downloaded model through Rust commands (asr_ensure_model, asr_transcribe_windows) that iOS does not have
373 D spoilerHideThumbnails: the Blur thumbnails toggle now writes Desktop's key (default on) and every episode list, card and the player panel read it (8 Nov, written by Haiku, uncompiled)
5 X blurEpisodes: Desktop blurs the hero image and stills on its episode detail page; iOS has no dedicated episode detail page, so nothing reads the setting (the toggle labelled Blur thumbnails is Desktop's spoilerHideThumbnails)
396 P prefer my installed metadata addon: the meta plans are reordered with Cinemeta last, and Desktop's poster rule picks the answer for the detail page, filling missing artwork from Cinemeta (8 Nov, written by Haiku, uncompiled); the card title swap is not ported
246 P Uncalibrated audio corrections are offered for review in the player, following the shipped Desktop calibration. Automatic application of calibrated structural results and its setting are pending.
236 D Per-profile OpenSubtitles, Wyzie, addon, SUBDL and Subsource toggles drive the player search. OpenSubtitles steps aside for an enabled equivalent addon. The player accepts bounded ZIP files and exact-origin Subsource downloads.
345 D The profile key enables SUBDL lookup, and the player prepares its downloaded subtitles or selects a matching episode and language from the ZIP.
346 D The profile key enables Subsource lookup and its authenticated download. The player sends the key only to the Subsource HTTPS endpoint, refuses redirects and extracts bounded text subtitles.
265 D The per-profile native-audio setting automatically selects an eligible forced track in preferred language order, or disables the primary track when no forced choice exists. Manual choices retain priority.
486 D The active profile controls whether iOS-delivered Stremio install links are routed to Harbor's installer. URL scheme selection belongs to iOS.
247 P The profile can enable the pinned Desktop drift monitor after subtitle alignment. Native mpv speech sampling and explicit confirmation differ from Desktop's audio backend. Native validation is pending.
249 P The experimental profile setting can offer a cross-language correction using the pinned Desktop workflow and the selected audio language. iOS measures separate audio windows with mpv. Automatic structural calibration and real-source validation remain pending.
65 P The original corner ribbon follows the active Home Top 10 and moves a bookmark sharing its corner. Native Home rows still differ from Desktop's data in some configurations.
66 D The active profile chooses the Top 10 ribbon's leading or trailing corner. The original assets follow Desktop's logical layout direction.
""")

def audit(items, verdicts, label):
    rows = []
    for index, item in enumerate(items, 1):
        verdict, note = verdicts.get(index, ("?", ""))
        if item.get("review", "").startswith("excluded_by_owner"):
            verdict, note = "X", note or "excluded by owner"
        rows.append({"index": index, "id": item["id"], "desktop_source": item.get("desktop_source"), "verdict": verdict, "note": note})
    missing = [row for row in rows if row["verdict"] == "?"]
    assert not missing, f"{label}: unclassified {missing[:3]}"
    return rows

def score(rows):
    counts = Counter(row["verdict"] for row in rows)
    counted = counts["D"] + counts["P"] + counts["M"]
    weighted = (counts["D"] + 0.5 * counts["P"]) / counted * 100 if counted else 0
    return counts, counted, weighted, counts["D"] / counted * 100 if counted else 0, (counts["D"] + counts["P"]) / counted * 100 if counted else 0

behaviors = audit(INVENTORY["behaviors"], BEHAVIORS, "behaviors")
settings = audit(INVENTORY["settings"], SETTINGS, "settings")
summary = {}
for name, rows in (("behaviors", behaviors), ("settings", settings), ("all", behaviors + settings)):
    counts, counted, weighted, strict, generous = score(rows)
    summary[name] = {"total": len(rows), "ported": counts["D"], "partial": counts["P"], "missing": counts["M"], "excluded": counts["X"],
                     "counted": counted, "weighted_percent": round(weighted, 1), "ported_only_percent": round(strict, 1),
                     "ported_or_partial_percent": round(generous, 1)}
areas = []
for start, end, title in BEHAVIOR_AREAS:
    counts, counted, weighted, _, _ = score([row for row in behaviors if start <= row["index"] <= end])
    areas.append({"area": title, "range": f"B{start}-B{end}", "ported": counts["D"], "partial": counts["P"], "missing": counts["M"],
                  "excluded": counts["X"], "weighted_percent": round(weighted, 1)})
out = {"schema": 1, "date": "2026-11-04", "method": __doc__.strip(), "summary": summary, "behavior_areas": areas,
       "behaviors": behaviors, "settings": settings}
(ROOT / "docs/ios/parity-audit-2026-11-04.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", "utf-8", newline="\n")
print(json.dumps({"summary": summary, "areas": areas}, indent=1))
