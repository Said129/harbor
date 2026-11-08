# Desktop 0.9.132 → iOS parity audit (4 November 2026)

A code-level audit of the reproducible inventory (`desktop-parity-0.9.132.json`:
438 behaviors, 511 settings) against the iOS sources. Each item has one verdict
in `parity-audit-2026-11-04.json`, produced by
`scripts/ios/parity-audit-2026-11-04.py`, which also recomputes the totals.

## Verdicts

- **Ported (D):** an iOS implementation of the same behavior or setting exists.
- **Partial (P):** implemented in part, or an earlier review recorded it as
  Partial and nothing since shows it complete. P counts as half.
- **Missing (M):** no iOS implementation found.
- **Excluded (X):** an owner exclusion (Games, Kids/parental) or a recorded
  platform reason (local torrent engine, Big Picture, desktop windowing, tray,
  Direct3D/RTX/SVP, Discord desktop presence, App Store updates, pointer-only
  hover, Desktop's web-interface CSS/JS). Not in the denominator.

## Result

| Scope     | Items | Ported | Partial | Missing | Excluded | Weighted (P = ½) | Ported only | Ported or partial |
| --------- | ----: | -----: | ------: | ------: | -------: | ---------------: | ----------: | ----------------: |
| Behaviors |   438 |    250 |     125 |       1 |       62 |           83.1 % |      66.5 % |            99.7 % |
| Settings  |   511 |    240 |      33 |       3 |      235 |           92.9 % |      87.0 % |            98.9 % |
| All       |   949 |    490 |     158 |       4 |      297 |           87.3 % |      75.2 % |            99.4 % |

The 8 November follow-up connects Suwayomi categories to the manga shelf (B369).
This is a source audit. Focused Apple validation is pending.

The 6 November refresh adds the OMDb and MDBList ratings on the detail page (the two
provider keys, the Details column of the ratings matrix and the scores row), on top
of the AniList/MyAnimeList trackers, Trakt comments, the audio filter chain, the
playback stats card, screen lock, hide-episodes and the subtitle sync indicator.
Everything above was compiled and tested by focused runs 1 to 14; run 14 passed the 12
ProviderRatingsTests cases. Not compiled yet: a review pass after that run (OMDb without a
type, one key owner on both screens) and the calendar sources of 7 November (source
switcher with All upcoming, My Trakt, Trakt anticipated and Anime, empty-month texts,
Watchlist only).

Figures above are the 5 November refresh (first audit, 4 November: 38.3 % weighted,
25.0 % ported only, 51.6 % ported or partial): the Rust trust/parser/types core
was synced with Desktop and sleep timer, A-B loop, auto-skip, custom speeds,
stream languages, pasted magnet/direct links, the "Still watching?" check-in,
Desktop's default player hotkeys, the Watch on providers and the AniList and
MyAnimeList trackers (sign-in, token refresh, progress sync) were ported. All of it is read
from code and uncompiled; the focused CI run that compiles it is described in
the plan.

Usefulness review (7 November, owner's rule: port only what is useful on iPhone and iPad). 19 behaviors
and 60 settings that had no real use on a phone or tablet moved from Missing to Excluded, each with its
reason in the audit script: frame grab, advanced mpv fields, motion interpolation and Anime4K, GIF recording,
scheduled DVR (iOS cannot record in the background), webhooks, song identification (no system audio capture),
desktop skinning of the player, seek bar and glass effects, game controller cursor settings, serving the web
interface, desktop hotkeys, fullscreen clock and top bar styling, Cloudflare relay deployment, UI sounds and
UI scale. The percentages rise because those items left the denominator (209 excluded in all), not because
anything new was ported: 50.9 % weighted, 35.4 % ported only, 66.5 % ported or partial. Remaining Missing items
are the ones judged useful on iPhone or iPad, such as casting, Watch Together, Letterboxd, AniList and MAL lists.

Behaviors by area (weighted, P = ½; refreshed 5 November where it changed):

| Area                                                              | Ported | Partial | Missing | Excluded | Weighted |
| ----------------------------------------------------------------- | -----: | ------: | ------: | -------: | -------: |
| Resolution and Debrid                                             |     18 |      10 |       0 |        1 |   82.1 % |
| Stream pipeline, parser, trust and scoring                        |     31 |       5 |       3 |        0 |   85.9 % |
| Player, subtitles, skip, trailers and downloads                   |     28 |      20 |      13 |        2 |   62.3 % |
| Addons and catalogs                                               |      4 |      14 |       2 |        0 |   55.0 % |
| Details and episodes                                              |      4 |      10 |       1 |        0 |   60.0 % |
| Home, Discover and rooms                                          |      2 |      18 |       1 |        0 |   52.4 % |
| Manga, Sports, Music, VOD details, Home customization, Spooktober |      0 |      72 |       0 |        0 |   50.0 % |
| Subtitle source FPS correction                                    |      0 |       1 |       0 |        0 |   50.0 % |
| Stremio account, library and local files                          |      4 |       6 |       4 |        0 |   50.0 % |
| Metadata providers, calendar and lists                            |      7 |       8 |       4 |        0 |   57.9 % |
| Trackers                                                          |     13 |      11 |       7 |        0 |   59.7 % |
| Profiles, appearance, integrations and system                     |     10 |      12 |      15 |        5 |   43.2 % |
| Live TV, VOD, DVR and multiview                                   |      0 |      12 |      10 |        0 |   27.3 % |
| Search                                                            |      1 |       6 |       4 |        0 |   36.4 % |
| Casting and Watch Together                                        |      0 |       1 |      20 |        0 |    2.4 % |
| Torrent engine and streaming server                               |      0 |       0 |       4 |       14 |    0.0 % |

## How to read it

- **Not a measure of effort.** Every item weighs the same: "Torrent
  statistics" counts as much as "Native libmpv playback", and a rating-badge
  toggle as much as the stream filter.
- **Partial is a wide bucket.** 206 behaviors are Partial, many because an
  earlier review said so. Manga, Sports, Music, VOD details, Home customization
  and Spooktober were
  not re-read item by item and sit at 50 %; some of them are probably close to
  complete. The honest range is therefore 31 % (ported only) to 58 % (ported or
  partial) overall, with 44 % as the weighted figure.
- **Settings lag behind behaviors.** Most missing settings are fine-grained
  Desktop options: rating chips on cards (9), controllers (12),
  hero/trailer layout (8), fullscreen clock (7), Anime4K and shaders (11),
  advanced subtitle auto-sync (7), AniList/MAL (8), AI and song ID (11).
- **Code, not runtime.** Nothing written since the last successful Apple build
  (run 41849651852) has been compiled: Debrid, the streaming sources panel,
  progressive results and the filtered picker are counted as ported on code
  reading alone.
- **The inventory leaves out a whole Desktop room.** E-books is a room in
  Desktop but has no behaviors in the inventory, and its own note asks for
  review of further source modules. The e-book work done on iOS is therefore
  not counted, and the true figure can be off in either direction.

## Findings worth acting on

1. **The iOS Rust core is behind Desktop 0.9.132.** `trust.rs` was about 219
   lines short and `parser.rs` about 94. With the picker now filtered, these
   differences decide which sources users see:
   - **Uncached markers (fixed in this commit, uncompiled).** iOS rejected any
     result with ⬇ ⏳ ⌛ ⏬ 🔽 📥 ☁ in its title, name or description as
     `addon-uncached-emoji` under Strict and Balanced. Desktop 0.9.132 removed
     that rule (its test is now `does_not_hard_reject_uncached_emoji`), and
     AIOStreams marks uncached results this way, so the filtered picker would
     have hidden them. The rule is replaced by Desktop's `known-fake-group`
     check (LAMA, DJT, TELLY, RUDE, TELESYNC, DragonMoney) with its tests.
   - **Still behind:** the anime title gate on `expectedTitles`, the
     fresh-cinema fake-web check, episode ranges in the episode check,
     `NUMBER_NAME_TAIL_RX`, multi-episode spans (`episode_end`) and sizes with
     thousands separators in the parser.
   - Syncing `harbor-core` with the reference (keeping the iOS-only
     `DebridFlags`, `cache_verified` and modules) is the next step; CI's Rust
     step can compile it.
2. **Whole features still missing:** Watch Together and relay, casting
   (Chromecast, DLNA, Roku), AniList, MyAnimeList, Letterboxd, remote Stremio
   streaming server, DVR and multiview (feasibility undecided), AI search,
   webhooks, Theme Studio, hotkeys and controllers, trickplay previews,
   Anime4K, sleep timer, A/B loop, stats overlay.
3. **Search** is the weakest everyday area: no people, Live TV, direct URL,
   magnet or guide search.
