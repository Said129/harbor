# Filas pendientes de la auditoria (generado el 12 de noviembre de 2026)

Cada fila: `lista indice | id | verdicto | hueco`. P = parcial. El indice vuelve a empezar en 1 en cada lista (`behaviors`, `settings`).
El texto del hueco esta cortado por la auditoria: para el detalle lee el codigo de iOS y el fuente de Desktop (`desktop_source` del inventario `desktop-parity-0.9.132.json`).

## behaviors (37 filas)

- B 1 | Home hero and real catalogs | P | cross-row Home dedupe against the hero and the first-row Top 10 section still differ; they need the base rows separated from the personal and addon rails [Desktop: src/views/home.tsx]
- B 5 | Discover personalized feed | P | the people and keyword lanes need TMDB person and keyword ids kept per watched title, which taste events do not store; the featured source pool still differs [Desktop: src/views/discover.tsx]
- B 6 | Daily discovery rails | P | the people and keyword daily lanes, custom Discover row order and full awards paging (24 per page up to 150) remain [Desktop: src/views/discover.tsx]
- B 10 | Movies room | P | movie rows skip hero and earlier titles, drop rows under four titles and take the Top 10 from weekly trending as Desktop does; page collection rows remain because iOS has no local collections model [Desktop: src/views/movies.tsx]
- B 14 | Shows room | P | the rotating mast and weekly Top 10 exist; per-page collection assignments and the day-copy mast text remain [Desktop: src/views/shows.tsx]
- B 15 | Series Continue Watching | P | Desktop's manual-watched resurface rule reads a storage module iOS does not mirror [Desktop: src/views/shows.tsx]
- B 18 | Anime room | P | the anime room follows Desktop's row display rules and per-pool franchise dedupe; the Your MAL and Your AniList account rows, live Crunchyroll award metas and page collections remain [Desktop: src/views/anime.tsx]
- B 20 | Anime award winners | P | award winners sort newest first; live Crunchyroll award metas remain unported [Desktop: src/views/anime.tsx]
- B 21 | Anime Top Picks | P | Top Picks use a page per day and genre with taste genres first, AniList origin and a franchise merge; scored rotation, Kitsu sequels, the shown-picks ring, watch-history picks and new releases remain [Desktop: src/views/anime.tsx]
- B 22 | Global search | P | the empty search shows genre tiles; music, sports and character facets remain [Desktop: src/lib/search.ts]
- B 42 | Episode selection | P | episode search across seasons by title or SxE and the random-episode and mark-season items exist; mark-season writes to Trakt only because Simkl progress is read only [Desktop: src/views/detail/series-episodes.tsx]
- B 90 | Title / year mismatch rejection | P | the title gate needs Kitsu's alternative titles, a network fetch iOS does not make yet [Desktop: harbor-core/src/trust.rs]
- B 151 | Transcode URL generation | P | transcode URL generation exists; the decode-error retry needs a player failure classification that does not exist yet [Desktop: src/lib/stremio-server.ts]
- B 188 | Player episode panel | P | the episode panel honors Instant Play; browsing sources while the previous episode keeps playing and queue navigation remain [Desktop: src/components/player]
- B 201 | Subtitle ranking / dedupe | P | stream-hint ranking and the automatic provider choice exist; the movie-hash bonus and the timing preflight remain [Desktop: src/lib/subtitles]
- B 203 | Subtitle text resync | P | manual live sync for external SRT and VTT tracks exists; full source matching and structural calibration remain [Desktop: src/lib/subtitles]
- B 206 | Audio correlation subtitle sync | P | same ratio hypotheses and correlation gates as Desktop on a coarser grid with an energy voice detector; no piecewise tier [Desktop: src-tauri/src/subsync]
- B 242 | DLNA discovery | P | DLNA devices are added by their description address and cast. Automatic discovery needs SSDP multicast, an entitlement a sideloaded app cannot hold, so it stays manual [Desktop: src-tauri/src/dlna.rs]
- B 250 | Watch party create / join | P | the room shows who is ready and its current title; the other-title notice needs the player [Desktop: src/lib/together]
- B 257 | Source matching | P | source-matching scoring exists and is tested; no player flow uses it yet [Desktop: src/lib/together]
- B 267 | Local playback resume | P | The plain series episode picker uses the local last-played season after a valid explicit hint and before watched history. A manual season choice stays selected. Playback entry-point and alias parity remain open. [Desktop: src/lib/resume.ts]
- B 279 | Trakt watchlist import / export | P | import and change endpoints exist; Desktop's one-time export plan is not built [Desktop: src/lib/trakt]
- B 284 | Trakt comments | P | sort, spoilers, replies and paging exist; likes and the title rating are not ported [Desktop: src/lib/trakt]
- B 300 | Simkl user ratings | P | ratings are fetched and the write request exists; the screen that calls the write was not checked [Desktop: src/lib/simkl]
- B 301 | Simkl anime grouping | P | pure grouping exists; Desktop groups on its library tab, which needs a franchise list screen [Desktop: src/lib/simkl]
- B 312 | Fanart artwork | P | the anime series logo and backdrops fill from Fanart; anime movies and Desktop's poster and home hero logos remain [Desktop: src/lib/providers]
- B 314 | Wikidata awards / people | P | person pages load awards by IMDb name id; the person collapse key is not wired [Desktop: src/lib/providers]
- B 322 | Library release calendar | P | the library calendar has the curated order, limits and dedupe; dates come from addon metadata, not Desktop's Cinemeta or TMDB resolution [Desktop: src/lib/calendar.ts]
- B 329 | Content categories | P | the adult-content switch exists for plugin streams; the anime half and Stremio addon streams are not covered [Desktop: src/lib/parental.tsx]
- B 347 | AI assisted recommendations / search | P | AI assisted search with the person's own key exists; recommendations and the episode mode do not [Desktop: src/lib/ai-search.ts]
- B 349 | Watching statistics / Wrapped | P | statistics come from local history; genres and people need a TMDB credits pass [Desktop: src/lib/wrapped]
- B 364 | Harbor / Stremio deep links | P | Harbor and Stremio title links and addon links are routed; list, music and profile links remain [Desktop: src/lib/deep-link.ts]
- B 392 | Sports calendar and scores | P | sports calendar: the native date picker cannot mark live days and iOS does not fetch live state for other days [Desktop: src/lib/sports/espn-scoreboard.ts]
- B 395 | Sports score periods and statistics | P | period headings, boxscore stats and player tables exist; cricket partnerships and the baseball and football situation panels remain [Desktop: src/lib/sports/espn-summary.ts]
- B 397 | Sports favorite leagues and teams | P | a home team per league group exists; a team browser and a followed-team schedule remain [Desktop: src/lib/sports/favourites.ts]
- B 401 | Sports configured broadcast sources | P | each broadcaster gets a Live TV search link; attached channels, the playlist matcher and the page-URL resolver remain [Desktop: src/lib/sports/stream-resolver.ts]
- B 426 | Music playback queue | P | music playback queue: the expanded player can request and append fresh tracks from the queue context without interrupting playback; Discover currently uses the profile catalog rather than Desktop radio, and Spotify paging and artist blocks remain pending [Desktop: src-tauri/src/music/commands/playback.rs]

