# Original Billboard discovery on iPhone and iPad

The Explore entry opens the complete original 196-chart directory, including
track, album and artist charts. Country selection chooses a compatible chart;
search filters the current entries without changing their published positions.
The page shows the publication date and links to the dated primary source.
Native navigation preserves the loaded chart and scroll position when returning
from an entry. Data loads only when opening Billboard, not during application
startup or while using the local library.

The pinned Desktop 0.9.132 modules retain the DOM parser's chart identity and
date checks, duplicate rank rejection, allowed artwork origins, eight MiB page
budget and one-hour cache with a sixteen-chart limit. Album entries are resolved
only when exactly one catalog result matches the original normalized title and
artist. Artist entries use the preserved measured authority and namesake ranking.
Unavailable sources offer Retry and the original primary-source link.

`build-music-billboard-assets.mjs` verifies the six source hashes before packaging
the original algorithms. The native runtime verifies its program hash and binds
each worker to the active profile and activation. Only anonymous HTTPS GET
requests to Billboard and Deezer are accepted, with public-network checks.
The 13 original interface labels are included in all 16 Desktop languages.

The new validation selection covers actual WebKit parsing and identity rejection,
native HTTP cache/refresh/eviction/error recovery, unique album resolution,
network restrictions, retired profiles, late UI requests and the real public
Hot 100. New iPhone and iPad journeys require ranks, detail navigation, album
chart, local search, country selection and return to the genre grid, with twelve
original captures. Existing approved native/Rust suites are retained.

Local generation and dispatch checks are not Apple execution or visual approval.
Music connectors, connected playback, video/event discovery, recommendations,
other original surfaces and the final full-port audit remain separate pending
work. This block does not produce an IPA or certify complete Music parity.

The first Apple run found that the original `DOMParser` is unavailable in a
worker. Billboard now uses the document host already used for trusted HTML
sources. Native code admits only the exact bundled, hash-verified Billboard
program to this mode; installed plugins continue to use workers. The document
keeps its nonpersistent store and restrictive content policy, and its requests
still pass through the same native network and profile guards.

The narrow follow-up selects four original failed native cases, the album
resolver affected by this hosting change, and the two unfinished UI journeys.
The unaffected Billboard model result is retained. If the real primary-source
request is denied, the failed public case now records only that public host's
numeric DNS answers to distinguish source availability from a routing problem.
It does not relax public-network checks.
