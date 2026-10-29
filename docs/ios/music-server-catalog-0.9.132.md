# Private music server catalog and connection screen

This slice connects the profile-owned Navidrome/Subsonic service to the existing Music catalog. Music → Options → Media servers opens the URL, username and password form. A successful connection reloads discovery and search. Disconnecting removes the saved pairing and invalidates combined search results; public catalog rows can remain visible during the reload.

Apple run 40874840049, source `9b81c8caca3758a06efd9db92a2b4e955cb263b7`, executed eight cases: seven passed and one failed. It introduced zero compiler warnings; the earlier service Sendable warning is resolved and its affected fan-out case passed. The failure was a timing-dependent concurrency assertion that sampled whether an 80 ms delay had finished. The repaired test now requires both sources to arrive at a shared barrier before either can return, then separately verifies partial results and the browse deadline.

All four original form/connected images were individually inspected. Their headings, fields, account/status and actions fit at 390 × 844 and 834 × 1194. The mount emitted one appearance-transition warning, so its harness now keeps one hosting controller, changes its root content without animations and lets the window finish disappearing. Only that affected mount and the failed concurrency method are selected again. The other six passes remain retained. This does not certify ordinary application navigation or physical iPad use.

The original 163,386-byte archive has SHA-256 `6a735daf463787a6dbd11214c64dc10576114b25eb818def03d37c09f31d4510`, matching GitHub's digest. Its result remains partial until the two necessary follow-ups pass without new appearance warnings.

## Desktop behavior preserved

- The exact reference is `0834340cec5531650bfe78cd628628702e636987` (Desktop 0.9.132). The fixture authenticates six original Rust modules against committed Git blobs, allowing only checkout line ending differences. This does not claim execution of those Rust modules.
- Discovery uses the original 12 second browse budget for each source. Anonymous and server queries run concurrently. Failed sources do not remove successful rows; catalog rows precede Subsonic rows, with the first duplicate row identifier retained.
- Combined typed search follows `rows::merge_typed_results`: round robin recordings deduplicated by trimmed lowercase title/artist, album identity by title/artist, artist identity by name, and playlist identity by name/connector. Each category has its own limit. The first available top result remains independent of track interleaving.
- An offline private server is omitted from search while anonymous discovery is available. The server's own Home requests can still refresh its health. Private album, artist and playlist references always use that server; they cannot be sent to an anonymous metadata API.
- The Subsonic artist catalog follows the original default: limited top tracks, no fabricated album catalog or pagination. Artist discovery rows remain empty as in the pinned connector.
- Profile activation and credential version are checked before and after asynchronous delivery, including anonymous results inside the combined route. Disposed routes reject new operations. Closing an unfinished form invalidates its connection attempt and clears its password; a late response cannot persist it. Failed disconnect writes preserve the existing pairing.
- All 23 interface labels resolve in all 16 native language bundles. The original connector contains six server row identifiers absent from all pinned Desktop locale catalogs. Explicit native translations fix those six labels instead of displaying their internal identifiers. Other existing translations are preserved.

## Still open

This screen covers Navidrome/Subsonic, not the full Desktop Connections interface. Other music services, complete source selection, shared remote audio playback, mixed playlist interfaces and the ordinary application journey remain separate work. Server rows and connection capability metadata do not certify audio playback. No private server has been contacted in these owned transport tests, no real account is bundled, and no IPA is produced by the validation slice.
