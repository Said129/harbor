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
| Behaviors |   438 |    106 |     203 |     107 |       22 |           49.9 % |      25.5 % |            74.3 % |
| Settings  |   511 |    104 |      21 |     300 |       86 |           26.9 % |      24.5 % |            29.4 % |
| All       |   949 |    210 |     224 |     407 |      108 |           38.3 % |      25.0 % |            51.6 % |

Behaviors by area (weighted, P = ½):

| Area                                                              | Ported | Partial | Missing | Excluded | Weighted |
| ----------------------------------------------------------------- | -----: | ------: | ------: | -------: | -------: |
| Resolution and Debrid                                             |     18 |      10 |       0 |        1 |   82.1 % |
| Stream pipeline, parser, trust and scoring                        |     24 |      11 |       4 |        0 |   75.6 % |
| Player, subtitles, skip, trailers and downloads                   |     24 |      20 |      17 |        2 |   55.7 % |
| Addons and catalogs                                               |      4 |      14 |       2 |        0 |   55.0 % |
| Details and episodes                                              |      3 |      10 |       2 |        0 |   53.3 % |
| Home, Discover and rooms                                          |      2 |      18 |       1 |        0 |   52.4 % |
| Manga, Sports, Music, VOD details, Home customization, Spooktober |      0 |      72 |       0 |        0 |   50.0 % |
| Subtitle source FPS correction                                    |      0 |       1 |       0 |        0 |   50.0 % |
| Stremio account, library and local files                          |      4 |       6 |       4 |        0 |   50.0 % |
| Metadata providers, calendar and lists                            |      7 |       5 |       7 |        0 |   50.0 % |
| Trackers                                                          |     10 |       7 |      14 |        0 |   43.5 % |
| Profiles, appearance, integrations and system                     |     10 |      11 |      16 |        5 |   41.9 % |
| Live TV, VOD, DVR and multiview                                   |      0 |      12 |      10 |        0 |   27.3 % |
| Search                                                            |      0 |       5 |       6 |        0 |   22.7 % |
| Casting and Watch Together                                        |      0 |       1 |      20 |        0 |    2.4 % |
| Torrent engine and streaming server                               |      0 |       0 |       4 |       14 |    0.0 % |

## How to read it

- **Not a measure of effort.** Every item weighs the same: "Torrent
  statistics" counts as much as "Native libmpv playback", and a rating-badge
  toggle as much as the stream filter.
- **Partial is a wide bucket.** 203 behaviors are Partial, many because an
  earlier review said so. Manga, Sports, Music, VOD details, Home customization
  and Spooktober were
  not re-read item by item and sit at 50 %; some of them are probably close to
  complete. The honest range is therefore 25 % (ported only) to 52 % (ported or
  partial) overall, with 38 % as the weighted figure.
- **Settings lag behind behaviors.** Most missing settings are fine-grained
  Desktop options: rating badges and detail ratings (22), controllers (12),
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
