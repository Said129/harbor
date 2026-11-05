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
175 M no playback audio filters
176 X RTX HDR needs an NVIDIA Windows driver
177 P earlier review Partial
178 M no motion interpolation
179-180 P earlier review Partial
181-182 D next episode and auto advance
183 D A-B loop (5 Nov, uncompiled)
184 D sleep timer (5 Nov, uncompiled)
185 M no stats overlay
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
283 P Trakt calendar in TraktHome
284 M no Trakt comments
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
299-301 P Simkl calendar, ratings, anime grouping partial
302-304 M Letterboxd not ported
305 P earlier review Partial
306-308 D TMDBService, MovieCollection, IMDb resolution
309 P TMDB images, trailers and watch providers
310-313 M no OMDB, RPDB, Fanart or MDBList
314 M Wikidata used for music/books only
315 D TVDBService
316 M no TVMaze
317-318 D Kitsu (AnimeService), AniZip mappings
319 P Jikan in AnimeService
320 P earlier review Partial
321 M no calendar source filters
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
""")

SETTINGS = expand("""
1-4 M no UI sounds or comments
5-6 D blurEpisodes, TMDB key
7-10 M no OMDB/RPDB/IMDb fallback/Fanart keys
11 P TVDB used without a user key setting
12-17 D debrid keys, region
18-19 D stream ranking languages and require-language (5 Nov, uncompiled)
20 D
21 M
22 D
23-44 M rating badges and detail ratings not ported
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
124 M
125 D
126-128 M
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
167-172 M PiP behavior, player shells and chrome, screen lock, seek preview
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
236-240 M subtitle providers, offset indicator, PiP subtitles
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
291-296 M MDBList, song ID, AI keys
297-301 X Games excluded
302-306 M AI search settings
307 X Direct3D flip model
308-309 M
310 D
311-312 X desktop renderer and graphics backend
313 M
314 P buffer size without boost
315-316 D
317 M
318 P earlier review Partial
319-322 X SVP is Windows software
323-324 D seek steps
325-327 M
328-329 X desktop HDR window and Esc key
330 M
331-338 X TV and Big Picture navigation
339 M
340-341 X Big Picture overscan, desktop HDR stage
342-348 M subtitle provider keys, audio normalisation and profile
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
469-470 M
471-473 M Simkl rails
474 D
475 M
476-477 D calendar settings
478-479 M
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
