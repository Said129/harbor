# WOFF and WOFF2 reader fonts — pending native validation

The same document picker now imports TTF, OTF, WOFF and WOFF2, with Desktop's
32 MiB input limit. The pinned pure-Rust wuff 0.2.9 decoder reconstructs a local
OpenType font. No font bytes go to a server or through the JSON bridge. An additive
decode/free C interface transfers one owned byte buffer to Swift Data; Core
Graphics validates the result before the protected per-profile store publishes
it. Existing TTF/OTF bytes still use their original path.

WOFF table lengths are checked before allocation. Decoded output is bounded to
128 MiB, including wuff's WOFF2 decompression and reconstruction limits. The
wrapper repairs the SFNT checksum adjustment. Failed imports retain the prior
font and the reader's ordinary fallback. wuff and the two new Brotli allocator
dependencies have their exact notices bundled with the app and available from
About > Legal.

The tiny owned fixtures were drawn and generated for this project, rather than
copied from a commercial font. The WOFF2 fixture exercises transformed glyf,
loca and hmtx tables. Five new Rust contracts cover bounds, checksum repair,
ownership and both real formats. Two new Apple tests compare Core Text names,
glyphs, advances and actual rendered bitmap pixels against the owned source
font, then check that malformed input leaves the old font intact.

The `web-fonts` selection runs those two new native cases, two necessary fresh
preparations and two new UI routes. It also retries the four failed book detail
and reader display routes from runs 39768078426 and 39770691335, for ten actual
XCTest executions and thirty-six original captures. Seventeen approved model
tests and the previously accepted network guards are retained without replay.
Only the five new Rust tests run. The separate reading-navigation run is not
restarted or cancelled.

Local fontTools checks confirmed the original glyph maps and advances through
both compression formats. These checks are not Apple/Rust execution evidence.
Local Windows Cargo checks could not link build scripts because MSVC link.exe
was unavailable. Apple run 39850934986 compiled the production decoder and passed
`cargo check`; its newer Clippy rejected a constant-sized test iterator before
any Rust test or XCTest ran. The iterator now uses fixed arrays. Production code
and Cargo inputs are unchanged, so the successful check is retained. The affected
Clippy compilation, five unexecuted Rust contracts, actual Core Text execution
and rendered interface review remain required. The workflow offers
an Apple ARM host for this new scope; it does not change the app's iOS 17+
deployment target or claim a measured build-speed improvement.

Desktop's paginated renderer, annotations, translation, complete narration
controls and the rest of the full port remain in scope. No final IPA or complete
Desktop parity is claimed by this increment.
