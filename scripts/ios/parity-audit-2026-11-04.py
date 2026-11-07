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
287 P AniList lists: read-only browse by status with search and type filter, no edits (8 Nov, written by Haiku, CI run 23 green)
288 D AniList recommendations rail from the lists, Desktop ranking and franchise dedupe (8 Nov, written by Haiku, CI run 23 green)
337 P Theme Studio without the code editor: library, import/export and background (8 Nov, written by Haiku, CI run 23 green)
339 D theme import / export as Desktop's JSON (8 Nov, written by Haiku, CI run 23 green)
340 D theme library: save, apply, rename, export, remove (8 Nov, written by Haiku, CI run 23 green)
341 P custom background image with dim; no logo (iOS cannot change the app icon this way) (8 Nov, written by Haiku, CI run 23 green)
349 P watching statistics: hours, titles, split, top titles, highlights, year heatmap from local history; genres and people need Desktop's network enrichment (8 Nov, written by Haiku, CI run 23 green)
302 D Letterboxd (Stremboxd) session: public username or full sign-in, token in the Keychain (8 Nov, written by Haiku, CI run 24 green)
303 D Letterboxd home rails (8 Nov, written by Haiku, CI run 24 green)
304 P Letterboxd catalogs appear as Home rails and in View All; no catalog-browser integration (8 Nov, written by Haiku, CI run 24 green)
26 D search people: People rail, top match and person page with filmography; cast opens it (8 Nov, written by Haiku, CI run 25 pending)
32 D AI search: the Ask AI screen from search with OpenRouter or Groq keys (8 Nov, written by Haiku, CI run 25 pending)
149 D remote streaming server: torrent streams resolve through the configured server, after debrid or first without one; wired in HarborService.resolve and compiled, parsing and policy tested, not exercised against a real server (8 Nov, written by Haiku, CI run 25 pending)
150 D strict remote server policy (8 Nov, written by Haiku, CI run 25 pending)
151 P transcode URL generation is built and tested; the decode-error retry that uses it is not wired (8 Nov, written by Haiku, CI run 25 pending)
152 D streaming server health check and Test connection (8 Nov, written by Haiku, CI run 25 pending)
205 D Wyzie subtitles through the optional provider search; wired in the player's addon-subtitle task and compiled, request and parsing tested, not exercised against Wyzie (8 Nov, written by Haiku, CI run 25 pending)
347 P AI assisted search with own keys; recommendations and the episode mode are not ported (8 Nov, written by Haiku, CI run 25 pending)
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
279 D pinned catalogs on the Catalogs screen (8 Nov, written by Haiku, CI run 23 green)
280 D hidden catalogs on the Catalogs screen (8 Nov, written by Haiku, CI run 23 green)
392 D Home show every addon row (8 Nov, written by Haiku, CI run 23 green)
494 D Stats entry in the library header (8 Nov, written by Haiku, CI run 23 green)
23 D Rotten Tomatoes chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
24 D MAL chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
25 X anime card rating choice: iOS has no IMDb title source for anime, so MAL is always used
26 D Metacritic chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
27 D Letterboxd chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
28 D MDBList chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
29 D Trakt chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
41 D SIMKL chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
47 D maximum score chips per card (8 Nov, written by Haiku, CI run 24 green)
117 D score chip placement top or bottom (8 Nov, written by Haiku, CI run 24 green)
120 D Popcornmeter chip on poster cards (8 Nov, written by Haiku, CI run 24 green)
121 D episode layout list, strip or grid (8 Nov, written by Haiku, CI run 24 green)
122 D episode card scale (8 Nov, written by Haiku, CI run 24 green)
127 X HD episode images: iOS never builds TMDB still URLs, so the toggle would change nothing
128 P episode arcs from TMDB story groups on plain series; no TVDB order or anime pool (8 Nov, written by Haiku, CI run 24 green)
362 X Letterboxd profile card: iOS has no profile surface for it
393 D New Episodes row on Home (8 Nov, written by Haiku, CI run 24 green)
399 D what happens to a finished anime in Continue Watching (8 Nov, written by Haiku, CI run 24 green)
401 D remove shows from Continue Watching once caught up (8 Nov, written by Haiku, CI run 24 green)
428 X Continue Watching snapshot retention: iOS saves the position only, not frames
429 X Continue Watching snapshot quality: iOS saves the position only, not frames
430 D Continue Watching episode still artwork (8 Nov, written by Haiku, CI run 24 green)
505 D Letterboxd settings: enable, mode, username, catalogs, custom lists, ratings on posters (8 Nov, written by Haiku, CI run 24 green)
195 P stremioServerTranscode is stored; Desktop has no control for it either (8 Nov, written by Haiku, CI run 25 pending)
209 D remote streaming server address (8 Nov, written by Haiku, CI run 25 pending)
210 D use the remote server exclusively (8 Nov, written by Haiku, CI run 25 pending)
211 P castAlwaysTranscode is stored; there is no cast pipeline yet (8 Nov, written by Haiku, CI run 25 pending)
236 P subtitle sources: Wyzie is wired but not exercised at runtime; SUBDL and Subsource are searched but their zip or key-protected files are not loadable yet (8 Nov, written by Haiku, CI run 25 pending)
296 D AI search key (8 Nov, written by Haiku, CI run 25 pending)
302 D AI search model (8 Nov, written by Haiku, CI run 25 pending)
303 D AI search provider (8 Nov, written by Haiku, CI run 25 pending)
304 D Groq key (8 Nov, written by Haiku, CI run 25 pending)
305 D Jina key (8 Nov, written by Haiku, CI run 25 pending)
306 D live web context for AI search (8 Nov, written by Haiku, CI run 25 pending)
342 P OpenSubtitles key is stored; auto-sync does not read it yet (8 Nov, written by Haiku, CI run 25 pending)
344 X Jimaku token: Desktop has no Jimaku provider, the key is only declared
345 P SUBDL key stored and used for search; zip downloads not loadable yet (8 Nov, written by Haiku, CI run 25 pending)
346 P Subsource key stored and used for search; downloads that need the key are not loadable yet (8 Nov, written by Haiku, CI run 25 pending)
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
