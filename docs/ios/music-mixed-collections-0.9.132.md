# Mixed music collections

Playlists, Saved and Recently played now resolve full recording metadata from the profile-owned shared document, falling back to actual imported records. A remote recording is displayed and played as a remote recording. A missing local file retains its metadata and membership without acquiring a fabricated local filename. A playlist store belonging to another owner cannot supply a personal collection or its playlist names.

The native playlist and personal collection screens use shared recording rows and the same player queue. Play uses the filtered listening order; local-only fallback preserves that order too. Reordering is available only without an active filter and with the stored track order selected. Removing a displayed item uses its actual recording identifier. The source/content menus, count, six sorts, search and persisted compact/list presentation are connected to real recording metadata. Saved/recent rows use the same full metadata, and recording context actions can save a remote track before adding its liked identifier.

The cover mosaic uses the first four distinct nonempty artwork sources. Three covers give the third cover the full bottom row, as Desktop. Genuine imported artwork can also occupy a tile. The add-tracks sheet combines saved and recent recordings, excludes existing playlist recordings and deduplicates using Desktop's normalized recording identity, including original collection credits.

## Original logic and local evidence

`MusicCollectionToolsAssets.json` authenticates five original inputs from `0834340cec5531650bfe78cd628628702e636987`. It executes the complete original `playlist-filters`, `source-label`, `track-identity` and `search-normalize` modules and the original `search-artists.artistCreditParts` function. It does not execute the other search-artists functions. The program is 15,261 bytes, SHA-256 `85a0e907ad1a5c61c7720dd421738f6027efa96012d2d77a681d25224b94e994`.

A separate Node reference executed those original functions and compared the native adapter across 60 cases: sort directions and unknown/tied fields, dates, recent order, content and source filters, multilingual/multiple search terms, supplied genre memberships, source labels, collection credits and saved/recent tray deduplication. All 60 local comparisons passed. Native filtering owns a JavaScriptCore context on a background actor; source labels are cached while the recording collection is unchanged. Cancelled filtering keeps the previous displayed collection. Search respects the source's 200 UTF-16-unit limit without cutting a native grapheme. Native list transitions use the source's 160 ms timing curve and respect Reduce Motion; this is not certification of all Desktop list animations.

The resource update selects 37 labels in 16 languages, with 592 expected comparisons. All other accepted labels, including all 432 comparisons in the pending shared-player slice, remain unchanged.

## Pending Apple execution

Four new functional cases cover the 60 original comparisons in Apple JavaScriptCore, owned mixed/personal metadata projection, cancelled filtering and native controls, and the 592 resource comparisons. A new independent mount requires eight original captures: playlist, compact rows, recently played and the actual add-tracks sheet at compact and regular sizes. It imports a genuine owned WAV and serves three distinct owned covers over loopback. It does not demonstrate an ordinary application journey, taps through every menu, or physical iPad behavior.

The earlier shared-player run `40912838875` never received a hosted runner and executed zero tests. GitHub annotations identify hosted ARM capacity constraints. Its immutable dispatch receipt and zero-execution proof are retained. The same eight cases ran through preparation on a supported Intel runner as run `40915769608`, pinned to source `d13be3d9bd6bee8caf4cf6a0de52cbcec37d09ca`. Application compilation passed, but test compilation stopped on an ambiguous `MusicTrack` return type imported through AVFoundation. All eight cases remained unexecuted. The return type is now qualified as `Harbor.MusicTrack`; an independently found label-fixture getter error is also fixed. No new compiler or appearance warnings were recorded.

The collected Intel evidence proves zero actual executions and contains no images. Its 46,361-byte archive SHA-256 is `2ef347149a3d9e6a922b4a5879864af23ad5a201b98bd9d1943a4f2f996ce353`, matching the GitHub artifact digest. The combined selection therefore includes the five new cases and those eight unexecuted cases. It expects 13 actual executions and 16 original captures, retaining 30 other nearby approved native contracts. The preflight requires the original terminal zero-execution proof; it cannot replace a live validation or replay passes from that run. No IPA is requested.

## Remaining parity

Genre filtering supports supplied source memberships, but the ordinary UI still lacks the original cached artist-tag producer and genre controls. Custom cover upload/removal, M3U transfer, playlist recommendations, sticky headings, inline like burst and remaining exact Desktop styling/animations are still open. The larger Music source-matching/provider/source-chooser/DSP/lyrics/checkpoint/casting scope also remains open. This improvement does not complete Music or the overall iOS/iPadOS port.