## settings (7 filas)

- S 128 | episodeArcGroups | P | arcs from TMDB story groups win over the TVDB order on plain series; anime pools have no arcs [Desktop: src/lib/settings/types.ts]
- S 247 | autoSyncDrift | P | The profile can enable the pinned Desktop drift monitor after subtitle alignment. Native mpv speech sampling and explicit confirmation differ from Desktop's audio backend. Native validation is pending. [Desktop: src/lib/settings/types.ts]
- S 249 | subtitleAutoSyncPivot | P | The experimental profile setting can offer a cross-language correction using the pinned Desktop workflow and the selected audio language. iOS measures separate audio windows with mpv. Automatic structural calibration and real-source validation remain pending. [Desktop: src/lib/settings/types.ts]
- S 396 | preferCustomMetaAddon | P | prefer my installed metadata addon: the meta plans are reordered with Cinemeta last, and Desktop's poster rule picks the answer for the detail page, filling missing artwork from Cinemeta (8 Nov, written by Haiku, uncompiled); the card title swap is not ported [Desktop: src/lib/settings/types.ts]
- S 438 | animeFavoriteGenres | P | favourite genres seed the picks after the taste genres with a daily page; the two-to-five page fill and the scored franchise merge detail are not ported [Desktop: src/lib/settings/types.ts]
- S 475 | simklAnimeTitleLanguage | P | Simkl anime title language: the helpers exist and are tested, no card calls them yet because iOS has one title per Simkl row [Desktop: src/lib/settings/types.ts]
- S 487 | iptvPlaylists | P | each source takes an optional guide address; Desktop's EPG-only source kind is not ported [Desktop: src/lib/settings/types.ts]
